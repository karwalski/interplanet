package ltx_test

// LTX v1.1 core subset conformance tests (Epic 72, Story 72.2).
// Golden vectors: testdata/v11.json (copy of conformance/vectors.json .v11).

import (
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"testing"

	ltx "github.com/interplanet/ltx"
)

type v11Vectors struct {
	Key struct {
		PrivateSeedB64 string  `json:"privateSeedB64"`
		Nik            ltx.NIK `json:"nik"`
	} `json:"key"`
	PlanIDV3 struct {
		Plan           ltx.LtxPlan `json:"plan"`
		CanonicalJSON  string      `json:"canonicalJson"`
		Sha256         string      `json:"sha256"`
		ExpectedPlanID string      `json:"expectedPlanId"`
	} `json:"planIdV3"`
	PlanIDV2Regression struct {
		Plan           ltx.LtxPlan `json:"plan"`
		ExpectedPlanID string      `json:"expectedPlanId"`
	} `json:"planIdV2Regression"`
	PairDelay struct {
		Plan  ltx.LtxPlan `json:"plan"`
		Cases []struct {
			A        string `json:"a"`
			B        string `json:"b"`
			Expected int    `json:"expected"`
		} `json:"cases"`
		FallbackCase struct {
			Plan     ltx.LtxPlan `json:"plan"`
			A        string      `json:"a"`
			B        string      `json:"b"`
			Expected int         `json:"expected"`
		} `json:"fallbackCase"`
	} `json:"pairDelay"`
	AmendmentChain struct {
		Chain         []ltx.SignedPlan `json:"chain"`
		RootPlanHash  string           `json:"rootPlanHash"`
		ExpectedValid bool             `json:"expectedValid"`
		TamperField   string           `json:"tamperField"`
	} `json:"amendmentChain"`
	RegisterEntries struct {
		Entries               []ltx.RegisterEntry               `json:"entries"`
		ExpectedQuestionState map[string]map[string]interface{} `json:"expectedQuestionState"`
		EntriesRoot           string                            `json:"entriesRoot"`
	} `json:"registerEntries"`
	CoseSign1 struct {
		Plan             interface{} `json:"plan"`
		CoseSign1CborB64 string      `json:"coseSign1CborB64"`
		CoseSign1CborHex string      `json:"coseSign1CborHex"`
		ExpectedValid    bool        `json:"expectedValid"`
	} `json:"coseSign1"`
	StateMachine struct {
		Plan   ltx.LtxPlan `json:"plan"`
		PlanID string      `json:"planId"`
		Quorum int         `json:"quorum"`
		Steps  []struct {
			Event struct {
				Type           string  `json:"type"`
				NowMs          int64   `json:"nowMs"`
				NodeID         string  `json:"nodeId"`
				PlanID         string  `json:"planId"`
				MeasuredDelayS float64 `json:"measuredDelayS"`
				Decision       string  `json:"decision"`
			} `json:"event"`
			ExpectState string  `json:"expectState"`
			ExpectLock  *string `json:"expectLock"`
		} `json:"steps"`
	} `json:"stateMachine"`
}

func loadV11(t *testing.T) v11Vectors {
	t.Helper()
	data, err := os.ReadFile("testdata/v11.json")
	if err != nil {
		t.Fatalf("read v11 vectors: %v", err)
	}
	var v v11Vectors
	if err := json.Unmarshal(data, &v); err != nil {
		t.Fatalf("parse v11 vectors: %v", err)
	}
	return v
}

func v11KeyCache(v v11Vectors, ids ...string) map[string]ltx.NIK {
	cache := map[string]ltx.NIK{v.Key.Nik.NodeId: v.Key.Nik}
	for _, id := range ids {
		cache[id] = v.Key.Nik
	}
	return cache
}

// ── Feature 1: v3 planId + pairDelay + computeSegmentsFor ────────────────────

