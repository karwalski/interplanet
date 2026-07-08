// Package ltx — LTX v1.1 core subset (Epic 72, Story 72.2).
//
// Implements the five v1.1 cascade features, mirroring the TypeScript
// reference implementation (typescript/ltx/src):
//  1. v3 planId + PairDelay + ComputeSegmentsFor      (segments.ts)
//  2. Transition() session state machine (pure core)  (session.ts)
//  3. Amendment-chain verification                    (amend.ts)
//  4. Register entries + reducers + Merkle root       (registers.ts / merkle.ts)
//  5. CBOR decode + COSE_Sign1 verify                 (cbor.ts / cose.ts)
package ltx

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strings"
)

// ── Feature 1: pair delays and viewer-perspective segments ──────────────────

// PairDelay returns the one-way delay in seconds between two nodes
// (LTX-SPECIFICATION.md §3.7). The v3 pair matrix (plan.Delays, key "A|B"
// with ids sorted) is authoritative where present; otherwise the conservative
// fallback: HOST pairs use the node's declared delay, non-HOST pairs the sum
// of both HOST-relative delays.
func PairDelay(plan LtxPlan, nodeIdA, nodeIdB string) (int, error) {
	if nodeIdA == nodeIdB {
		return 0, nil
	}
	if plan.Delays != nil {
		pair := []string{nodeIdA, nodeIdB}
		sort.Strings(pair)
		if d, ok := plan.Delays[strings.Join(pair, "|")]; ok {
			return d, nil
		}
	}
	var a, b *LtxNode
	for i := range plan.Nodes {
		if plan.Nodes[i].ID == nodeIdA {
			a = &plan.Nodes[i]
		}
		if plan.Nodes[i].ID == nodeIdB {
			b = &plan.Nodes[i]
		}
	}
	if a == nil {
		return 0, fmt.Errorf("pairDelay: unknown node %s", nodeIdA)
	}
	if b == nil {
		return 0, fmt.Errorf("pairDelay: unknown node %s", nodeIdB)
	}
	hostID := plan.Nodes[0].ID
	if nodeIdA == hostID {
		return b.Delay, nil
	}
	if nodeIdB == hostID {
		return a.Delay, nil
	}
	return a.Delay + b.Delay, nil
}

// LtxViewerSegment is a computed segment from a specific viewer's perspective
// (LTX-SPECIFICATION.md §14.3).
type LtxViewerSegment struct {
	Type    string
	Q       int
	StartMs int64
	EndMs   int64
	DurMin  int
	// Speaker is the presenting node id when the segment is attributed.
	Speaker string
	// Label is the agenda label, when present.
	Label string
	// Perspective is "transmit" (viewer presents), "receive" (arrives after
	// light-time) or "neutral".
	Perspective string
	// ArrivalOffsetS is the light-time shift applied to start/end, in seconds
	// (0 unless receiving).
	ArrivalOffsetS int
}

// ComputeSegmentsFor computes the timed segment array from viewer V's
// perspective (LTX-SPECIFICATION.md §14.3): a segment attributed to speaker S
// starts for V at segStart + PairDelay(S, V). Unattributed segments keep
// their times.
func ComputeSegmentsFor(plan LtxPlan, viewerNodeID string) ([]LtxViewerSegment, error) {
	known := false
	for _, n := range plan.Nodes {
		if n.ID == viewerNodeID {
			known = true
			break
		}
	}
	if !known {
		return nil, fmt.Errorf("computeSegmentsFor: unknown viewer %s", viewerNodeID)
	}
	base, err := ComputeSegments(plan)
	if err != nil {
		return nil, err
	}
	out := make([]LtxViewerSegment, 0, len(base))
	for i, seg := range base {
		tpl := plan.Segments[i]
		vs := LtxViewerSegment{
			Type: seg.Type, Q: seg.Q, StartMs: seg.StartMs, EndMs: seg.EndMs,
			DurMin: seg.DurMin, Speaker: tpl.Speaker, Label: tpl.Label,
			Perspective: "neutral", ArrivalOffsetS: 0,
		}
		if tpl.Speaker != "" && (tpl.Type == "TX" || tpl.Type == "SPEAK") {
			if tpl.Speaker == viewerNodeID {
				vs.Perspective = "transmit"
			} else {
				shiftS, err := PairDelay(plan, tpl.Speaker, viewerNodeID)
				if err != nil {
					return nil, err
				}
				vs.Perspective = "receive"
				vs.ArrivalOffsetS = shiftS
				vs.StartMs += int64(shiftS) * 1000
				vs.EndMs += int64(shiftS) * 1000
			}
		}
		out = append(out, vs)
	}
	return out, nil
}

// ── Feature 2: session state machine (LTX-SPECIFICATION.md §5) ──────────────

// Session lifecycle states for the v1.1 state machine.
const (
	SessionStateDraft         SessionState = "DRAFT"
	SessionStateLocking       SessionState = "LOCKING"
	SessionStateActive        SessionState = "ACTIVE"
	SessionStateEmergencyHold SessionState = "EMERGENCY_HOLD"
	SessionStateAborted       SessionState = "ABORTED"
)

// LockKind is the plan-lock kind: LockNone, LockFull or LockQuorum.
type LockKind string

const (
	LockNone   LockKind = ""
	LockFull   LockKind = "FULL"
	LockQuorum LockKind = "QUORUM"
)

// Session event types accepted by Transition().
const (
	EventStartLock          = "START_LOCK"
	EventPlanConfirm        = "PLAN_CONFIRM"
	EventTick               = "TICK"
	EventSessionStart       = "SESSION_START"
	EventDelayMeasured      = "DELAY_MEASURED"
	EventEokOverride        = "EOK_OVERRIDE"
	EventAmendmentProposed  = "AMENDMENT_PROPOSED"
	EventAmendmentConfirmed = "AMENDMENT_CONFIRMED"
	EventHostDecision       = "HOST_DECISION"
	EventSessionEnd         = "SESSION_END"
)

// SessionEvent is a time-injected state machine event; NowMs always carries
// the caller's clock so Transition() stays pure.
type SessionEvent struct {
	Type            string
	NowMs           int64
	NodeID          string
	PlanID          string
	MeasuredDelayS  float64
	Verified        bool
	Reason          string
	PlanVersion     int
	AffectedNodeIDs []string
	Decision        string // "continue" | "abort" | "resume"
}

// SessionEffect is a side-effect command returned by Transition(); the caller
// executes it. Kind is "audit", "notify" or "escalate".
type SessionEffect struct {
	Kind   string
	Level  string // notify: "info" | "warn" | "error"
	Code   string
	Detail string
	// Audit fields (state_transition entries, LTX-SECURITY.md §9.6).
	From  SessionState
	To    SessionState
	Event string
	AtMs  int64
}

