// Package ltx provides the LTX (Light-Time eXchange) library for Go.
// Story 33.6 — Go 1.21+, no external dependencies.
// Pure port of ltx-sdk.js / interplanet_ltx.rb
package ltx

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"time"
)

// ── Constants ────────────────────────────────────────────────────────────────

const (
	// VERSION is the library version.
	VERSION = "1.0.0"

	// DEFAULT_QUANTUM is the default quantum size in minutes.
	DEFAULT_QUANTUM = 3

	// DEFAULT_API_BASE is the default API base URL.
	DEFAULT_API_BASE = "https://interplanet.live/api/ltx.php"

	// DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR is the multiplier for plan-lock timeout.
	DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR = 2

	// DELAY_VIOLATION_WARN_S is the threshold (seconds) above which a delay
	// difference triggers a warning notification.
	DELAY_VIOLATION_WARN_S = 120

	// DELAY_VIOLATION_DEGRADED_S is the threshold (seconds) above which a delay
	// difference moves the session to DEGRADED state.
	DELAY_VIOLATION_DEGRADED_S = 300
)

// SessionState represents the lifecycle state of an LTX session.
type SessionState string

const (
	SessionStateInit     SessionState = "INIT"
	SessionStateLocked   SessionState = "LOCKED"
	SessionStateRunning  SessionState = "RUNNING"
	SessionStateDegraded SessionState = "DEGRADED"
	SessionStateComplete SessionState = "COMPLETE"
)

// SessionStates is the ordered list of all valid session states.
var SessionStates = []SessionState{
	SessionStateInit,
	SessionStateLocked,
	SessionStateRunning,
	SessionStateDegraded,
	SessionStateComplete,
}

// DefaultSegments is the canonical 7-segment LTX template.
var DefaultSegments = []LtxSegmentTemplate{
	{Type: "PLAN_CONFIRM", Q: 2},
	{Type: "TX", Q: 2},
	{Type: "RX", Q: 2},
	{Type: "CAUCUS", Q: 2},
	{Type: "TX", Q: 2},
	{Type: "RX", Q: 2},
	{Type: "BUFFER", Q: 1},
}

// ── Types ────────────────────────────────────────────────────────────────────

// LtxNode represents a participant node in an LTX session.
type LtxNode struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Role     string `json:"role"`
	Delay    int    `json:"delay"`
	Location string `json:"location"`
}

// LtxSegmentTemplate is a segment specification (type + quantum multiplier).
type LtxSegmentTemplate struct {
	Type string `json:"type"`
	Q    int    `json:"q"`
}

// LtxSegment is a computed timed segment.
type LtxSegment struct {
	Type    string
	Q       int
	StartMs int64
	EndMs   int64
	DurMin  int
}

// LtxNodeURL holds a perspective URL for one node.
type LtxNodeURL struct {
	NodeID string
	Name   string
	Role   string
	URL    string
}

// LtxPlan is the full session plan.
type LtxPlan struct {
	V        int                  `json:"v"`
	Title    string               `json:"title"`
	Start    string               `json:"start"`
	Mode     string               `json:"mode"`
	Quantum  int                  `json:"quantum"`
	Nodes    []LtxNode            `json:"nodes"`
	Segments []LtxSegmentTemplate `json:"segments"`
}

// CreatePlanOpts holds options for CreatePlan.
type CreatePlanOpts struct {
	Title  string
	Start  string
	DelayS int
}

// ── Plan creation ────────────────────────────────────────────────────────────

// CreatePlan creates a plan with default Earth HQ -> Mars Hab-01 nodes and segments.
func CreatePlan(opts CreatePlanOpts) LtxPlan {
	title := opts.Title
	if title == "" {
		title = "LTX Session"
	}

	segs := make([]LtxSegmentTemplate, len(DefaultSegments))
	copy(segs, DefaultSegments)

	return LtxPlan{
		V:       2,
		Title:   title,
		Start:   opts.Start,
		Quantum: DEFAULT_QUANTUM,
		Mode:    "LTX",
		Nodes: []LtxNode{
			{ID: "N0", Name: "Earth HQ", Role: "HOST", Delay: 0, Location: "earth"},
			{ID: "N1", Name: "Mars Hab-01", Role: "PARTICIPANT", Delay: opts.DelayS, Location: "mars"},
		},
		Segments: segs,
	}
}