func TestV11PlanIDV3(t *testing.T) {
	v := loadV11(t)

	if got := ltx.CanonicalJSON(v.PlanIDV3.Plan); got != v.PlanIDV3.CanonicalJSON {
		t.Errorf("canonical JSON mismatch:\n got %s\nwant %s", got, v.PlanIDV3.CanonicalJSON)
	}
	if got := ltx.PlanHash(v.PlanIDV3.Plan); got != v.PlanIDV3.Sha256 {
		t.Errorf("sha256 mismatch: got %s want %s", got, v.PlanIDV3.Sha256)
	}
	if got := ltx.MakePlanID(v.PlanIDV3.Plan); got != v.PlanIDV3.ExpectedPlanID {
		t.Errorf("v3 planId: got %s want %s", got, v.PlanIDV3.ExpectedPlanID)
	}
}

func TestV11PlanIDV2Regression(t *testing.T) {
	v := loadV11(t)
	// FROZEN v2 polynomial hash — if this breaks the v2 hash changed: STOP.
	if got := ltx.MakePlanID(v.PlanIDV2Regression.Plan); got != v.PlanIDV2Regression.ExpectedPlanID {
		t.Fatalf("FROZEN v2 planId regression: got %s want %s", got, v.PlanIDV2Regression.ExpectedPlanID)
	}
}

func TestV11PairDelay(t *testing.T) {
	v := loadV11(t)
	for _, c := range v.PairDelay.Cases {
		got, err := ltx.PairDelay(v.PairDelay.Plan, c.A, c.B)
		if err != nil {
			t.Fatalf("pairDelay(%s,%s): %v", c.A, c.B, err)
		}
		if got != c.Expected {
			t.Errorf("pairDelay(%s,%s): got %d want %d", c.A, c.B, got, c.Expected)
		}
	}
	fc := v.PairDelay.FallbackCase
	got, err := ltx.PairDelay(fc.Plan, fc.A, fc.B)
	if err != nil {
		t.Fatalf("fallback pairDelay: %v", err)
	}
	if got != fc.Expected {
		t.Errorf("fallback pairDelay(%s,%s): got %d want %d", fc.A, fc.B, got, fc.Expected)
	}
	if _, err := ltx.PairDelay(v.PairDelay.Plan, "N0", "NX"); err == nil {
		t.Errorf("pairDelay with unknown node should error")
	}
}

func TestV11ComputeSegmentsFor(t *testing.T) {
	v := loadV11(t)
	plan := v.PairDelay.Plan // v3 plan with delays {"N1|N2":500}

	base, err := ltx.ComputeSegments(plan)
	if err != nil {
		t.Fatalf("ComputeSegments: %v", err)
	}

	// Viewer N2: segment 1 (TX by N0) shifts by pairDelay(N0,N2)=2 s;
	// segment 2 (TX by N1) shifts by pairDelay(N1,N2)=500 s.
	segsN2, err := ltx.ComputeSegmentsFor(plan, "N2")
	if err != nil {
		t.Fatalf("ComputeSegmentsFor(N2): %v", err)
	}
	if len(segsN2) != len(base) {
		t.Fatalf("segment count: got %d want %d", len(segsN2), len(base))
	}
	if segsN2[0].Perspective != "neutral" || segsN2[0].ArrivalOffsetS != 0 {
		t.Errorf("seg0 (PLAN_CONFIRM) should be neutral/0: %+v", segsN2[0])
	}
	if segsN2[1].Perspective != "receive" || segsN2[1].ArrivalOffsetS != 2 ||
		segsN2[1].StartMs != base[1].StartMs+2000 || segsN2[1].EndMs != base[1].EndMs+2000 {
		t.Errorf("seg1 for N2: %+v", segsN2[1])
	}
	if segsN2[2].Perspective != "receive" || segsN2[2].ArrivalOffsetS != 500 ||
		segsN2[2].StartMs != base[2].StartMs+500000 {
		t.Errorf("seg2 for N2: %+v", segsN2[2])
	}
	if segsN2[1].Speaker != "N0" || segsN2[1].Label != "Opening" {
		t.Errorf("seg1 speaker/label: %+v", segsN2[1])
	}

	// Viewer N1: transmits segment 2, receives segment 1 after 900 s.
	segsN1, err := ltx.ComputeSegmentsFor(plan, "N1")
	if err != nil {
		t.Fatalf("ComputeSegmentsFor(N1): %v", err)
	}
	if segsN1[2].Perspective != "transmit" || segsN1[2].ArrivalOffsetS != 0 ||
		segsN1[2].StartMs != base[2].StartMs {
		t.Errorf("seg2 for N1 should be transmit/unshifted: %+v", segsN1[2])
	}
	if segsN1[1].Perspective != "receive" || segsN1[1].ArrivalOffsetS != 900 {
		t.Errorf("seg1 for N1: %+v", segsN1[1])
	}

	if _, err := ltx.ComputeSegmentsFor(plan, "NX"); err == nil {
		t.Errorf("unknown viewer should error")
	}
}