// PendingAmendment tracks a proposed-but-unconfirmed amendment (§6.4).
type PendingAmendment struct {
	PlanID          string
	PlanVersion     int
	AffectedNodeIDs []string
	Confirmed       []string
	ProposedAtMs    int64
	TimeoutMs       int64
}

// SessionContext is the full state of one session state machine.
type SessionContext struct {
	State             SessionState
	Plan              LtxPlan
	PlanID            string
	SessionRootPlanID string
	PlanVersion       int
	Lock              LockKind
	LockStartedAtMs   int64 // -1 = not started
	LockTimeoutMs     int64
	Confirmations     map[string]string // nodeId → confirmed planId
	Mismatched        []string
	QuorumThreshold   int
	Subset            []string // nil = all nodes
	DegradedReasons   []string
	ResumeState       SessionState // "" = none
	PendingAmendment  *PendingAmendment
}

// SessionOptions configures CreateSession. QuorumCount > 0 sets an absolute
// threshold; otherwise Quorum is "majority" or "all" (default).
type SessionOptions struct {
	Quorum      string
	QuorumCount int
}

func sessionParticipants(plan LtxPlan) []LtxNode {
	out := make([]LtxNode, 0, len(plan.Nodes))
	for _, n := range plan.Nodes {
		if n.Role == "PARTICIPANT" {
			out = append(out, n)
		}
	}
	return out
}

// LockTimeoutMs returns 2 × one-way delay to the furthest node, in ms
// (LTX-SPECIFICATION.md §5.1).
func LockTimeoutMs(plan LtxPlan) int64 {
	maxDelayS := 0
	for _, n := range plan.Nodes {
		if n.Delay > maxDelayS {
			maxDelayS = n.Delay
		}
	}
	return int64(DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR) * int64(maxDelayS) * 1000
}

func quorumCount(plan LtxPlan, opts SessionOptions) int {
	total := len(sessionParticipants(plan))
	if opts.QuorumCount > 0 {
		qc := opts.QuorumCount
		if qc < 1 {
			qc = 1
		}
		if qc > total {
			qc = total
		}
		return qc
	}
	if opts.Quorum == "majority" {
		return total/2 + 1
	}
	return total // "all" (default)
}

// CreateSession creates a session context in DRAFT state. planID is supplied
// by the caller (MakePlanID) so this module stays pure.
func CreateSession(plan LtxPlan, planID string, opts SessionOptions) SessionContext {
	planVersion := plan.PlanVersion
	if planVersion == 0 {
		planVersion = 1
	}
	return SessionContext{
		State:             SessionStateDraft,
		Plan:              plan,
		PlanID:            planID,
		SessionRootPlanID: planID,
		PlanVersion:       planVersion,
		Lock:              LockNone,
		LockStartedAtMs:   -1,
		LockTimeoutMs:     LockTimeoutMs(plan),
		Confirmations:     map[string]string{},
		Mismatched:        nil,
		QuorumThreshold:   quorumCount(plan, opts),
		Subset:            nil,
		DegradedReasons:   nil,
		ResumeState:       "",
		PendingAmendment:  nil,
	}
}

// Ascending-delay fallback ordering over confirmed participants (§5.3).
func confirmedSubset(ctx SessionContext) []string {
	confirmed := make([]LtxNode, 0)
	for _, n := range sessionParticipants(ctx.Plan) {
		if ctx.Confirmations[n.ID] == ctx.PlanID {
			confirmed = append(confirmed, n)
		}
	}
	sort.SliceStable(confirmed, func(i, j int) bool { return confirmed[i].Delay < confirmed[j].Delay })
	out := []string{ctx.Plan.Nodes[0].ID}
	for _, n := range confirmed {
		out = append(out, n.ID)
	}
	return out
}

func fullLockReached(ctx SessionContext) bool {
	for _, n := range sessionParticipants(ctx.Plan) {
		if ctx.Confirmations[n.ID] != ctx.PlanID {
			return false
		}
	}
	return true
}

func quorumReached(ctx SessionContext) bool {
	confirmed := 0
	for _, n := range sessionParticipants(ctx.Plan) {
		if ctx.Confirmations[n.ID] == ctx.PlanID {
			confirmed++
		}
	}
	return confirmed >= ctx.QuorumThreshold
}

// Declared one-way delay for a node: v3 pair matrix HOST row, else node delay.
// Returns (delay, true) or (0, false) for an unknown node.
func declaredDelayS(plan LtxPlan, nodeID string) (int, bool) {
	var node *LtxNode
	for i := range plan.Nodes {
		if plan.Nodes[i].ID == nodeID {
			node = &plan.Nodes[i]
			break
		}
	}
	if node == nil {
		return 0, false
	}
	if plan.Delays != nil {
		pair := []string{plan.Nodes[0].ID, nodeID}
		sort.Strings(pair)
		if d, ok := plan.Delays[strings.Join(pair, "|")]; ok {
			return d, true
		}
	}
	return node.Delay, true
}

func cloneCtx(ctx SessionContext) SessionContext {
	next := ctx
	next.Confirmations = make(map[string]string, len(ctx.Confirmations))
	for k, v := range ctx.Confirmations {
		next.Confirmations[k] = v
	}
	next.Mismatched = append([]string(nil), ctx.Mismatched...)
	next.Subset = append([]string(nil), ctx.Subset...)
	next.DegradedReasons = append([]string(nil), ctx.DegradedReasons...)
	if ctx.PendingAmendment != nil {
		pa := *ctx.PendingAmendment
		pa.AffectedNodeIDs = append([]string(nil), ctx.PendingAmendment.AffectedNodeIDs...)
		pa.Confirmed = append([]string(nil), ctx.PendingAmendment.Confirmed...)
		next.PendingAmendment = &pa
	}
	return next
}

func auditEffect(from, to SessionState, ev SessionEvent, detail string) SessionEffect {
	return SessionEffect{Kind: "audit", From: from, To: to, Event: ev.Type, AtMs: ev.NowMs, Detail: detail}
}

func notifyEffect(level, code, detail string) SessionEffect {
	return SessionEffect{Kind: "notify", Level: level, Code: code, Detail: detail}
}

func escalateEffect(code, detail string) SessionEffect {
	return SessionEffect{Kind: "escalate", Code: code, Detail: detail}
}

func invalidEffect(ctx SessionContext, ev SessionEvent) SessionEffect {
	return notifyEffect("warn", "INVALID_EVENT", fmt.Sprintf("%s ignored in state %s", ev.Type, ctx.State))
}

func moved(ctx SessionContext, to SessionState, ev SessionEvent, effects []SessionEffect, detail string) (SessionContext, []SessionEffect) {
	all := append([]SessionEffect{auditEffect(ctx.State, to, ev, detail)}, effects...)
	ctx.State = to
	return ctx, all
}