// UpgradeConfig merges a partial config map into a full LtxPlan with defaults.
func UpgradeConfig(raw map[string]interface{}) LtxPlan {
	plan := CreatePlan(CreatePlanOpts{
		Title: strField(raw, "title"),
		Start: strField(raw, "start"),
	})

	if q := intField(raw, "quantum"); q != 0 {
		plan.Quantum = q
	}
	if m := strField(raw, "mode"); m != "" {
		plan.Mode = m
	}

	if rawNodes, ok := raw["nodes"]; ok {
		if nodeSlice, ok := rawNodes.([]interface{}); ok {
			nodes := make([]LtxNode, 0, len(nodeSlice))
			for _, rn := range nodeSlice {
				nm, _ := rn.(map[string]interface{})
				if nm == nil {
					continue
				}
				id := strField(nm, "id")
				if id == "" {
					id = "N0"
				}
				name := strField(nm, "name")
				if name == "" {
					name = "Unknown"
				}
				role := strField(nm, "role")
				if role == "" {
					role = "HOST"
				}
				loc := strField(nm, "location")
				if loc == "" {
					loc = "earth"
				}
				nodes = append(nodes, LtxNode{
					ID:       id,
					Name:     name,
					Role:     role,
					Delay:    intField(nm, "delay"),
					Location: loc,
				})
			}
			plan.Nodes = nodes
		}
	}

	if rawSegs, ok := raw["segments"]; ok {
		if segSlice, ok := rawSegs.([]interface{}); ok {
			segs := make([]LtxSegmentTemplate, 0, len(segSlice))
			for _, rs := range segSlice {
				sm, _ := rs.(map[string]interface{})
				if sm == nil {
					continue
				}
				typ := strField(sm, "type")
				if typ == "" {
					typ = "TX"
				}
				q := intField(sm, "q")
				if q == 0 {
					q = 2
				}
				segs = append(segs, LtxSegmentTemplate{Type: typ, Q: q})
			}
			plan.Segments = segs
		}
	}

	return plan
}

// ── Segment computation ──────────────────────────────────────────────────────

// ComputeSegments computes the timed segment array for a plan.
// Returns an error if quantum is less than 1.
func ComputeSegments(plan LtxPlan) ([]LtxSegment, error) {
	if plan.Quantum < 1 {
		return nil, fmt.Errorf("quantum must be a positive integer, got %d", plan.Quantum)
	}
	qMs := int64(plan.Quantum) * 60 * 1000
	t := parseISOMs(plan.Start)
	segs := make([]LtxSegment, 0, len(plan.Segments))
	for _, tmpl := range plan.Segments {
		dur := int64(tmpl.Q) * qMs
		segs = append(segs, LtxSegment{
			Type:    tmpl.Type,
			Q:       tmpl.Q,
			StartMs: t,
			EndMs:   t + dur,
			DurMin:  tmpl.Q * plan.Quantum,
		})
		t += dur
	}
	return segs, nil
}

// TotalMin returns the total session duration in minutes.
func TotalMin(plan LtxPlan) int {
	total := 0
	for _, s := range plan.Segments {
		total += s.Q * plan.Quantum
	}
	return total
}

// PlanLockTimeoutMs returns the plan-lock timeout in milliseconds.
// timeout = delaySeconds * DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000
func PlanLockTimeoutMs(delaySeconds float64) float64 {
	return delaySeconds * DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000
}

// CheckDelayViolation compares a declared one-way delay against a measured
// one-way delay and returns the severity:
//   - "ok"        : |measured - declared| <= DELAY_VIOLATION_WARN_S
//   - "violation" : > DELAY_VIOLATION_WARN_S and <= DELAY_VIOLATION_DEGRADED_S
//   - "degraded"  : > DELAY_VIOLATION_DEGRADED_S
func CheckDelayViolation(declaredDelayS, measuredDelayS float64) string {
	diff := measuredDelayS - declaredDelayS
	if diff < 0 {
		diff = -diff
	}
	if diff > DELAY_VIOLATION_DEGRADED_S {
		return "degraded"
	}
	if diff > DELAY_VIOLATION_WARN_S {
		return "violation"
	}
	return "ok"
}

// EscapeIcsText escapes a string for use in RFC 5545 TEXT property values.
// Escapes: backslash → \\, semicolon → \;, comma → \,, newline → \n
func EscapeIcsText(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, ";", `\;`)
	s = strings.ReplaceAll(s, ",", `\,`)
	s = strings.ReplaceAll(s, "\n", `\n`)
	return s
}