// ── Feature 2: session state machine golden transition table ─────────────────

func TestV11StateMachine(t *testing.T) {
	v := loadV11(t)
	sm := v.StateMachine

	if got := ltx.MakePlanID(sm.Plan); got != sm.PlanID {
		t.Fatalf("stateMachine planId: got %s want %s", got, sm.PlanID)
	}

	ctx := ltx.CreateSession(sm.Plan, sm.PlanID, ltx.SessionOptions{QuorumCount: sm.Quorum})
	if ctx.State != ltx.SessionStateDraft {
		t.Fatalf("initial state: got %s want DRAFT", ctx.State)
	}
	if ctx.LockTimeoutMs != 1800000 {
		t.Fatalf("lockTimeoutMs: got %d want 1800000", ctx.LockTimeoutMs)
	}

	for i, step := range sm.Steps {
		ev := ltx.SessionEvent{
			Type:           step.Event.Type,
			NowMs:          step.Event.NowMs,
			NodeID:         step.Event.NodeID,
			PlanID:         step.Event.PlanID,
			MeasuredDelayS: step.Event.MeasuredDelayS,
			Decision:       step.Event.Decision,
		}
		ctx, _ = ltx.Transition(ctx, ev)
		if string(ctx.State) != step.ExpectState {
			t.Fatalf("step %d (%s): state got %s want %s", i, step.Event.Type, ctx.State, step.ExpectState)
		}
		wantLock := ""
		if step.ExpectLock != nil {
			wantLock = *step.ExpectLock
		}
		if string(ctx.Lock) != wantLock {
			t.Fatalf("step %d (%s): lock got %q want %q", i, step.Event.Type, ctx.Lock, wantLock)
		}
	}
}

// ── Feature 3: amendment-chain verification ──────────────────────────────────

func TestV11AmendmentChain(t *testing.T) {
	v := loadV11(t)
	keyCache := v11KeyCache(v)

	if got := ltx.PlanHash(v.AmendmentChain.Chain[0].Plan); got != v.AmendmentChain.RootPlanHash {
		t.Fatalf("root plan hash: got %s want %s", got, v.AmendmentChain.RootPlanHash)
	}

	res := ltx.VerifyAmendmentChain(v.AmendmentChain.Chain, keyCache)
	if res.Valid != v.AmendmentChain.ExpectedValid {
		t.Fatalf("chain verify: got %v (%s) want %v", res.Valid, res.Reason, v.AmendmentChain.ExpectedValid)
	}

	// Tamper the golden field on link 1 → chain must fail.
	data, _ := json.Marshal(v.AmendmentChain.Chain)
	var tampered []ltx.SignedPlan
	if err := json.Unmarshal(data, &tampered); err != nil {
		t.Fatalf("clone chain: %v", err)
	}
	tampered[1].Plan.(map[string]interface{})[v.AmendmentChain.TamperField] = "TAMPERED"
	if res := ltx.VerifyAmendmentChain(tampered, keyCache); res.Valid {
		t.Errorf("tampered chain must not verify")
	}

	// Empty chain rejected.
	if res := ltx.VerifyAmendmentChain(nil, keyCache); res.Valid || res.Reason != "empty_chain" {
		t.Errorf("empty chain: got %+v", res)
	}

	// CreateAmendment round-trip with a fresh key.
	nikRes, err := ltx.GenerateNIK(ltx.GenerateNIKOpts{ValidDays: 30})
	if err != nil {
		t.Fatalf("GenerateNIK: %v", err)
	}
	rootPlan := map[string]interface{}{"v": 2, "title": "Root", "start": "2040-02-01T12:00:00.000Z",
		"quantum": 5, "mode": "LTX", "nodes": []interface{}{}, "segments": []interface{}{}}
	signedRoot, err := ltx.SignPlan(rootPlan, nikRes.PrivateKeyB64)
	if err != nil {
		t.Fatalf("SignPlan: %v", err)
	}
	amended, err := ltx.CreateAmendment(signedRoot, map[string]interface{}{"title": "Root (amended)"}, nikRes.PrivateKeyB64)
	if err != nil {
		t.Fatalf("CreateAmendment: %v", err)
	}
	cache := map[string]ltx.NIK{nikRes.NIK.NodeId: nikRes.NIK}
	if res := ltx.VerifyAmendmentChain([]ltx.SignedPlan{signedRoot, amended}, cache); !res.Valid {
		t.Errorf("createAmendment chain should verify: %s", res.Reason)
	}
}