func degrade(ctx SessionContext, ev SessionEvent, reason string) (SessionContext, []SessionEffect) {
	next := cloneCtx(ctx)
	next.DegradedReasons = append(next.DegradedReasons, reason)
	effects := []SessionEffect{
		notifyEffect("warn", "DEGRADED", reason),
		escalateEffect("DEGRADED", reason),
	}
	if ctx.State == SessionStateDegraded {
		return next, effects[:1] // already degraded: notify only
	}
	return moved(next, SessionStateDegraded, ev, effects, reason)
}

// Transition advances the session state machine. Pure: the same (ctx, event)
// always yields the same result; ctx is not mutated.
func Transition(ctx SessionContext, ev SessionEvent) (SessionContext, []SessionEffect) {
	switch ev.Type {
	case EventStartLock:
		if ctx.State != SessionStateDraft {
			return ctx, []SessionEffect{invalidEffect(ctx, ev)}
		}
		next := cloneCtx(ctx)
		next.LockStartedAtMs = ev.NowMs
		next.Confirmations[ctx.Plan.Nodes[0].ID] = ctx.PlanID
		return moved(next, SessionStateLocking, ev, nil, "")

	case EventPlanConfirm:
		if ctx.State != SessionStateLocking && ctx.State != SessionStateDegraded {
			return ctx, []SessionEffect{invalidEffect(ctx, ev)}
		}
		next := cloneCtx(ctx)
		next.Confirmations[ev.NodeID] = ev.PlanID
		if ev.PlanID != ctx.PlanID {
			next.Mismatched = appendUnique(removeString(next.Mismatched, ev.NodeID), ev.NodeID)
			return next, []SessionEffect{notifyEffect("warn", "PLANID_MISMATCH",
				fmt.Sprintf("%s confirmed %s, expected %s (resolve per §5.5)", ev.NodeID, ev.PlanID, ctx.PlanID))}
		}
		next.Mismatched = removeString(next.Mismatched, ev.NodeID)
		if fullLockReached(next) {
			next.Lock = LockFull
			next.Subset = nil
			// Late full confirmation recovers a DEGRADED quorum lock (§5.2).
			return moved(next, SessionStateLocked, ev, []SessionEffect{
				notifyEffect("info", "LOCKED", "full lock achieved"),
			}, "")
		}
		return next, nil

	case EventTick:
		if ctx.State != SessionStateLocking {
			return ctx, nil
		}
		if ctx.LockStartedAtMs < 0 {
			return ctx, nil
		}
		if ev.NowMs-ctx.LockStartedAtMs < ctx.LockTimeoutMs {
			return ctx, nil
		}
		// Lock timeout expired (§5.1).
		if quorumReached(ctx) {
			subset := confirmedSubset(ctx)
			next := cloneCtx(ctx)
			next.Lock = LockQuorum
			next.Subset = subset
			missing := make([]string, 0)
			for _, n := range sessionParticipants(ctx.Plan) {
				if ctx.Confirmations[n.ID] != ctx.PlanID {
					missing = append(missing, n.ID)
				}
			}
			return degrade(next, ev, fmt.Sprintf("quorum lock with subset [%s]; unconfirmed: [%s]",
				strings.Join(subset, ","), strings.Join(missing, ",")))
		}
		return degrade(ctx, ev, "plan-lock timeout without quorum")

	case EventSessionStart:
		if ctx.State == SessionStateLocked {
			return moved(cloneCtx(ctx), SessionStateActive, ev, nil, "")
		}
		if ctx.State == SessionStateDegraded && ctx.Lock != LockNone {
			// §5.2: escalation to HOST required before TX.
			return ctx, []SessionEffect{escalateEffect("DEGRADED_START",
				"session start requested while DEGRADED; HOST decision required")}
		}
		return ctx, []SessionEffect{invalidEffect(ctx, ev)}

	case EventDelayMeasured:
		if ctx.State != SessionStateActive && ctx.State != SessionStateLocked && ctx.State != SessionStateDegraded {
			return ctx, nil
		}
		declared, ok := declaredDelayS(ctx.Plan, ev.NodeID)
		if !ok {
			return ctx, []SessionEffect{invalidEffect(ctx, ev)}
		}
		deviation := math.Abs(ev.MeasuredDelayS - float64(declared))
		if deviation > DELAY_VIOLATION_DEGRADED_S {
			return degrade(ctx, ev, fmt.Sprintf("delay violation %s: measured %gs vs declared %ds (>%ds)",
				ev.NodeID, ev.MeasuredDelayS, declared, DELAY_VIOLATION_DEGRADED_S))
		}
		if deviation > DELAY_VIOLATION_WARN_S {
			return ctx, []SessionEffect{notifyEffect("warn", "DELAY_VIOLATION",
				fmt.Sprintf("%s: measured %gs vs declared %ds", ev.NodeID, ev.MeasuredDelayS, declared))}
		}
		return ctx, nil

	case EventEokOverride:
		if ctx.State == SessionStateComplete || ctx.State == SessionStateAborted {
			return ctx, nil
		}
		if !ev.Verified {
			reason := ev.Reason
			if reason == "" {
				reason = "override failed verification"
			}
			return ctx, []SessionEffect{notifyEffect("error", "OVERRIDE_REJECTED", reason)}
		}
		if ctx.State == SessionStateEmergencyHold {
			return ctx, nil
		}
		next := cloneCtx(ctx)
		next.ResumeState = ctx.State
		reason := ev.Reason
		if reason == "" {
			reason = "verified EOK override"
		}
		return moved(next, SessionStateEmergencyHold, ev, []SessionEffect{
			notifyEffect("error", "EMERGENCY_HOLD", reason),
		}, "")

	case EventAmendmentProposed:
		if ctx.State != SessionStateActive && ctx.State != SessionStateLocked && ctx.State != SessionStateDegraded {
			return ctx, []SessionEffect{invalidEffect(ctx, ev)}
		}
		if ev.PlanVersion != ctx.PlanVersion+1 {
			return ctx, []SessionEffect{notifyEffect("error", "AMENDMENT_REJECTED",
				fmt.Sprintf("planVersion %d != %d + 1", ev.PlanVersion, ctx.PlanVersion))}
		}
		// Delta re-lock (§6.4): timeout scoped to the furthest affected node.
		maxDelayS := 0
		for _, n := range ctx.Plan.Nodes {
			if containsString(ev.AffectedNodeIDs, n.ID) && n.Delay > maxDelayS {
				maxDelayS = n.Delay
			}
		}
		next := cloneCtx(ctx)
		next.PendingAmendment = &PendingAmendment{
			PlanID:          ev.PlanID,
			PlanVersion:     ev.PlanVersion,
			AffectedNodeIDs: append([]string(nil), ev.AffectedNodeIDs...),
			Confirmed:       nil,
			ProposedAtMs:    ev.NowMs,
			TimeoutMs:       int64(DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR) * int64(maxDelayS) * 1000,
		}
		return next, []SessionEffect{notifyEffect("info", "AMENDMENT_PROPOSED",
			fmt.Sprintf("plan %s v%d; awaiting [%s]", ev.PlanID, ev.PlanVersion, strings.Join(ev.AffectedNodeIDs, ",")))}

	case EventAmendmentConfirmed:
		pa := ctx.PendingAmendment
		if pa == nil || ev.PlanID != pa.PlanID {
			return ctx, []SessionEffect{invalidEffect(ctx, ev)}
		}
		if !containsString(pa.AffectedNodeIDs, ev.NodeID) {
			return ctx, nil
		}
		next := cloneCtx(ctx)
		npa := next.PendingAmendment
		npa.Confirmed = appendUnique(removeString(npa.Confirmed, ev.NodeID), ev.NodeID)
		if len(npa.Confirmed) < len(npa.AffectedNodeIDs) {
			return next, nil
		}
		// All affected nodes confirmed — the amendment applies. The caller
		// swaps ctx.Plan for the verified successor (Transition tracks ids).
		next.PlanID = npa.PlanID
		next.PlanVersion = npa.PlanVersion
		next.PendingAmendment = nil
		return next, []SessionEffect{notifyEffect("info", "AMENDMENT_APPLIED",
			fmt.Sprintf("plan %s v%d in effect (root %s)", npa.PlanID, npa.PlanVersion, ctx.SessionRootPlanID))}

	case EventHostDecision:
		if ev.Decision == "abort" {
			if ctx.State == SessionStateComplete || ctx.State == SessionStateAborted {
				return ctx, nil
			}
			return moved(cloneCtx(ctx), SessionStateAborted, ev, nil, "")
		}
		if ev.Decision == "resume" && ctx.State == SessionStateEmergencyHold {
			back := ctx.ResumeState
			if back == "" {
				back = SessionStateActive
			}
			next := cloneCtx(ctx)
			next.ResumeState = ""
			return moved(next, back, ev, nil, "")
		}
		if ev.Decision == "continue" && ctx.State == SessionStateDegraded {
			// §5.2: HOST elects to continue with the confirmed subset.
			detail := "continuing despite degraded condition"
			if ctx.Subset != nil {
				detail = fmt.Sprintf("continuing with subset [%s]", strings.Join(ctx.Subset, ","))
			}
			return moved(cloneCtx(ctx), SessionStateActive, ev, []SessionEffect{
				notifyEffect("warn", "CONTINUE_DEGRADED", detail),
			}, "")
		}
		return ctx, []SessionEffect{invalidEffect(ctx, ev)}

	case EventSessionEnd:
		if ctx.State == SessionStateActive || ctx.State == SessionStateDegraded {
			return moved(cloneCtx(ctx), SessionStateComplete, ev, nil, "")
		}
		return ctx, []SessionEffect{invalidEffect(ctx, ev)}
	}
	return ctx, []SessionEffect{notifyEffect("warn", "INVALID_EVENT",
		fmt.Sprintf("unknown event %s in state %s", ev.Type, ctx.State))}
}