// ── Plan ID ──────────────────────────────────────────────────────────────────

// MakePlanID computes the deterministic plan ID: "LTX-YYYYMMDD-HOST-NODE-v2-XXXXXXXX"
func MakePlanID(plan LtxPlan) string {
	startMs := parseISOMs(plan.Start)
	date := time.UnixMilli(startMs).UTC().Format("20060102")

	hostStr := "HOST"
	if len(plan.Nodes) > 0 {
		s := strings.ToUpper(strings.ReplaceAll(plan.Nodes[0].Name, " ", ""))
		if len(s) > 8 {
			s = s[:8]
		}
		hostStr = s
	}

	nodeStr := "RX"
	if len(plan.Nodes) > 1 {
		parts := make([]string, 0, len(plan.Nodes)-1)
		for _, n := range plan.Nodes[1:] {
			s := strings.ToUpper(strings.ReplaceAll(n.Name, " ", ""))
			if len(s) > 4 {
				s = s[:4]
			}
			parts = append(parts, s)
		}
		nodeStr = strings.Join(parts, "-")
	}

	h := planHashHex(plan)
	return fmt.Sprintf("LTX-%s-%s-%s-v2-%s", date, hostStr, nodeStr, h)
}

// ── Encoding ─────────────────────────────────────────────────────────────────

// EncodeHash encodes a plan to a URL-safe base64 hash fragment ("#l=...").
func EncodeHash(plan LtxPlan) string {
	data, err := planToJSON(plan)
	if err != nil {
		return "#l="
	}
	encoded := base64.RawURLEncoding.EncodeToString(data)
	return "#l=" + encoded
}

// DecodeHash decodes a plan from a URL hash fragment ("#l=...", "l=...", or raw base64).
// Returns nil on failure.
func DecodeHash(hash string) *LtxPlan {
	if hash == "" {
		return nil
	}
	token := hash
	token = strings.TrimPrefix(token, "#")
	token = strings.TrimPrefix(token, "l=")

	data, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil {
		return nil
	}

	var raw map[string]interface{}
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil
	}

	plan := UpgradeConfig(raw)
	if len(plan.Segments) == 0 {
		return nil
	}
	return &plan
}

// ── Node URLs ────────────────────────────────────────────────────────────────

// BuildNodeURLs builds perspective URLs for all nodes in a plan.
func BuildNodeURLs(plan LtxPlan, baseURL string) []LtxNodeURL {
	hash := EncodeHash(plan)
	hashPart := strings.TrimPrefix(hash, "#")

	// Strip existing query/fragment from baseURL
	base := regexp.MustCompile(`[?#].*$`).ReplaceAllString(baseURL, "")

	urls := make([]LtxNodeURL, 0, len(plan.Nodes))
	for _, n := range plan.Nodes {
		urls = append(urls, LtxNodeURL{
			NodeID: n.ID,
			Name:   n.Name,
			Role:   n.Role,
			URL:    fmt.Sprintf("%s?node=%s#%s", base, n.ID, hashPart),
		})
	}
	return urls
}

// ── ICS generation ───────────────────────────────────────────────────────────

