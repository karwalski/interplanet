package ltx_test

import (
	"fmt"
	"strings"
	"testing"

	ltx "github.com/interplanet/ltx"
)

func TestAll(t *testing.T) {
	passed := 0
	failed := 0

	check := func(name string, cond bool) {
		if cond {
			passed++
		} else {
			failed++
			fmt.Printf("FAIL: %s\n", name)
		}
	}

	// Base plan used throughout
	plan := ltx.CreatePlan(ltx.CreatePlanOpts{Start: "2026-03-15T14:00:00Z"})

	// ── 1. Constants ────────────────────────────────────────────────────────
	check("VERSION == 1.0.0", ltx.VERSION == "1.0.0")
	check("DEFAULT_QUANTUM == 3", ltx.DEFAULT_QUANTUM == 3)
	check("DEFAULT_API_BASE has https://", strings.Contains(ltx.DEFAULT_API_BASE, "https://"))
	check("DefaultSegments[0].Type == PLAN_CONFIRM", ltx.DefaultSegments[0].Type == "PLAN_CONFIRM")
	check("DefaultSegments[0].Q == 2", ltx.DefaultSegments[0].Q == 2)
	check("DefaultSegments[1].Type == TX", ltx.DefaultSegments[1].Type == "TX")
	check("DefaultSegments[2].Type == RX", ltx.DefaultSegments[2].Type == "RX")
	check("DefaultSegments[6].Type == BUFFER", ltx.DefaultSegments[6].Type == "BUFFER")
	check("DefaultSegments[6].Q == 1", ltx.DefaultSegments[6].Q == 1)

	// ── 2. CreatePlan ────────────────────────────────────────────────────────
	check("V == 2", plan.V == 2)
	check("Title == LTX Session", plan.Title == "LTX Session")
	check("Start preserved", plan.Start == "2026-03-15T14:00:00Z")
	check("Quantum == 3", plan.Quantum == 3)
	check("Mode == LTX", plan.Mode == "LTX")
	check("len(Nodes) == 2", len(plan.Nodes) == 2)
	check("Nodes[0].ID == N0", plan.Nodes[0].ID == "N0")
	check("Nodes[0].Role == HOST", plan.Nodes[0].Role == "HOST")
	check("Nodes[0].Location == earth", plan.Nodes[0].Location == "earth")
	check("Nodes[0].Delay == 0", plan.Nodes[0].Delay == 0)
	check("Nodes[1].ID == N1", plan.Nodes[1].ID == "N1")
	check("Nodes[1].Role == PARTICIPANT", plan.Nodes[1].Role == "PARTICIPANT")
	check("Nodes[1].Location == mars", plan.Nodes[1].Location == "mars")
	check("len(Segments) == 7", len(plan.Segments) == 7)

	customPlan := ltx.CreatePlan(ltx.CreatePlanOpts{Title: "Q3 Review", Start: "2026-03-15T14:00:00Z", DelayS: 860})
	check("custom title", customPlan.Title == "Q3 Review")
	check("custom delay", customPlan.Nodes[1].Delay == 860)

	// ── 3. UpgradeConfig ─────────────────────────────────────────────────────
	rawCfg := map[string]interface{}{
		"title":   "Upgraded Plan",
		"start":   "2026-04-01T10:00:00Z",
		"quantum": float64(5),
	}
	upgraded := ltx.UpgradeConfig(rawCfg)
	check("upgrade: title", upgraded.Title == "Upgraded Plan")
	check("upgrade: start", upgraded.Start == "2026-04-01T10:00:00Z")
	check("upgrade: quantum", upgraded.Quantum == 5)
	check("upgrade: default nodes", len(upgraded.Nodes) == 2)

	rawWithNodes := map[string]interface{}{
		"title":   "Custom Nodes",
		"start":   "2026-05-01T09:00:00Z",
		"quantum": float64(3),
		"nodes": []interface{}{
			map[string]interface{}{"id": "N0", "name": "Alpha Station", "role": "HOST", "delay": float64(0), "location": "earth"},
			map[string]interface{}{"id": "N1", "name": "Beta Base", "role": "PARTICIPANT", "delay": float64(1200), "location": "mars"},
		},
	}
	upgradedNodes := ltx.UpgradeConfig(rawWithNodes)
	check("upgrade: custom nodes count", len(upgradedNodes.Nodes) == 2)
	check("upgrade: custom node name", upgradedNodes.Nodes[0].Name == "Alpha Station")
	check("upgrade: custom node delay", upgradedNodes.Nodes[1].Delay == 1200)

	// ── 4. ComputeSegments ───────────────────────────────────────────────────
	segs, segErr := ltx.ComputeSegments(plan)
	check("ComputeSegments no error", segErr == nil)
	check("segments len == 7", len(segs) == 7)
	check("seg[0].Type == PLAN_CONFIRM", segs[0].Type == "PLAN_CONFIRM")
	check("seg[1].Type == TX", segs[1].Type == "TX")
	check("seg[2].Type == RX", segs[2].Type == "RX")
	check("seg[6].Type == BUFFER", segs[6].Type == "BUFFER")
	check("seg[0].Q == 2", segs[0].Q == 2)
	check("seg[6].Q == 1", segs[6].Q == 1)
	check("seg[0].StartMs > 0", segs[0].StartMs > 0)
	check("seg[0].EndMs > StartMs", segs[0].EndMs > segs[0].StartMs)
	check("seg[0].DurMin == 6", segs[0].DurMin == 6)
	check("seg[6].DurMin == 3", segs[6].DurMin == 3)
	// Check all contiguous pairs
	check("segs contiguous 0-1", segs[0].EndMs == segs[1].StartMs)
	check("segs contiguous 1-2", segs[1].EndMs == segs[2].StartMs)
	check("segs contiguous 2-3", segs[2].EndMs == segs[3].StartMs)
	check("segs contiguous 3-4", segs[3].EndMs == segs[4].StartMs)
	check("segs contiguous 4-5", segs[4].EndMs == segs[5].StartMs)
	check("segs contiguous 5-6", segs[5].EndMs == segs[6].StartMs)
	// quantum guard: zero quantum should error
	badPlan := ltx.CreatePlan(ltx.CreatePlanOpts{Start: "2026-03-15T14:00:00Z"})
	badPlan.Quantum = 0
	_, badSegErr := ltx.ComputeSegments(badPlan)
	check("ComputeSegments quantum=0 returns error", badSegErr != nil)
	neg1Plan := ltx.CreatePlan(ltx.CreatePlanOpts{Start: "2026-03-15T14:00:00Z"})
	neg1Plan.Quantum = -1
	_, neg1SegErr := ltx.ComputeSegments(neg1Plan)
	check("ComputeSegments quantum=-1 returns error", neg1SegErr != nil)

	// ── 5. TotalMin ──────────────────────────────────────────────────────────
	total := ltx.TotalMin(plan)
	check("TotalMin == 39", total == 39)
	// Verify by manual sum: (2+2+2+2+2+2+1)*3 = 13*3 = 39
	manualSum := 0
	for _, s := range plan.Segments {
		manualSum += s.Q * plan.Quantum
	}
	check("TotalMin matches manual sum", total == manualSum)

	// ── 6. MakePlanID ────────────────────────────────────────────────────────
	planID := ltx.MakePlanID(plan)
	check("planID not empty", planID != "")
	check("planID starts LTX-", strings.HasPrefix(planID, "LTX-"))
	check("planID has date 20260315", strings.Contains(planID, "20260315"))
	check("planID has -v2-", strings.Contains(planID, "-v2-"))
	planID2 := ltx.MakePlanID(plan)
	check("planID deterministic", planID == planID2)
	check("planID len > 20", len(planID) > 20)

	// ── 7. EncodeHash / DecodeHash ───────────────────────────────────────────
	hash := ltx.EncodeHash(plan)
	check("hash starts #l=", strings.HasPrefix(hash, "#l="))
	check("hash length > 10", len(hash) > 10)
	// After #l= there should be no +, / or = (base64url, no padding)
	payload := strings.TrimPrefix(hash, "#l=")
	check("no + in payload", !strings.Contains(payload, "+"))
	check("no / in payload", !strings.Contains(payload, "/"))
	check("no = in payload", !strings.Contains(payload, "="))

	decoded := ltx.DecodeHash(hash)
	check("decoded != nil", decoded != nil)
	if decoded != nil {
		check("decoded V == 2", decoded.V == 2)
		check("decoded title matches", decoded.Title == plan.Title)
		check("decoded quantum matches", decoded.Quantum == plan.Quantum)
		check("decoded node count == 2", len(decoded.Nodes) == 2)
		check("decoded seg count == 7", len(decoded.Segments) == 7)
	} else {
		check("decoded V == 2", false)
		check("decoded title matches", false)
		check("decoded quantum matches", false)
		check("decoded node count == 2", false)
		check("decoded seg count == 7", false)
	}

	// Without # prefix works
	decoded2 := ltx.DecodeHash(strings.TrimPrefix(hash, "#"))
	check("without # works", decoded2 != nil)

	// Bad input returns nil
	nilResult := ltx.DecodeHash("!!!notbase64!!!")
	check("bad input returns nil", nilResult == nil)

	// ── 8. BuildNodeURLs ─────────────────────────────────────────────────────
	baseURL := "https://interplanet.live/ltx.html"
	nodeURLs := ltx.BuildNodeURLs(plan, baseURL)
	check("BuildNodeURLs count == 2", len(nodeURLs) == 2)
	check("nodeURLs[0].NodeID == N0", nodeURLs[0].NodeID == "N0")
	check("nodeURLs[0].Role == HOST", nodeURLs[0].Role == "HOST")
	check("nodeURLs[0].URL has ?node=N0", strings.Contains(nodeURLs[0].URL, "?node=N0"))
	check("nodeURLs[0].URL has #l=", strings.Contains(nodeURLs[0].URL, "#l="))
	check("nodeURLs[0].URL starts with base", strings.HasPrefix(nodeURLs[0].URL, "https://interplanet.live/ltx.html"))
	check("nodeURLs[1].NodeID == N1", nodeURLs[1].NodeID == "N1")
	check("nodeURLs[1].Role == PARTICIPANT", nodeURLs[1].Role == "PARTICIPANT")

	// ── 9. GenerateICS ───────────────────────────────────────────────────────
	ics := ltx.GenerateICS(plan)
	check("ICS starts BEGIN:VCALENDAR", strings.HasPrefix(ics, "BEGIN:VCALENDAR"))
	check("ICS has END:VCALENDAR", strings.Contains(ics, "END:VCALENDAR"))
	check("ICS has BEGIN:VEVENT", strings.Contains(ics, "BEGIN:VEVENT"))
	check("ICS has END:VEVENT", strings.Contains(ics, "END:VEVENT"))
	check("ICS has VERSION:2.0", strings.Contains(ics, "VERSION:2.0"))
	check("ICS has DTSTART:", strings.Contains(ics, "DTSTART:"))
	check("ICS has DTEND:", strings.Contains(ics, "DTEND:"))
	check("ICS has SUMMARY:", strings.Contains(ics, "SUMMARY:"))
	check("ICS has LTX:1", strings.Contains(ics, "LTX:1"))
	check("ICS has LTX-PLANID:", strings.Contains(ics, "LTX-PLANID:"))
	check("ICS has LTX-QUANTUM:PT3M", strings.Contains(ics, "LTX-QUANTUM:PT3M"))
	check("ICS has LTX-NODE:", strings.Contains(ics, "LTX-NODE:"))
	check("ICS has CRLF", strings.Contains(ics, "\r\n"))

	// ── 10. FormatHMS ────────────────────────────────────────────────────────
	check("FormatHMS(0) == 00:00", ltx.FormatHMS(0) == "00:00")
	check("FormatHMS(30) == 00:30", ltx.FormatHMS(30) == "00:30")
	check("FormatHMS(59) == 00:59", ltx.FormatHMS(59) == "00:59")
	check("FormatHMS(60) == 01:00", ltx.FormatHMS(60) == "01:00")
	check("FormatHMS(3600) == 01:00:00", ltx.FormatHMS(3600) == "01:00:00")
	check("FormatHMS(3661) == 01:01:01", ltx.FormatHMS(3661) == "01:01:01")
	check("FormatHMS(7322) == 02:02:02", ltx.FormatHMS(7322) == "02:02:02")
	check("FormatHMS(-1) == 00:00", ltx.FormatHMS(-1) == "00:00")

	// ── 11. FormatUTC ────────────────────────────────────────────────────────
	// epoch 1772375445000 ms = 2026-02-28 14:30:45 UTC
	utcStr := ltx.FormatUTC(1772375445000)
	check("FormatUTC starts 14:30:45", strings.HasPrefix(utcStr, "14:30:45"))
	check("FormatUTC ends UTC", strings.HasSuffix(utcStr, "UTC"))
	check("FormatUTC(0) == 00:00:00 UTC", ltx.FormatUTC(0) == "00:00:00 UTC")

	// ── 12. EscapeIcsText ────────────────────────────────────────────────────
	check("escape empty", ltx.EscapeIcsText("") == "")
	check("escape no special", ltx.EscapeIcsText("hello world") == "hello world")
	check("escape semicolon", ltx.EscapeIcsText("a;b") == `a\;b`)
	check("escape comma", ltx.EscapeIcsText("a,b") == `a\,b`)
	check("escape backslash", ltx.EscapeIcsText(`a\b`) == `a\\b`)
	check("escape newline", ltx.EscapeIcsText("a\nb") == `a\nb`)
	check("escape combined", ltx.EscapeIcsText("Hello, World; Test\\End\nLine") == `Hello\, World\; Test\\End\nLine`)

	// ── 13. DEGRADED state ────────────────────────────────────────────────────
	check("DEGRADED constant", ltx.SessionStateDegraded == "DEGRADED")
	check("SessionStates has INIT",     ltx.SessionStates[0] == "INIT")
	check("SessionStates has LOCKED",   ltx.SessionStates[1] == "LOCKED")
	check("SessionStates has RUNNING",  ltx.SessionStates[2] == "RUNNING")
	check("SessionStates has DEGRADED", ltx.SessionStates[3] == "DEGRADED")
	check("SessionStates has COMPLETE", ltx.SessionStates[4] == "COMPLETE")
	check("SessionStates len == 5", len(ltx.SessionStates) == 5)

	// ── 14. PlanLockTimeoutMs ────────────────────────────────────────────────
	check("DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR == 2", ltx.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR == 2)
	check("PlanLockTimeoutMs(100) == 200000", ltx.PlanLockTimeoutMs(100) == 200000)
	check("PlanLockTimeoutMs(860) == 1720000", ltx.PlanLockTimeoutMs(860) == 1720000)
	check("PlanLockTimeoutMs(0) == 0", ltx.PlanLockTimeoutMs(0) == 0)

	// ── 15. CheckDelayViolation ──────────────────────────────────────────────
	check("DELAY_VIOLATION_WARN_S == 120", ltx.DELAY_VIOLATION_WARN_S == 120)
	check("DELAY_VIOLATION_DEGRADED_S == 300", ltx.DELAY_VIOLATION_DEGRADED_S == 300)
	check("violation ok exact", ltx.CheckDelayViolation(100, 100) == "ok")
	check("violation ok within warn", ltx.CheckDelayViolation(100, 210) == "ok")
	check("violation warn +121", ltx.CheckDelayViolation(100, 221) == "violation")
	check("violation warn -121", ltx.CheckDelayViolation(221, 100) == "violation")
	check("violation degraded +301", ltx.CheckDelayViolation(100, 401) == "degraded")
	check("violation degraded -301", ltx.CheckDelayViolation(401, 100) == "degraded")
	check("violation boundary 120", ltx.CheckDelayViolation(0, 120) == "ok")
	check("violation boundary 121", ltx.CheckDelayViolation(0, 121) == "violation")
	check("violation boundary 300", ltx.CheckDelayViolation(0, 300) == "violation")
	check("violation boundary 301", ltx.CheckDelayViolation(0, 301) == "degraded")

	// ── 16. ICS escaping in GenerateICS ──────────────────────────────────────
	escapePlan := ltx.CreatePlan(ltx.CreatePlanOpts{Title: "Hello, World; Test", Start: "2026-03-15T14:00:00Z"})
	escapeIcs := ltx.GenerateICS(escapePlan)
	check("ICS SUMMARY escapes comma", strings.Contains(escapeIcs, `SUMMARY:Hello\, World\; Test`))
	check("ICS has LTX-QUANTUM:PT3M", strings.Contains(escapeIcs, "LTX-QUANTUM:PT3M"))

	// ── Summary ──────────────────────────────────────────────────────────────
	fmt.Printf("\n%d passed  %d failed\n", passed, failed)
	if failed > 0 {
		t.FailNow()
	}
}