func containsString(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

func removeString(list []string, s string) []string {
	out := make([]string, 0, len(list))
	for _, x := range list {
		if x != s {
			out = append(out, x)
		}
	}
	return out
}

func appendUnique(list []string, s string) []string {
	if containsString(list, s) {
		return list
	}
	return append(list, s)
}

// ── Feature 3: amendment chains (LTX-SECURITY.md §7.6) ──────────────────────

// PlanHash returns the SHA-256 hex of the RFC 8785 canonical JSON of a plan.
// Order-insensitive and collision-resistant — never the legacy v2 polynomial
// planId hash.
func PlanHash(plan interface{}) string {
	digest := sha256.Sum256([]byte(CanonicalJSON(plan)))
	return fmt.Sprintf("%x", digest[:])
}

func toPlanMap(plan interface{}) map[string]interface{} {
	if m, ok := plan.(map[string]interface{}); ok {
		return m
	}
	data, err := json.Marshal(plan)
	if err != nil {
		return nil
	}
	var m map[string]interface{}
	if err := json.Unmarshal(data, &m); err != nil {
		return nil
	}
	return m
}

func planMapInt(m map[string]interface{}, key string, fallback int) int {
	v, ok := m[key]
	if !ok {
		return fallback
	}
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case int64:
		return int(n)
	case json.Number:
		i, err := n.Int64()
		if err != nil {
			return fallback
		}
		return int(i)
	}
	return fallback
}

// CreateAmendment creates a signed amendment of signedPlan with changes
// applied. The successor is always a v3 plan (LTX-SPECIFICATION.md §4.4);
// the fields managed here ("v", "planVersion", "prevPlanHash") cannot be
// overridden via changes.
func CreateAmendment(signedPlan SignedPlan, changes map[string]interface{}, privateKeyB64 string) (SignedPlan, error) {
	prev := toPlanMap(signedPlan.Plan)
	if prev == nil {
		return SignedPlan{}, fmt.Errorf("createAmendment: invalid predecessor plan")
	}
	successor := make(map[string]interface{}, len(prev)+3)
	for k, v := range prev {
		successor[k] = v
	}
	for k, v := range changes {
		successor[k] = v
	}
	successor["v"] = 3
	successor["planVersion"] = planMapInt(prev, "planVersion", 1) + 1
	successor["prevPlanHash"] = PlanHash(prev)
	return SignPlan(successor, privateKeyB64)
}

// VerifyAmendmentChain verifies an amendment chain: chain[0] is the root
// plan, each later element a successive amendment. Checks, per link: HOST
// signature against keyCache, planVersion increment of exactly 1, and
// prevPlanHash equality with the recomputed predecessor hash
// (LTX-SECURITY.md §7.6).
func VerifyAmendmentChain(chain []SignedPlan, keyCache map[string]NIK) VerifyResult {
	if len(chain) == 0 {
		return VerifyResult{Valid: false, Reason: "empty_chain"}
	}
	for i := range chain {
		sig := VerifyPlan(chain[i], keyCache)
		if !sig.Valid {
			return VerifyResult{Valid: false, Reason: fmt.Sprintf("link_%d_%s", i, sig.Reason)}
		}
	}
	root := toPlanMap(chain[0].Plan)
	if root == nil {
		return VerifyResult{Valid: false, Reason: "link_0_invalid_plan"}
	}
	if _, has := root["prevPlanHash"]; has {
		return VerifyResult{Valid: false, Reason: "root_has_prev_hash"}
	}
	prevPlan := chain[0].Plan
	prevVersion := planMapInt(root, "planVersion", 1)
	for i := 1; i < len(chain); i++ {
		p := toPlanMap(chain[i].Plan)
		if p == nil {
			return VerifyResult{Valid: false, Reason: fmt.Sprintf("link_%d_invalid_plan", i)}
		}
		if planMapInt(p, "v", 0) != 3 {
			return VerifyResult{Valid: false, Reason: fmt.Sprintf("link_%d_not_v3", i)}
		}
		if planMapInt(p, "planVersion", 0) != prevVersion+1 {
			return VerifyResult{Valid: false, Reason: fmt.Sprintf("link_%d_version_gap", i)}
		}
		prevHash, _ := p["prevPlanHash"].(string)
		if prevHash != PlanHash(prevPlan) {
			return VerifyResult{Valid: false, Reason: fmt.Sprintf("link_%d_prev_hash_mismatch", i)}
		}
		prevPlan = chain[i].Plan
		prevVersion = planMapInt(p, "planVersion", 0)
	}
	return VerifyResult{Valid: true}
}