// GenerateICS generates LTX-extended iCalendar (.ics) content for a plan.
func GenerateICS(plan LtxPlan) string {
	segs, _ := ComputeSegments(plan)
	startMs := parseISOMs(plan.Start)
	endMs := startMs
	if len(segs) > 0 {
		endMs = segs[len(segs)-1].EndMs
	}
	planID := MakePlanID(plan)

	fmtICS := func(ms int64) string {
		return time.UnixMilli(ms).UTC().Format("20060102T150405Z")
	}
	dtStart := fmtICS(startMs)
	dtEnd := fmtICS(endMs)
	dtStamp := time.Now().UTC().Format("20060102T150405Z")

	segTypes := make([]string, 0, len(plan.Segments))
	for _, s := range plan.Segments {
		segTypes = append(segTypes, s.Type)
	}
	segTpl := strings.Join(segTypes, ",")

	hostName := "Earth HQ"
	if len(plan.Nodes) > 0 {
		hostName = plan.Nodes[0].Name
	}

	partNames := "remote nodes"
	if len(plan.Nodes) > 1 {
		names := make([]string, 0, len(plan.Nodes)-1)
		for _, n := range plan.Nodes[1:] {
			names = append(names, n.Name)
		}
		partNames = strings.Join(names, ", ")
	}

	delayDesc := "no participant delay configured"
	if len(plan.Nodes) > 1 {
		parts := make([]string, 0, len(plan.Nodes)-1)
		for _, n := range plan.Nodes[1:] {
			parts = append(parts, fmt.Sprintf("%s: %d min one-way", n.Name, n.Delay/60))
		}
		delayDesc = strings.Join(parts, " . ")
	}

	toNid := func(n LtxNode) string {
		re := regexp.MustCompile(`[\s\t]+`)
		return strings.ToUpper(re.ReplaceAllString(n.Name, "-"))
	}

	var lines []string
	lines = append(lines,
		"BEGIN:VCALENDAR",
		"VERSION:2.0",
		"PRODID:-//InterPlanet//LTX v1.1//EN",
		"CALSCALE:GREGORIAN",
		"METHOD:PUBLISH",
		"BEGIN:VEVENT",
		fmt.Sprintf("UID:%s@interplanet.live", planID),
		fmt.Sprintf("DTSTAMP:%s", dtStamp),
		fmt.Sprintf("DTSTART:%s", dtStart),
		fmt.Sprintf("DTEND:%s", dtEnd),
		fmt.Sprintf("SUMMARY:%s", EscapeIcsText(plan.Title)),
		fmt.Sprintf("DESCRIPTION:LTX session -- %s with %s\\nSignal delays: %s\\nMode: %s . Segment plan: %s\\nGenerated by InterPlanet (https://interplanet.live)",
			EscapeIcsText(hostName), EscapeIcsText(partNames), EscapeIcsText(delayDesc), EscapeIcsText(plan.Mode), segTpl),
		"LTX:1",
		fmt.Sprintf("LTX-PLANID:%s", planID),
		fmt.Sprintf("LTX-QUANTUM:PT%dM", plan.Quantum),
		fmt.Sprintf("LTX-SEGMENT-TEMPLATE:%s", segTpl),
		fmt.Sprintf("LTX-MODE:%s", plan.Mode),
	)

	for _, n := range plan.Nodes {
		// The semicolons between ID=, ROLE= are structural delimiters.
		// Only the name field within the node NID needs text-escaping.
		lines = append(lines, fmt.Sprintf("LTX-NODE:ID=%s;ROLE=%s", toNid(n), n.Role))
	}

	for _, n := range plan.Nodes[1:] {
		d := n.Delay
		lines = append(lines, fmt.Sprintf("LTX-DELAY;NODEID=%s:ONEWAY-MIN=%d;ONEWAY-MAX=%d;ONEWAY-ASSUMED=%d",
			toNid(n), d, d+120, d))
	}

	lines = append(lines, "LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY")

	for _, n := range plan.Nodes {
		if n.Location == "mars" {
			lines = append(lines, fmt.Sprintf("LTX-LOCALTIME:NODE=%s;SCHEME=LMST;PARAMS=LONGITUDE:0E", toNid(n)))
		}
	}

	lines = append(lines, "END:VEVENT", "END:VCALENDAR")

	return strings.Join(lines, "\r\n") + "\r\n"
}

// ── Formatting ───────────────────────────────────────────────────────────────

// FormatHMS formats seconds as "MM:SS" (< 1 hour) or "HH:MM:SS".
// Negative values are clamped to 0.
func FormatHMS(seconds int) string {
	if seconds < 0 {
		seconds = 0
	}
	h := seconds / 3600
	m := (seconds % 3600) / 60
	s := seconds % 60
	if h > 0 {
		return fmt.Sprintf("%02d:%02d:%02d", h, m, s)
	}
	return fmt.Sprintf("%02d:%02d", m, s)
}

// FormatUTC formats UTC epoch milliseconds as "HH:MM:SS UTC".
func FormatUTC(epochMs int64) string {
	t := time.UnixMilli(epochMs).UTC()
	return fmt.Sprintf("%02d:%02d:%02d UTC", t.Hour(), t.Minute(), t.Second())
}

// ── REST client ──────────────────────────────────────────────────────────────