// ── Feature 4: register entries + reducers + entriesRoot ─────────────────────

func TestV11RegisterEntries(t *testing.T) {
	v := loadV11(t)
	keyCache := v11KeyCache(v, "N0", "N1")

	for _, e := range v.RegisterEntries.Entries {
		if res := ltx.VerifyRegisterEntry(e, keyCache); !res.Valid {
			t.Errorf("entry %s should verify: %s", e.EntryId, res.Reason)
		}
		tampered := e
		tampered.Timestamp = "2041-01-01T00:00:00.000Z"
		if res := ltx.VerifyRegisterEntry(tampered, keyCache); res.Valid {
			t.Errorf("tampered entry %s must not verify", e.EntryId)
		}
	}

	byID, superseded := ltx.ReduceQuestions(v.RegisterEntries.Entries)
	if len(superseded) != 0 {
		t.Errorf("no entries should be superseded: %v", superseded)
	}
	for qid, want := range v.RegisterEntries.ExpectedQuestionState {
		got, ok := byID[qid]
		if !ok {
			t.Fatalf("missing question %s", qid)
		}
		gotMap := map[string]interface{}{
			"qid": got.Qid, "text": got.Text, "submitter": got.Submitter,
			"urgency": got.Urgency, "status": got.Status,
			"version": float64(got.Version), "response": got.Response,
			"responder": got.Responder,
		}
		for k, wv := range want {
			if gotMap[k] != wv {
				t.Errorf("question %s field %s: got %v want %v", qid, k, gotMap[k], wv)
			}
		}
	}

	// Ordering is deterministic regardless of input order.
	reversed := []ltx.RegisterEntry{v.RegisterEntries.Entries[1], v.RegisterEntries.Entries[0]}
	if got := ltx.EntriesRoot(reversed); got != v.RegisterEntries.EntriesRoot {
		t.Errorf("entriesRoot (reversed input): got %s want %s", got, v.RegisterEntries.EntriesRoot)
	}
	if got := ltx.EntriesRoot(v.RegisterEntries.Entries); got != v.RegisterEntries.EntriesRoot {
		t.Errorf("entriesRoot: got %s want %s", got, v.RegisterEntries.EntriesRoot)
	}

	// Round-trip: create + verify a fresh entry with the vector key.
	entry, err := ltx.CreateRegisterEntry("question",
		map[string]interface{}{"text": "Status?", "urgency": "high"},
		ltx.CreateEntryOptions{
			SessionId: "VEC-SESSION", NodeId: "N1", Seq: 1,
			Timestamp:     "2040-02-01T11:00:00.000Z",
			PrivateKeyB64: v.Key.PrivateSeedB64,
		})
	if err != nil {
		t.Fatalf("CreateRegisterEntry: %v", err)
	}
	if entry.EntryId != "QST-N1-1" {
		t.Errorf("entryId: got %s want QST-N1-1", entry.EntryId)
	}
	if entry.Sig != v.RegisterEntries.Entries[0].Sig {
		t.Errorf("deterministic signature mismatch:\n got %s\nwant %s", entry.Sig, v.RegisterEntries.Entries[0].Sig)
	}

	// ReduceActions basic behaviour with the same envelope machinery.
	actions := []ltx.RegisterEntry{
		{EntryId: "ACT-N0-1", SessionId: "S", NodeId: "N0", Seq: 1, Type: "action",
			Content: map[string]interface{}{"description": "Do the thing", "owner": "N1"}, Timestamp: "2040-02-01T11:00:00.000Z", Sig: "x"},
		{EntryId: "ACT-N1-1", SessionId: "S", NodeId: "N1", Seq: 1, Type: "action_update",
			Content: map[string]interface{}{"aid": "ACT-N0-1", "status": "DONE", "version": float64(2)}, Timestamp: "2040-02-01T11:10:00.000Z", Sig: "x"},
	}
	aByID, aSuperseded := ltx.ReduceActions(actions)
	if len(aSuperseded) != 0 {
		t.Errorf("actions superseded: %v", aSuperseded)
	}
	a := aByID["ACT-N0-1"]
	if a.Status != "DONE" || a.Version != 2 || a.Description != "Do the thing" || a.Owner != "N1" {
		t.Errorf("reduced action: %+v", a)
	}
}