// ── Feature 4: registers (LTX-SPECIFICATION.md §8–§10) ──────────────────────

// RegisterEntry is a signed audit-log entry (LTX-SECURITY.md §9.5 envelope).
type RegisterEntry struct {
	EntryId   string                 `json:"entryId"`
	SessionId string                 `json:"sessionId"`
	NodeId    string                 `json:"nodeId"`
	Seq       int                    `json:"seq"`
	Type      string                 `json:"type"`
	Content   map[string]interface{} `json:"content"`
	Timestamp string                 `json:"timestamp"`
	Sig       string                 `json:"sig"`
}

var entryPrefix = map[string]string{
	"question":          "QST",
	"question_response": "QST",
	"action":            "ACT",
	"action_update":     "ACT",
	"amendment":         "AMD",
	"state_transition":  "STA",
	"merge_snapshot":    "MRG",
	"decision":          "DEC",
}

// CreateEntryOptions holds options for CreateRegisterEntry.
type CreateEntryOptions struct {
	SessionId     string
	NodeId        string
	Seq           int
	Timestamp     string
	PrivateKeyB64 string
	// EntryId is an explicit id; defaults to "<PREFIX>-<nodeId>-<seq>".
	EntryId string
}

func entryUnsignedMap(e RegisterEntry) map[string]interface{} {
	return map[string]interface{}{
		"entryId":   e.EntryId,
		"sessionId": e.SessionId,
		"nodeId":    e.NodeId,
		"seq":       e.Seq,
		"type":      e.Type,
		"content":   e.Content,
		"timestamp": e.Timestamp,
	}
}

// CreateRegisterEntry creates a signed register entry (LTX-SECURITY.md §9.5).
// The signature covers the canonical JSON of the entry without "sig".
func CreateRegisterEntry(entryType string, content map[string]interface{}, opts CreateEntryOptions) (RegisterEntry, error) {
	entryID := opts.EntryId
	if entryID == "" {
		prefix, ok := entryPrefix[entryType]
		if !ok {
			return RegisterEntry{}, fmt.Errorf("createRegisterEntry: unknown type %s", entryType)
		}
		entryID = fmt.Sprintf("%s-%s-%d", prefix, opts.NodeId, opts.Seq)
	}
	entry := RegisterEntry{
		EntryId:   entryID,
		SessionId: opts.SessionId,
		NodeId:    opts.NodeId,
		Seq:       opts.Seq,
		Type:      entryType,
		Content:   content,
		Timestamp: opts.Timestamp,
	}
	rawSeed := b64urlDecodeBytes(opts.PrivateKeyB64)
	if len(rawSeed) != 32 {
		return RegisterEntry{}, fmt.Errorf("invalid private key: expected 32 bytes, got %d", len(rawSeed))
	}
	priv := ed25519.NewKeyFromSeed(rawSeed)
	msg := []byte(CanonicalJSON(entryUnsignedMap(entry)))
	entry.Sig = b64urlEncodeBytes(ed25519.Sign(priv, msg))
	return entry, nil
}

// VerifyRegisterEntry verifies a register entry signature against a keyCache
// mapping the entry's nodeId to its NIK.
func VerifyRegisterEntry(entry RegisterEntry, keyCache map[string]NIK) VerifyResult {
	if entry.Sig == "" {
		return VerifyResult{Valid: false, Reason: "missing_sig"}
	}
	nik, ok := keyCache[entry.NodeId]
	if !ok {
		return VerifyResult{Valid: false, Reason: "key_not_in_cache"}
	}
	rawPub := b64urlDecodeBytes(nik.PublicKey)
	if len(rawPub) != 32 {
		return VerifyResult{Valid: false, Reason: "invalid_public_key"}
	}
	msg := []byte(CanonicalJSON(entryUnsignedMap(entry)))
	if !ed25519.Verify(ed25519.PublicKey(rawPub), msg, b64urlDecodeBytes(entry.Sig)) {
		return VerifyResult{Valid: false, Reason: "signature_invalid"}
	}
	return VerifyResult{Valid: true}
}

// CompareEntries implements the §8.2 total order: (timestamp, nodeId, seq).
func CompareEntries(a, b RegisterEntry) int {
	if a.Timestamp != b.Timestamp {
		if a.Timestamp < b.Timestamp {
			return -1
		}
		return 1
	}
	if a.NodeId != b.NodeId {
		if a.NodeId < b.NodeId {
			return -1
		}
		return 1
	}
	return a.Seq - b.Seq
}

// OrderEntries de-duplicates by (nodeId, seq) and sorts into the §8.2 total
// order.
func OrderEntries(entries []RegisterEntry) []RegisterEntry {
	seen := make(map[string]bool, len(entries))
	out := make([]RegisterEntry, 0, len(entries))
	for _, e := range entries {
		key := fmt.Sprintf("%s %d", e.NodeId, e.Seq)
		if !seen[key] {
			seen[key] = true
			out = append(out, e)
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return CompareEntries(out[i], out[j]) < 0 })
	return out
}

// QuestionState is the reduced state of one question (§9.4).
type QuestionState struct {
	Qid            string
	Text           string
	Submitter      string
	Urgency        string
	IntendedWindow string
	Status         string // OPEN | ANSWERED | WITHDRAWN
	Response       string
	Responder      string
	Version        int
}

// ActionState is the reduced state of one action item (§10.2).
type ActionState struct {
	Aid          string
	Description  string
	Owner        string
	DueTimeUTC   string
	OriginWindow string
	Status       string // PROPOSED | ACCEPTED | REJECTED | DONE
	Version      int
}

type versioned struct {
	version int
	editor  string
	entryID string
}

// §8.2 conflict rule: higher version wins; tie → lowest editor nodeId.
func winsConflict(incoming, current versioned) bool {
	if incoming.version != current.version {
		return incoming.version > current.version
	}
	return incoming.editor < current.editor
}