// StoreSession POSTs the plan to the LTX session store.
func StoreSession(plan LtxPlan, apiBase string) (map[string]interface{}, error) {
	if apiBase == "" {
		apiBase = DEFAULT_API_BASE
	}
	endpoint := strings.TrimRight(apiBase, "/") + "/session"

	planJSON, err := planToJSON(plan)
	if err != nil {
		return nil, err
	}
	var planRaw interface{}
	if err := json.Unmarshal(planJSON, &planRaw); err != nil {
		return nil, err
	}
	body, err := json.Marshal(map[string]interface{}{"plan": planRaw})
	if err != nil {
		return nil, err
	}

	result, err := httpPost(endpoint, body)
	if err != nil {
		return map[string]interface{}{}, err
	}
	return result, nil
}

// GetSession GETs a session plan by plan ID.
func GetSession(planID, apiBase string) (*LtxPlan, error) {
	if apiBase == "" {
		apiBase = DEFAULT_API_BASE
	}
	endpoint := strings.TrimRight(apiBase, "/") + "/session/" + url.PathEscape(planID)

	body, err := httpGet(endpoint)
	if err != nil {
		return nil, err
	}

	var data map[string]interface{}
	if err := json.Unmarshal([]byte(body), &data); err != nil {
		return nil, err
	}

	var planData map[string]interface{}
	if pd, ok := data["plan"].(map[string]interface{}); ok {
		planData = pd
	} else {
		planData = data
	}

	plan := UpgradeConfig(planData)
	h := EncodeHash(plan)
	decoded := DecodeHash(h)
	return decoded, nil
}

// DownloadICS downloads ICS content for a session by plan ID and optional node ID.
func DownloadICS(planID, nodeID, apiBase string) (string, error) {
	if apiBase == "" {
		apiBase = DEFAULT_API_BASE
	}
	endpoint := strings.TrimRight(apiBase, "/") + "/ics/" + url.PathEscape(planID)
	if nodeID != "" {
		endpoint += "?node=" + url.QueryEscape(nodeID)
	}

	body, err := httpGet(endpoint)
	if err != nil {
		return "", err
	}
	return body, nil
}

// SubmitFeedback POSTs feedback for a session.
func SubmitFeedback(planID string, payload interface{}, apiBase string) (map[string]interface{}, error) {
	if apiBase == "" {
		apiBase = DEFAULT_API_BASE
	}
	endpoint := strings.TrimRight(apiBase, "/") + "/feedback/" + url.PathEscape(planID)

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	result, err := httpPost(endpoint, body)
	if err != nil {
		return map[string]interface{}{}, err
	}
	return result, nil
}

// ── Private helpers ──────────────────────────────────────────────────────────

// parseISOMs parses an ISO-8601 UTC string to epoch milliseconds.
func parseISOMs(iso string) int64 {
	if iso == "" {
		return 0
	}
	t, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		return 0
	}
	return t.UnixMilli()
}

// planJSONOrdered is used for controlled JSON key ordering.
type planJSONOrdered struct {
	V        int                  `json:"v"`
	Title    string               `json:"title"`
	Start    string               `json:"start"`
	Quantum  int                  `json:"quantum"`
	Mode     string               `json:"mode"`
	Nodes    []nodeJSONOrdered    `json:"nodes"`
	Segments []segJSONOrdered     `json:"segments"`
}

type nodeJSONOrdered struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Role     string `json:"role"`
	Delay    int    `json:"delay"`
	Location string `json:"location"`
}

type segJSONOrdered struct {
	Type string `json:"type"`
	Q    int    `json:"q"`
}