// ── Security tests (Epic 29) ──────────────────────────────────────────────

func TestCanonicalJSON(t *testing.T) {
	passed := 0
	failed := 0
	check := func(name string, cond bool) {
		if cond { passed++ } else { failed++; fmt.Printf("FAIL: %s\n", name) }
	}

	a := ltx.CanonicalJSON(map[string]interface{}{"b": 2, "a": 1})
	b := ltx.CanonicalJSON(map[string]interface{}{"a": 1, "b": 2})
	check("same output different order", a == b)
	check("sorted keys output", a == `{"a":1,"b":2}`)

	nested := ltx.CanonicalJSON(map[string]interface{}{
		"z": map[string]interface{}{"y": 2, "x": 1},
		"a": "hello",
	})
	check("nested sorted", nested == `{"a":"hello","z":{"x":1,"y":2}}`)

	arr := ltx.CanonicalJSON([]interface{}{3, 1, 2})
	check("array unchanged", arr == `[3,1,2]`)

	check("null", ltx.CanonicalJSON(nil) == "null")
	check("bool true", ltx.CanonicalJSON(true) == "true")
	check("int", ltx.CanonicalJSON(42) == "42")
	check("string", ltx.CanonicalJSON("hello") == `"hello"`)

	fmt.Printf("TestCanonicalJSON: %d passed %d failed\n", passed, failed)
	if failed > 0 { t.FailNow() }
}