func contentStr(c map[string]interface{}, key string) (string, bool) {
	v, ok := c[key]
	if !ok {
		return "", false
	}
	switch s := v.(type) {
	case string:
		return s, true
	case float64:
		return fmt.Sprintf("%g", s), true
	case bool:
		return fmt.Sprintf("%v", s), true
	}
	return "", false
}

// ReduceQuestions reduces the question register state from log entries
// (LTX-SPECIFICATION.md §9.4). Pure: identical entry sets in any input order
// produce identical state. Returns byId plus entryIds superseded per §8.2.
func ReduceQuestions(entries []RegisterEntry) (map[string]QuestionState, []string) {
	byID := map[string]QuestionState{}
	winners := map[string]versioned{}
	superseded := []string{}

	for _, e := range OrderEntries(entries) {
		switch e.Type {
		case "question":
			qid := e.EntryId
			if _, exists := byID[qid]; exists {
				superseded = append(superseded, e.EntryId)
				continue
			}
			winners[qid] = versioned{version: 1, editor: e.NodeId, entryID: e.EntryId}
			q := QuestionState{Qid: qid, Submitter: e.NodeId, Status: "OPEN", Version: 1}
			q.Text, _ = contentStr(e.Content, "text")
			q.Urgency, _ = contentStr(e.Content, "urgency")
			q.IntendedWindow, _ = contentStr(e.Content, "intendedWindow")
			byID[qid] = q
		case "question_response":
			qid, _ := contentStr(e.Content, "qid")
			q, exists := byID[qid]
			if !exists {
				superseded = append(superseded, e.EntryId)
				continue
			}
			version := planMapInt(e.Content, "version", q.Version+1)
			incoming := versioned{version: version, editor: e.NodeId, entryID: e.EntryId}
			current, hasCurrent := winners[qid]
			if hasCurrent && !winsConflict(incoming, current) {
				superseded = append(superseded, e.EntryId)
				continue
			}
			if hasCurrent && current.entryID != q.Qid {
				superseded = append(superseded, current.entryID)
			}
			winners[qid] = incoming
			status := "ANSWERED"
			if s, _ := contentStr(e.Content, "status"); s == "WITHDRAWN" {
				status = "WITHDRAWN"
			}
			q.Status = status
			if resp, ok := contentStr(e.Content, "response"); ok {
				q.Response = resp
			}
			q.Responder = e.NodeId
			q.Version = version
			byID[qid] = q
		}
	}
	return byID, superseded
}

var actionStatuses = map[string]bool{"PROPOSED": true, "ACCEPTED": true, "REJECTED": true, "DONE": true}

// ReduceActions reduces the action register state from log entries
// (LTX-SPECIFICATION.md §10.2).
func ReduceActions(entries []RegisterEntry) (map[string]ActionState, []string) {
	byID := map[string]ActionState{}
	winners := map[string]versioned{}
	superseded := []string{}

	for _, e := range OrderEntries(entries) {
		switch e.Type {
		case "action":
			aid := e.EntryId
			if _, exists := byID[aid]; exists {
				superseded = append(superseded, e.EntryId)
				continue
			}
			winners[aid] = versioned{version: 1, editor: e.NodeId, entryID: e.EntryId}
			a := ActionState{Aid: aid, Status: "PROPOSED", Version: 1}
			a.Description, _ = contentStr(e.Content, "description")
			a.Owner, _ = contentStr(e.Content, "owner")
			a.DueTimeUTC, _ = contentStr(e.Content, "dueTimeUTC")
			a.OriginWindow, _ = contentStr(e.Content, "originWindow")
			byID[aid] = a
		case "action_update":
			aid, _ := contentStr(e.Content, "aid")
			a, exists := byID[aid]
			if !exists {
				superseded = append(superseded, e.EntryId)
				continue
			}
			version := planMapInt(e.Content, "version", a.Version+1)
			incoming := versioned{version: version, editor: e.NodeId, entryID: e.EntryId}
			current, hasCurrent := winners[aid]
			if hasCurrent && !winsConflict(incoming, current) {
				superseded = append(superseded, e.EntryId)
				continue
			}
			if hasCurrent && current.entryID != a.Aid {
				superseded = append(superseded, current.entryID)
			}
			winners[aid] = incoming
			if s, _ := contentStr(e.Content, "status"); actionStatuses[s] {
				a.Status = s
			}
			if d, ok := contentStr(e.Content, "description"); ok {
				a.Description = d
			}
			if o, ok := contentStr(e.Content, "owner"); ok {
				a.Owner = o
			}
			if d, ok := contentStr(e.Content, "dueTimeUTC"); ok {
				a.DueTimeUTC = d
			}
			a.Version = version
			byID[aid] = a
		}
	}
	return byID, superseded
}

// ── Merkle log root (RFC 9162-style, story 28.5 hash scheme) ─────────────────

func merkleLeafHash(entryBytes []byte) []byte {
	buf := make([]byte, 1+len(entryBytes))
	buf[0] = 0x00
	copy(buf[1:], entryBytes)
	digest := sha256.Sum256(buf)
	return digest[:]
}

func merkleNodeHash(left, right []byte) []byte {
	buf := make([]byte, 1+64)
	buf[0] = 0x01
	copy(buf[1:33], left)
	copy(buf[33:], right)
	digest := sha256.Sum256(buf)
	return digest[:]
}

func merkleRootOf(leaves [][]byte) []byte {
	if len(leaves) == 0 {
		return make([]byte, 32)
	}
	if len(leaves) == 1 {
		return leaves[0]
	}
	// Largest power of two strictly less than len(leaves) (RFC 9162 §2.1).
	mid := 1
	for mid*2 < len(leaves) {
		mid *= 2
	}
	return merkleNodeHash(merkleRootOf(leaves[:mid]), merkleRootOf(leaves[mid:]))
}

// EntriesRoot returns the Merkle audit-log root (hex) over the §8.2-ordered
// entries: leaf = SHA-256(0x00 || canonicalJSON(entry)),
// node = SHA-256(0x01 || left || right); empty log root is 64 hex zeros.
func EntriesRoot(entries []RegisterEntry) string {
	ordered := OrderEntries(entries)
	leaves := make([][]byte, 0, len(ordered))
	for _, e := range ordered {
		leaves = append(leaves, merkleLeafHash([]byte(CanonicalJSON(e))))
	}
	return fmt.Sprintf("%x", merkleRootOf(leaves))
}

// ── Feature 5: CBOR (RFC 8949 deterministic subset) + COSE_Sign1 ────────────

// CborTag is a tagged CBOR value (major type 6).
type CborTag struct {
	Tag   uint64
	Value interface{}
}