// ── Feature 5: CBOR decode + COSE_Sign1 verify ───────────────────────────────

func TestV11CoseSign1(t *testing.T) {
	v := loadV11(t)
	keyCache := v11KeyCache(v)

	// b64 and hex forms must be the same bytes.
	rawB64, err := base64.RawURLEncoding.DecodeString(v.CoseSign1.CoseSign1CborB64)
	if err != nil {
		t.Fatalf("decode b64: %v", err)
	}
	rawHex, err := hex.DecodeString(v.CoseSign1.CoseSign1CborHex)
	if err != nil {
		t.Fatalf("decode hex: %v", err)
	}
	if string(rawB64) != string(rawHex) {
		t.Fatalf("b64 and hex forms differ")
	}

	// Structural CBOR checks: tag 18, 4-element array, alg -19.
	decoded, err := ltx.DecodeCbor(rawB64)
	if err != nil {
		t.Fatalf("DecodeCbor: %v", err)
	}
	tag, ok := decoded.(ltx.CborTag)
	if !ok || tag.Tag != ltx.COSE_SIGN1_TAG {
		t.Fatalf("expected COSE_Sign1 tag 18, got %#v", decoded)
	}
	arr, ok := tag.Value.([]interface{})
	if !ok || len(arr) != 4 {
		t.Fatalf("expected 4-element array, got %#v", tag.Value)
	}
	protectedMap, err := ltx.DecodeCbor(arr[0].([]byte))
	if err != nil {
		t.Fatalf("decode protected: %v", err)
	}
	if alg := protectedMap.(map[interface{}]interface{})[int64(1)]; alg != int64(ltx.COSE_ALG_ED25519) {
		t.Fatalf("alg: got %v want -19", alg)
	}

	// Golden verification.
	env := ltx.CoseSignedPlan{Plan: v.CoseSign1.Plan, CoseSign1CborB64: v.CoseSign1.CoseSign1CborB64}
	if res := ltx.VerifyPlanCose(env, keyCache); res.Valid != v.CoseSign1.ExpectedValid {
		t.Fatalf("verifyPlanCose: got %v (%s) want %v", res.Valid, res.Reason, v.CoseSign1.ExpectedValid)
	}

	// Tampered plan → payload_mismatch.
	tamperedPlan := map[string]interface{}{"v": 2, "title": "TAMPERED"}
	if res := ltx.VerifyPlanCose(ltx.CoseSignedPlan{Plan: tamperedPlan, CoseSign1CborB64: v.CoseSign1.CoseSign1CborB64}, keyCache); res.Valid {
		t.Errorf("tampered plan must not verify")
	}

	// Unknown key → key_not_in_cache.
	if res := ltx.VerifyPlanCose(env, map[string]ltx.NIK{}); res.Valid || res.Reason != "key_not_in_cache" {
		t.Errorf("empty cache: got %+v", res)
	}

	// Bad CBOR rejected.
	if res := ltx.VerifyPlanCose(ltx.CoseSignedPlan{CoseSign1CborB64: "AAAA"}, keyCache); res.Valid {
		t.Errorf("garbage CBOR must not verify")
	}

	// Deterministic signing with the vector seed reproduces the golden bytes.
	signed, err := ltx.SignPlanCose(v.CoseSign1.Plan, v.Key.PrivateSeedB64)
	if err != nil {
		t.Fatalf("SignPlanCose: %v", err)
	}
	if signed.CoseSign1CborB64 != v.CoseSign1.CoseSign1CborB64 {
		t.Errorf("SignPlanCose bytes mismatch:\n got %s\nwant %s", signed.CoseSign1CborB64, v.CoseSign1.CoseSign1CborB64)
	}
	if res := ltx.VerifyPlanCose(signed, keyCache); !res.Valid {
		t.Errorf("self-signed envelope should verify: %s", res.Reason)
	}
}