func TestGenerateNIK(t *testing.T) {
	passed := 0
	failed := 0
	check := func(name string, cond bool) {
		if cond { passed++ } else { failed++; fmt.Printf("FAIL: %s\n", name) }
	}

	result, err := ltx.GenerateNIK(ltx.GenerateNIKOpts{ValidDays: 30, NodeLabel: "Test Node"})
	check("no error", err == nil)
	check("nodeId non-empty", result.NIK.NodeId != "")
	check("publicKey non-empty", result.NIK.PublicKey != "")
	check("algorithm Ed25519", result.NIK.Algorithm == "Ed25519")
	check("keyVersion 1", result.NIK.KeyVersion == 1)
	check("validFrom non-empty", result.NIK.ValidFrom != "")
	check("validUntil non-empty", result.NIK.ValidUntil != "")
	check("label", result.NIK.Label == "Test Node")
	check("privateKeyB64 non-empty", result.PrivateKeyB64 != "")

	r2, _ := ltx.GenerateNIK(ltx.GenerateNIKOpts{ValidDays: 365})
	check("unique nodeIds", result.NIK.NodeId != r2.NIK.NodeId)
	check("unique publicKeys", result.NIK.PublicKey != r2.NIK.PublicKey)
	check("not expired", !ltx.IsNIKExpired(result.NIK))

	fmt.Printf("TestGenerateNIK: %d passed %d failed\n", passed, failed)
	if failed > 0 { t.FailNow() }
}