// COSE constants (RFC 9052 / RFC 9864).
const (
	COSE_SIGN1_TAG   = 18
	COSE_ALG_ED25519 = -19
)

func cborEncodeHead(major byte, arg uint64) []byte {
	switch {
	case arg < 24:
		return []byte{major<<5 | byte(arg)}
	case arg < 0x100:
		return []byte{major<<5 | 24, byte(arg)}
	case arg < 0x10000:
		b := make([]byte, 3)
		b[0] = major<<5 | 25
		binary.BigEndian.PutUint16(b[1:], uint16(arg))
		return b
	case arg < 0x100000000:
		b := make([]byte, 5)
		b[0] = major<<5 | 26
		binary.BigEndian.PutUint32(b[1:], uint32(arg))
		return b
	default:
		b := make([]byte, 9)
		b[0] = major<<5 | 27
		binary.BigEndian.PutUint64(b[1:], arg)
		return b
	}
}

// EncodeCbor encodes a value to deterministic CBOR bytes (RFC 8949 §4.2.1:
// definite lengths, shortest-form heads, map keys sorted bytewise by encoded
// form). Supported: int/int64, []byte, string, []interface{},
// map[interface{}]interface{}, CborTag, bool, nil.
func EncodeCbor(value interface{}) ([]byte, error) {
	switch v := value.(type) {
	case nil:
		return []byte{0xf6}, nil
	case bool:
		if v {
			return []byte{0xf5}, nil
		}
		return []byte{0xf4}, nil
	case int:
		return EncodeCbor(int64(v))
	case int64:
		if v >= 0 {
			return cborEncodeHead(0, uint64(v)), nil
		}
		return cborEncodeHead(1, uint64(-v-1)), nil
	case string:
		return append(cborEncodeHead(3, uint64(len(v))), v...), nil
	case []byte:
		return append(cborEncodeHead(2, uint64(len(v))), v...), nil
	case CborTag:
		inner, err := EncodeCbor(v.Value)
		if err != nil {
			return nil, err
		}
		return append(cborEncodeHead(6, v.Tag), inner...), nil
	case []interface{}:
		out := cborEncodeHead(4, uint64(len(v)))
		for _, item := range v {
			enc, err := EncodeCbor(item)
			if err != nil {
				return nil, err
			}
			out = append(out, enc...)
		}
		return out, nil
	case map[interface{}]interface{}:
		type kv struct{ k, v []byte }
		pairs := make([]kv, 0, len(v))
		for key, val := range v {
			ek, err := EncodeCbor(key)
			if err != nil {
				return nil, err
			}
			ev, err := EncodeCbor(val)
			if err != nil {
				return nil, err
			}
			pairs = append(pairs, kv{ek, ev})
		}
		sort.Slice(pairs, func(i, j int) bool { return string(pairs[i].k) < string(pairs[j].k) })
		out := cborEncodeHead(5, uint64(len(pairs)))
		for _, p := range pairs {
			out = append(out, p.k...)
			out = append(out, p.v...)
		}
		return out, nil
	}
	return nil, fmt.Errorf("cbor: unsupported type %T", value)
}

type cborDecodeState struct {
	buf []byte
	pos int
}

func (s *cborDecodeState) readHead() (byte, uint64, error) {
	if s.pos >= len(s.buf) {
		return 0, 0, fmt.Errorf("cbor: truncated")
	}
	initial := s.buf[s.pos]
	s.pos++
	major := initial >> 5
	info := initial & 0x1f
	switch {
	case info < 24:
		return major, uint64(info), nil
	case info == 24:
		if s.pos+1 > len(s.buf) {
			return 0, 0, fmt.Errorf("cbor: truncated")
		}
		v := uint64(s.buf[s.pos])
		s.pos++
		return major, v, nil
	case info == 25:
		if s.pos+2 > len(s.buf) {
			return 0, 0, fmt.Errorf("cbor: truncated")
		}
		v := uint64(binary.BigEndian.Uint16(s.buf[s.pos:]))
		s.pos += 2
		return major, v, nil
	case info == 26:
		if s.pos+4 > len(s.buf) {
			return 0, 0, fmt.Errorf("cbor: truncated")
		}
		v := uint64(binary.BigEndian.Uint32(s.buf[s.pos:]))
		s.pos += 4
		return major, v, nil
	case info == 27:
		if s.pos+8 > len(s.buf) {
			return 0, 0, fmt.Errorf("cbor: truncated")
		}
		v := binary.BigEndian.Uint64(s.buf[s.pos:])
		s.pos += 8
		return major, v, nil
	}
	return 0, 0, fmt.Errorf("cbor: indefinite lengths not supported")
}

func (s *cborDecodeState) decodeItem(depth int) (interface{}, error) {
	if depth > 64 {
		return nil, fmt.Errorf("cbor: nesting too deep")
	}
	if s.pos >= len(s.buf) {
		return nil, fmt.Errorf("cbor: truncated")
	}
	switch s.buf[s.pos] {
	case 0xf6:
		s.pos++
		return nil, nil
	case 0xf5:
		s.pos++
		return true, nil
	case 0xf4:
		s.pos++
		return false, nil
	}
	major, arg, err := s.readHead()
	if err != nil {
		return nil, err
	}
	switch major {
	case 0:
		if arg > math.MaxInt64 {
			return nil, fmt.Errorf("cbor: integer too large")
		}
		return int64(arg), nil
	case 1:
		if arg > math.MaxInt64-1 {
			return nil, fmt.Errorf("cbor: integer too large")
		}
		return -int64(arg) - 1, nil
	case 2:
		if uint64(s.pos)+arg > uint64(len(s.buf)) {
			return nil, fmt.Errorf("cbor: truncated bstr")
		}
		out := append([]byte(nil), s.buf[s.pos:s.pos+int(arg)]...)
		s.pos += int(arg)
		return out, nil
	case 3:
		if uint64(s.pos)+arg > uint64(len(s.buf)) {
			return nil, fmt.Errorf("cbor: truncated tstr")
		}
		out := string(s.buf[s.pos : s.pos+int(arg)])
		s.pos += int(arg)
		return out, nil
	case 4:
		out := make([]interface{}, 0, arg)
		for i := uint64(0); i < arg; i++ {
			item, err := s.decodeItem(depth + 1)
			if err != nil {
				return nil, err
			}
			out = append(out, item)
		}
		return out, nil
	case 5:
		out := make(map[interface{}]interface{}, arg)
		for i := uint64(0); i < arg; i++ {
			k, err := s.decodeItem(depth + 1)
			if err != nil {
				return nil, err
			}
			// Byte-string keys hash as base64url so the map stays usable.
			if kb, ok := k.([]byte); ok {
				k = b64urlEncodeBytes(kb)
			}
			v, err := s.decodeItem(depth + 1)
			if err != nil {
				return nil, err
			}
			out[k] = v
		}
		return out, nil
	case 6:
		v, err := s.decodeItem(depth + 1)
		if err != nil {
			return nil, err
		}
		return CborTag{Tag: arg, Value: v}, nil
	}
	return nil, fmt.Errorf("cbor: unsupported major type %d / simple value", major)
}