// ── CBOR decoder robustness (RFC 8949 deterministic subset) ──────────────────

func TestV11CborDecoder(t *testing.T) {
	mustHex := func(s string) []byte {
		b, err := hex.DecodeString(s)
		if err != nil {
			t.Fatalf("bad hex %s", s)
		}
		return b
	}

	// RFC 8949 Appendix A vectors (deterministic subset).
	cases := []struct {
		hex  string
		want interface{}
	}{
		{"00", int64(0)},
		{"0a", int64(10)},
		{"17", int64(23)},
		{"1818", int64(24)},
		{"1903e8", int64(1000)},
		{"1a000f4240", int64(1000000)},
		{"20", int64(-1)},
		{"3863", int64(-100)},
		{"f4", false},
		{"f5", true},
		{"f6", nil},
		{"60", ""},
		{"6161", "a"},
		{"6449455446", "IETF"},
	}
	for _, c := range cases {
		got, err := ltx.DecodeCbor(mustHex(c.hex))
		if err != nil {
			t.Errorf("decode %s: %v", c.hex, err)
			continue
		}
		if got != c.want {
			t.Errorf("decode %s: got %#v want %#v", c.hex, got, c.want)
		}
	}

	// Array and nested array.
	arr, err := ltx.DecodeCbor(mustHex("83010203"))
	if err != nil {
		t.Fatalf("decode array: %v", err)
	}
	if a := arr.([]interface{}); len(a) != 3 || a[0] != int64(1) || a[2] != int64(3) {
		t.Errorf("array: %#v", arr)
	}

	// Map {"a": 1, "b": [2, 3]}.
	m, err := ltx.DecodeCbor(mustHex("a26161016162820203"))
	if err != nil {
		t.Fatalf("decode map: %v", err)
	}
	if mm := m.(map[interface{}]interface{}); mm["a"] != int64(1) {
		t.Errorf("map: %#v", m)
	}

	// Rejections: floats, indefinite lengths, trailing bytes, truncation.
	for _, bad := range []string{
		"f97c00",             // float16 Infinity
		"fb3ff199999999999a", // float64 1.1
		"9f01ff",             // indefinite array
		"5f42010243030405ff", // indefinite bstr
		"0001",               // trailing bytes
		"1903",               // truncated head
		"6449455446ff",       // trailing after tstr
	} {
		if _, err := ltx.DecodeCbor(mustHex(bad)); err == nil {
			t.Errorf("decode %s should fail", bad)
		}
	}

	// Encode round-trip determinism.
	enc, err := ltx.EncodeCbor(map[interface{}]interface{}{"b": int64(2), "a": int64(1)})
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	if fmt.Sprintf("%x", enc) != "a2616101616202" {
		t.Errorf("deterministic map encode: got %x", enc)
	}
}