func TestIsNIKExpired(t *testing.T) {
	passed := 0
	failed := 0
	check := func(name string, cond bool) {
		if cond { passed++ } else { failed++; fmt.Printf("FAIL: %s\n", name) }
	}

	past := ltx.NIK{ValidUntil: "2020-01-01T00:00:00Z"}
	check("past expired", ltx.IsNIKExpired(past))

	future := ltx.NIK{ValidUntil: "2099-01-01T00:00:00Z"}
	check("future not expired", !ltx.IsNIKExpired(future))

	fmt.Printf("TestIsNIKExpired: %d passed %d failed\n", passed, failed)
	if failed > 0 { t.FailNow() }
}

func TestSignVerifyPlan(t *testing.T) {
	passed := 0
	failed := 0
	check := func(name string, cond bool) {
		if cond { passed++ } else { failed++; fmt.Printf("FAIL: %s\n", name) }
	}

	nikResult, err := ltx.GenerateNIK(ltx.GenerateNIKOpts{ValidDays: 365})
	check("generate NIK", err == nil)

	plan := map[string]interface{}{
		"title":   "LTX Session",
		"start":   "2026-03-15T14:00:00Z",
		"quantum": 3,
	}

	signed, err := ltx.SignPlan(plan, nikResult.PrivateKeyB64)
	check("sign no error", err == nil)
	check("signed has plan", signed.Plan != nil)
	check("signed coseSign1 protected non-empty", signed.CoseSign1.Protected != "")
	check("signed coseSign1 payload non-empty", signed.CoseSign1.Payload != "")
	check("signed coseSign1 signature non-empty", signed.CoseSign1.Signature != "")
	check("signed kid non-empty", signed.CoseSign1.Unprotected["kid"] != "")
	check("kid matches nodeId", signed.CoseSign1.Unprotected["kid"] == nikResult.NIK.NodeId)

	keyCache := map[string]ltx.NIK{nikResult.NIK.NodeId: nikResult.NIK}
	result := ltx.VerifyPlan(signed, keyCache)
	check("verify valid", result.Valid)
	check("verify no reason", result.Reason == "")

	emptyCache := map[string]ltx.NIK{}
	r2 := ltx.VerifyPlan(signed, emptyCache)
	check("wrong cache: not valid", !r2.Valid)
	check("wrong cache: reason", r2.Reason == "key_not_in_cache")

	tamperedSigned := signed
	tamperedSigned.Plan = map[string]interface{}{
		"title":   "TAMPERED",
		"start":   "2026-03-15T14:00:00Z",
		"quantum": 3,
	}
	r3 := ltx.VerifyPlan(tamperedSigned, keyCache)
	check("tampered: not valid", !r3.Valid)
	check("tampered: reason", r3.Reason == "payload_mismatch")

	expiredNIK := nikResult.NIK
	expiredNIK.ValidUntil = "2020-01-01T00:00:00Z"
	expiredCache := map[string]ltx.NIK{nikResult.NIK.NodeId: expiredNIK}
	r4 := ltx.VerifyPlan(signed, expiredCache)
	check("expired: not valid", !r4.Valid)
	check("expired: reason", r4.Reason == "key_expired")

	fmt.Printf("TestSignVerifyPlan: %d passed %d failed\n", passed, failed)
	if failed > 0 { t.FailNow() }
}