// DecodeCbor decodes deterministic CBOR bytes to a value. Maps decode to
// map[interface{}]interface{} (byte-string keys as base64url strings);
// floats, indefinite lengths and trailing bytes are rejected.
func DecodeCbor(data []byte) (interface{}, error) {
	s := &cborDecodeState{buf: data}
	v, err := s.decodeItem(0)
	if err != nil {
		return nil, err
	}
	if s.pos != len(s.buf) {
		return nil, fmt.Errorf("cbor: trailing bytes")
	}
	return v, nil
}

// ── COSE_Sign1 (RFC 9052) ────────────────────────────────────────────────────

// CoseSignedPlan is a signed plan carrying the CBOR COSE_Sign1 envelope
// (base64url bytes).
type CoseSignedPlan struct {
	Plan             interface{} `json:"plan"`
	CoseSign1CborB64 string      `json:"coseSign1CborB64"`
}

func coseSigStructureBytes(protectedBytes, payload []byte) ([]byte, error) {
	return EncodeCbor([]interface{}{"Signature1", protectedBytes, []byte{}, payload})
}

// SignPlanCose signs a plan as a real CBOR COSE_Sign1 (tag 18). The kid
// (header label 4) is the raw 16-byte prefix of SHA-256(raw public key),
// matching GenerateNIK()/SignPlan().
func SignPlanCose(plan interface{}, privateKeyB64 string) (CoseSignedPlan, error) {
	rawSeed := b64urlDecodeBytes(privateKeyB64)
	if len(rawSeed) != 32 {
		return CoseSignedPlan{}, fmt.Errorf("invalid private key: expected 32 bytes, got %d", len(rawSeed))
	}
	priv := ed25519.NewKeyFromSeed(rawSeed)

	protectedBytes, err := EncodeCbor(map[interface{}]interface{}{int64(1): int64(COSE_ALG_ED25519)})
	if err != nil {
		return CoseSignedPlan{}, err
	}
	payload := []byte(CanonicalJSON(plan))
	sigStruct, err := coseSigStructureBytes(protectedBytes, payload)
	if err != nil {
		return CoseSignedPlan{}, err
	}
	signature := ed25519.Sign(priv, sigStruct)

	rawPub := []byte(priv.Public().(ed25519.PublicKey))
	kidHash := sha256.Sum256(rawPub)
	kid := kidHash[:16]

	envelope := CborTag{Tag: COSE_SIGN1_TAG, Value: []interface{}{
		protectedBytes,
		map[interface{}]interface{}{int64(4): kid},
		payload,
		signature,
	}}
	encoded, err := EncodeCbor(envelope)
	if err != nil {
		return CoseSignedPlan{}, err
	}
	return CoseSignedPlan{Plan: plan, CoseSign1CborB64: b64urlEncodeBytes(encoded)}, nil
}

// VerifyPlanCose verifies a CBOR COSE_Sign1 plan envelope against the key
// cache. Rejects non-Ed25519 algorithms (including the deprecated -8) and
// payloads that do not match the accompanying plan object.
func VerifyPlanCose(envelope CoseSignedPlan, keyCache map[string]NIK) VerifyResult {
	if envelope.CoseSign1CborB64 == "" {
		return VerifyResult{Valid: false, Reason: "missing_cose_sign1"}
	}
	raw := b64urlDecodeBytes(envelope.CoseSign1CborB64)
	decoded, err := DecodeCbor(raw)
	if err != nil {
		return VerifyResult{Valid: false, Reason: "cbor_decode_failed"}
	}
	tag, ok := decoded.(CborTag)
	if !ok || tag.Tag != COSE_SIGN1_TAG {
		return VerifyResult{Valid: false, Reason: "not_cose_sign1"}
	}
	arr, ok := tag.Value.([]interface{})
	if !ok || len(arr) != 4 {
		return VerifyResult{Valid: false, Reason: "malformed_cose_sign1"}
	}
	protectedBytes, ok1 := arr[0].([]byte)
	unprotected, ok2 := arr[1].(map[interface{}]interface{})
	payload, ok3 := arr[2].([]byte)
	signature, ok4 := arr[3].([]byte)
	if !ok1 || !ok2 || !ok3 || !ok4 {
		return VerifyResult{Valid: false, Reason: "malformed_cose_sign1"}
	}

	protectedDecoded, err := DecodeCbor(protectedBytes)
	if err != nil {
		return VerifyResult{Valid: false, Reason: "protected_decode_failed"}
	}
	protectedMap, ok := protectedDecoded.(map[interface{}]interface{})
	if !ok {
		return VerifyResult{Valid: false, Reason: "protected_decode_failed"}
	}
	if alg, ok := protectedMap[int64(1)].(int64); !ok || alg != COSE_ALG_ED25519 {
		return VerifyResult{Valid: false, Reason: "unsupported_alg"}
	}

	kid, _ := unprotected[int64(4)].(string) // bstr keys/values: bstr value stays []byte
	if kidBytes, ok := unprotected[int64(4)].([]byte); ok {
		kid = b64urlEncodeBytes(kidBytes)
	}
	if kid == "" {
		return VerifyResult{Valid: false, Reason: "missing_kid"}
	}

	signerNIK, found := keyCache[kid]
	if !found {
		for _, nik := range keyCache {
			if nik.NodeId != "" && strings.HasPrefix(nik.NodeId, kid) {
				signerNIK = nik
				found = true
				break
			}
		}
	}
	if !found {
		return VerifyResult{Valid: false, Reason: "key_not_in_cache"}
	}
	if IsNIKExpired(signerNIK) {
		return VerifyResult{Valid: false, Reason: "key_expired"}
	}

	rawPub := b64urlDecodeBytes(signerNIK.PublicKey)
	if len(rawPub) != 32 {
		return VerifyResult{Valid: false, Reason: "invalid_public_key"}
	}
	sigStruct, err := coseSigStructureBytes(protectedBytes, payload)
	if err != nil {
		return VerifyResult{Valid: false, Reason: "cbor_decode_failed"}
	}
	if !ed25519.Verify(ed25519.PublicKey(rawPub), sigStruct, signature) {
		return VerifyResult{Valid: false, Reason: "signature_invalid"}
	}

	if envelope.Plan != nil && string(payload) != CanonicalJSON(envelope.Plan) {
		return VerifyResult{Valid: false, Reason: "payload_mismatch"}
	}
	return VerifyResult{Valid: true}
}