// planToJSON serialises a plan to compact JSON with exact key order:
// v, title, start, quantum, mode, nodes, segments
func planToJSON(plan LtxPlan) ([]byte, error) {
	nodes := make([]nodeJSONOrdered, 0, len(plan.Nodes))
	for _, n := range plan.Nodes {
		nodes = append(nodes, nodeJSONOrdered{
			ID:       n.ID,
			Name:     n.Name,
			Role:     n.Role,
			Delay:    n.Delay,
			Location: n.Location,
		})
	}
	segs := make([]segJSONOrdered, 0, len(plan.Segments))
	for _, s := range plan.Segments {
		segs = append(segs, segJSONOrdered{Type: s.Type, Q: s.Q})
	}
	ordered := planJSONOrdered{
		V:        plan.V,
		Title:    plan.Title,
		Start:    plan.Start,
		Quantum:  plan.Quantum,
		Mode:     plan.Mode,
		Nodes:    nodes,
		Segments: segs,
	}
	buf := &bytes.Buffer{}
	enc := json.NewEncoder(buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(ordered); err != nil {
		return nil, err
	}
	// Encode adds a trailing newline; trim it
	return bytes.TrimRight(buf.Bytes(), "\n"), nil
}

// planHashHex computes the polynomial hash hex string.
// Matches Math.imul(31, h) in ltx-sdk.js: uint32 arithmetic.
func planHashHex(plan LtxPlan) string {
	data, err := planToJSON(plan)
	if err != nil {
		return "00000000"
	}
	var h uint32
	for _, b := range data {
		h = h*31 + uint32(b)
	}
	return fmt.Sprintf("%08x", h)
}

// strField reads a string field from a map, trying both the key as-is.
func strField(m map[string]interface{}, key string) string {
	if v, ok := m[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

// intField reads an int field from a map (handles float64, int, int64).
func intField(m map[string]interface{}, key string) int {
	v, ok := m[key]
	if !ok {
		return 0
	}
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case int64:
		return int(n)
	case json.Number:
		i, _ := n.Int64()
		return int(i)
	}
	return 0
}

// httpPost POSTs JSON body and returns parsed map or error.
func httpPost(endpoint string, body []byte) (map[string]interface{}, error) {
	resp, err := http.Post(endpoint, "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	var result map[string]interface{}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, err
	}
	return result, nil
}

// httpGet GETs a URL and returns the response body as string or error.
func httpGet(endpoint string) (string, error) {
	resp, err := http.Get(endpoint)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(body), nil
}



// ────────────────────────────────────────────────────────────────────────────
// Security: Epic 29 (stories 29.1, 29.4, 29.5)
// ────────────────────────────────────────────────────────────────────────────

// CanonicalJSON serialises any Go value to a deterministic JSON string with
// object keys sorted lexicographically at every nesting level.
// Arrays are preserved in their original order.
func CanonicalJSON(v interface{}) string {
	if v == nil {
		return "null"
	}
	rv := reflect.ValueOf(v)
	switch rv.Kind() {
	case reflect.Map:
		keys := make([]string, 0, rv.Len())
		for _, k := range rv.MapKeys() {
			keys = append(keys, k.String())
		}
		sort.Strings(keys)
		parts := make([]string, len(keys))
		for i, k := range keys {
			kb, _ := json.Marshal(k)
			parts[i] = string(kb) + ":" + CanonicalJSON(rv.MapIndex(reflect.ValueOf(k)).Interface())
		}
		return "{" + strings.Join(parts, ",") + "}"
	case reflect.Slice:
		if rv.IsNil() {
			return "null"
		}
		items := make([]string, rv.Len())
		for i := range items {
			items[i] = CanonicalJSON(rv.Index(i).Interface())
		}
		return "[" + strings.Join(items, ",") + "]"
	case reflect.Array:
		items := make([]string, rv.Len())
		for i := range items {
			items[i] = CanonicalJSON(rv.Index(i).Interface())
		}
		return "[" + strings.Join(items, ",") + "]"
	default:
		b, _ := json.Marshal(v)
		return string(b)
	}
}

// ── NIK (Node Identity Key) ───────────────────────────────────────────────

// NIK holds a Node Identity Key record.
type NIK struct {
	NodeId     string `json:"nodeId"`
	PublicKey  string `json:"publicKey"`
	Algorithm  string `json:"algorithm"`
	ValidFrom  string `json:"validFrom"`
	ValidUntil string `json:"validUntil"`
	KeyVersion int    `json:"keyVersion"`
	Label      string `json:"label,omitempty"`
}

// GenerateNIKOpts holds options for GenerateNIK.
type GenerateNIKOpts struct {
	ValidDays int
	NodeLabel string
}

// GenerateNIKResult is returned by GenerateNIK.
type GenerateNIKResult struct {
	NIK           NIK
	PrivateKeyB64 string
}

// GenerateNIK generates a new Node Identity Key (NIK) using Ed25519.
// validDays defaults to 365.  nodeLabel is optional.
// Raw 32-byte public key is used for NodeId computation; raw private
// seed is returned as base64url in PrivateKeyB64.
func GenerateNIK(opts GenerateNIKOpts) (GenerateNIKResult, error) {
	validDays := opts.ValidDays
	if validDays <= 0 {
		validDays = 365
	}

	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		return GenerateNIKResult{}, err
	}

	// Raw 32-byte public key
	rawPub := []byte(pub)
	pubB64 := b64urlEncodeBytes(rawPub)

	// NodeId = base64url of first 16 bytes of SHA-256(raw public key)
	hash := sha256.Sum256(rawPub)
	nodeId := b64urlEncodeBytes(hash[:16])

	now := time.Now().UTC()
	validUntil := now.Add(time.Duration(validDays) * 24 * time.Hour)

	nik := NIK{
		NodeId:     nodeId,
		PublicKey:  pubB64,
		Algorithm:  "Ed25519",
		ValidFrom:  now.Format(time.RFC3339),
		ValidUntil: validUntil.Format(time.RFC3339),
		KeyVersion: 1,
		Label:      opts.NodeLabel,
	}

	// Go ed25519 private key is 64 bytes (seed+pub); seed is first 32 bytes
	rawSeed := []byte(priv[:32])
	privB64 := b64urlEncodeBytes(rawSeed)

	return GenerateNIKResult{NIK: nik, PrivateKeyB64: privB64}, nil
}

// IsNIKExpired returns true if the NIK ValidUntil is in the past.
func IsNIKExpired(nik NIK) bool {
	for _, layout := range []string{time.RFC3339, "2006-01-02T15:04:05Z", "2006-01-02T15:04:05"} {
		if t, err := time.Parse(layout, nik.ValidUntil); err == nil {
			return time.Now().UTC().After(t)
		}
	}
	return true // treat unparseable as expired
}

// NikFingerprint returns the full SHA-256 hex fingerprint of a NIK public key.
func NikFingerprint(nik NIK) string {
	rawPub := b64urlDecodeBytes(nik.PublicKey)
	hash := sha256.Sum256(rawPub)
	return fmt.Sprintf("%x", hash[:])
}

// ── CoseSign1 / SignedPlan / VerifyResult ─────────────────────────────────

// CoseSign1 holds the COSE_Sign1-compatible signing envelope fields.
type CoseSign1 struct {
	Protected   string            `json:"protected"`
	Unprotected map[string]string `json:"unprotected"`
	Payload     string            `json:"payload"`
	Signature   string            `json:"signature"`
}

// SignedPlan is the output of SignPlan.
type SignedPlan struct {
	Plan      interface{} `json:"plan"`
	CoseSign1 CoseSign1   `json:"coseSign1"`
}

// VerifyResult is returned by VerifyPlan.
type VerifyResult struct {
	Valid  bool
	Reason string
}

// SignPlan signs an LTX session plan using a COSE_Sign1-compatible structure.
// privateKeyB64 is the base64url-encoded raw 32-byte Ed25519 private seed.
func SignPlan(plan interface{}, privateKeyB64 string) (SignedPlan, error) {
	rawSeed := b64urlDecodeBytes(privateKeyB64)
	if len(rawSeed) != 32 {
		return SignedPlan{}, fmt.Errorf("invalid private key: expected 32 bytes, got %d", len(rawSeed))
	}
	priv := ed25519.NewKeyFromSeed(rawSeed)
	pub := priv.Public().(ed25519.PublicKey)

	// Protected header
	protectedHeader := CanonicalJSON(map[string]interface{}{"alg": -19})
	protectedB64 := b64urlEncodeBytes([]byte(protectedHeader))

	// Payload
	payloadStr := CanonicalJSON(plan)
	payloadB64 := b64urlEncodeBytes([]byte(payloadStr))

	// Sig_Structure
	sigStructure := CanonicalJSON([]interface{}{"Signature1", protectedB64, "", payloadB64})

	// Sign
	sigBytes := ed25519.Sign(priv, []byte(sigStructure))
	sigB64 := b64urlEncodeBytes(sigBytes)

	// Derive kid (nodeId) from public key
	rawPub := []byte(pub)
	kidHash := sha256.Sum256(rawPub)
	kid := b64urlEncodeBytes(kidHash[:16])

	return SignedPlan{
		Plan: plan,
		CoseSign1: CoseSign1{
			Protected:   protectedB64,
			Unprotected: map[string]string{"kid": kid},
			Payload:     payloadB64,
			Signature:   sigB64,
		},
	}, nil
}

// VerifyPlan verifies a COSE_Sign1-signed session plan envelope.
// keyCache maps nodeId (string) to NIK.
func VerifyPlan(sp SignedPlan, keyCache map[string]NIK) VerifyResult {
	cose := sp.CoseSign1
	kid := cose.Unprotected["kid"]

	signerNIK, ok := keyCache[kid]
	if !ok {
		return VerifyResult{Valid: false, Reason: "key_not_in_cache"}
	}
	if IsNIKExpired(signerNIK) {
		return VerifyResult{Valid: false, Reason: "key_expired"}
	}

	// Reconstruct sig structure
	sigStructure := CanonicalJSON([]interface{}{"Signature1", cose.Protected, "", cose.Payload})

	// Reconstruct public key (raw 32 bytes)
	rawPub := b64urlDecodeBytes(signerNIK.PublicKey)
	if len(rawPub) != 32 {
		return VerifyResult{Valid: false, Reason: "invalid_public_key"}
	}
	pubKey := ed25519.PublicKey(rawPub)

	// Verify signature
	sigBytes := b64urlDecodeBytes(cose.Signature)
	if !ed25519.Verify(pubKey, []byte(sigStructure), sigBytes) {
		return VerifyResult{Valid: false, Reason: "signature_invalid"}
	}

	// Verify payload matches plan
	payloadStr := string(b64urlDecodeBytes(cose.Payload))
	planStr := CanonicalJSON(sp.Plan)
	if payloadStr != planStr {
		return VerifyResult{Valid: false, Reason: "payload_mismatch"}
	}

	return VerifyResult{Valid: true}
}

// ── Sequence Tracker ─────────────────────────────────────────────────────

// SequenceTracker tracks per-nodeId sequence numbers for replay detection.
type SequenceTracker struct {
	planId string
	outSeq map[string]int
	inSeq  map[string]int
}

// SeqCheckResult is returned by CheckSeq.
type SeqCheckResult struct {
	Accepted bool
	Reason   string
	Gap      bool
	GapSize  int
}

// CreateSequenceTracker creates a new SequenceTracker for the given planId.
func CreateSequenceTracker(planId string) *SequenceTracker {
	return &SequenceTracker{
		planId: planId,
		outSeq: make(map[string]int),
		inSeq:  make(map[string]int),
	}
}

func (st *SequenceTracker) nextSeq(nodeId string) int {
	st.outSeq[nodeId]++
	return st.outSeq[nodeId]
}

func (st *SequenceTracker) recordSeq(nodeId string, seq int) SeqCheckResult {
	last := st.inSeq[nodeId]
	if seq <= last {
		return SeqCheckResult{Accepted: false, Reason: "replay", Gap: false, GapSize: 0}
	}
	gap := seq > last+1
	gapSize := 0
	if gap {
		gapSize = seq - last - 1
	}
	st.inSeq[nodeId] = seq
	return SeqCheckResult{Accepted: true, Gap: gap, GapSize: gapSize}
}

// AddSeq stamps a bundle map with the next outbound sequence number.
// Returns a new map with "seq" set.
func AddSeq(bundle map[string]interface{}, tracker *SequenceTracker, nodeId string) map[string]interface{} {
	seq := tracker.nextSeq(nodeId)
	out := make(map[string]interface{}, len(bundle)+1)
	for k, v := range bundle {
		out[k] = v
	}
	out["seq"] = seq
	return out
}

// CheckSeq checks an inbound bundle seq field against the tracker.
func CheckSeq(bundle map[string]interface{}, tracker *SequenceTracker, senderNodeId string) SeqCheckResult {
	seqRaw, ok := bundle["seq"]
	if !ok {
		return SeqCheckResult{Accepted: false, Reason: "missing_seq"}
	}
	var seq int
	switch v := seqRaw.(type) {
	case int:
		seq = v
	case float64:
		seq = int(v)
	case int64:
		seq = int(v)
	default:
		return SeqCheckResult{Accepted: false, Reason: "invalid_seq"}
	}
	return tracker.recordSeq(senderNodeId, seq)
}

// ── base64url byte helpers ────────────────────────────────────────────────

func b64urlEncodeBytes(data []byte) string {
	return base64.RawURLEncoding.EncodeToString(data)
}

func b64urlDecodeBytes(s string) []byte {
	data, err := base64.RawURLEncoding.DecodeString(s)
	if err == nil {
		return data
	}
	// Fallback: try padding / standard alphabet
	padded := strings.NewReplacer("-", "+", "_", "/").Replace(s)
	switch len(padded) % 4 {
	case 2:
		padded += "=="
	case 3:
		padded += "="
	}
	data, _ = base64.StdEncoding.DecodeString(padded)
	return data
}