func TestSequenceTracker(t *testing.T) {
	passed := 0
	failed := 0
	check := func(name string, cond bool) {
		if cond { passed++ } else { failed++; fmt.Printf("FAIL: %s\n", name) }
	}

	tracker := ltx.CreateSequenceTracker("plan-001")

	bundle1 := ltx.AddSeq(map[string]interface{}{"data": "hello"}, tracker, "N0")
	check("first seq == 1", bundle1["seq"] == 1)

	bundle2 := ltx.AddSeq(map[string]interface{}{"data": "world"}, tracker, "N0")
	check("second seq == 2", bundle2["seq"] == 2)

	bundle3 := ltx.AddSeq(map[string]interface{}{"data": "test"}, tracker, "N1")
	check("N1 first seq == 1", bundle3["seq"] == 1)

	check1 := ltx.CheckSeq(map[string]interface{}{"seq": 1}, tracker, "N0")
	check("seq 1 accepted", check1.Accepted)
	check("seq 1 no gap", !check1.Gap)
	check("seq 1 no gap size", check1.GapSize == 0)

	replay := ltx.CheckSeq(map[string]interface{}{"seq": 1}, tracker, "N0")
	check("replay rejected", !replay.Accepted)
	check("replay reason", replay.Reason == "replay")

	check2 := ltx.CheckSeq(map[string]interface{}{"seq": 2}, tracker, "N0")
	check("seq 2 accepted", check2.Accepted)
	check("seq 2 no gap", !check2.Gap)

	gap := ltx.CheckSeq(map[string]interface{}{"seq": 5}, tracker, "N0")
	check("gap accepted", gap.Accepted)
	check("gap detected", gap.Gap)
	check("gap size == 2", gap.GapSize == 2)

	missing := ltx.CheckSeq(map[string]interface{}{"data": "no seq"}, tracker, "N0")
	check("missing seq rejected", !missing.Accepted)
	check("missing seq reason", missing.Reason == "missing_seq")

	fmt.Printf("TestSequenceTracker: %d passed %d failed\n", passed, failed)
	if failed > 0 { t.FailNow() }
}

