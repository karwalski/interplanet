package ltx_test

// Parity tests mirroring javascript/ltx/tests/run.js (issue #27):
// golden planId vectors (spec/golden/plan-ids.json), validatePlan and the
// reserved streams / branching fields, reduceDecisions + merge_snapshot
// decisionRegister, and the sequence-tracker reorder window.

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"reflect"
	"strings"
	"testing"

	ltx "github.com/interplanet/ltx"
)

type goldenVector struct {
	Name     string          `json:"name"`
	Plan     json.RawMessage `json:"plan"`
	PlanID   string          `json:"planId"`
	PlanHash string          `json:"planHash"`
}

type goldenFile struct {
	Vectors []goldenVector `json:"vectors"`
}

type checker struct {
	t              *testing.T
	name           string
	passed, failed int
}

func (c *checker) check(label string, ok bool) {
	if ok {
		c.passed++
	} else {
		c.failed++
		c.t.Errorf("FAIL: %s", label)
	}
}

func (c *checker) done() {
	fmt.Printf("%s: %d passed %d failed\n", c.name, c.passed, c.failed)
}

func loadGolden(t *testing.T) (goldenFile, map[string]goldenVector) {
	data, err := os.ReadFile("../../spec/golden/plan-ids.json")
	if err != nil {
		t.Fatalf("read golden vectors: %v", err)
	}
	var g goldenFile
	if err := json.Unmarshal(data, &g); err != nil {
		t.Fatalf("parse golden vectors: %v", err)
	}
	by := map[string]goldenVector{}
	for _, v := range g.Vectors {
		by[v.Name] = v
	}
	return g, by
}

func TestGoldenPlanIDs(t *testing.T) {
	c := &checker{t: t, name: "TestGoldenPlanIDs"}
	defer c.done()
	g, by := loadGolden(t)
	c.check("golden vectors present", len(g.Vectors) >= 9)
	for _, v := range g.Vectors {
		id, err := ltx.MakePlanIDFromJSON([]byte(v.Plan))
		c.check("golden planId "+v.Name+" (got "+id+")", err == nil && id == v.PlanID)
		if v.PlanHash != "" {
			c.check("golden planHash "+v.Name, ltx.PlanHashFromJSON([]byte(v.Plan)) == v.PlanHash)
		}
	}
	c.check("golden v2 freeze anchor", by["v2-freeze-check"].PlanID == "LTX-20260801-EARTHHQ-MARS-v2-d132e85d")
	c.check("golden v2 unicode anchor", by["v2-unicode-title"].PlanID == "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8")
	c.check("golden v2 order-sensitive", by["v2-createPlan-default"].PlanID != by["v2-key-order-sensitive"].PlanID)
	c.check("golden v3 order-insensitive", by["v3-upgrade-delays"].PlanID == by["v3-key-order-insensitive"].PlanID)
	var amend map[string]interface{}
	_ = json.Unmarshal(by["v3-amendment"].Plan, &amend)
	c.check("golden v3 amendment chain hash", amend["prevPlanHash"] == by["v3-upgrade-delays"].PlanHash)
	c.check("createPlan default quantum is 5", ltx.CreatePlan(ltx.CreatePlanOpts{}).Quantum == 5 && ltx.DEFAULT_QUANTUM == 5)

	// The typed LtxPlan serialises v2 plans in the fixed key order
	// v,title,start,quantum,mode,nodes,segments, so MakePlanID matches the
	// golden vectors that use that order, and every v3 vector the typed
	// struct can represent.
	for _, name := range []string{"v2-key-order-sensitive", "v2-conference-attributed", "v3-upgrade-delays", "v3-key-order-insensitive"} {
		var p ltx.LtxPlan
		_ = json.Unmarshal(by[name].Plan, &p)
		c.check("typed MakePlanID "+name, ltx.MakePlanID(p) == by[name].PlanID)
	}
	// The v2 hash runs over UTF-16 code units, not UTF-8 bytes. Expected value
	// from ltx-sdk.js makePlanId on the unicode vector in typed key order.
	var uni ltx.LtxPlan
	_ = json.Unmarshal(by["v2-unicode-title"].Plan, &uni)
	c.check("typed MakePlanID hashes UTF-16", ltx.MakePlanID(uni) == "LTX-20261231-EARTHHQ-MARS-v2-06a7c14c")
	// Canonical JSON matches JavaScript: no HTML escaping, JS number form.
	c.check("canonical no HTML escape", ltx.CanonicalJSON(map[string]interface{}{"t": "a<b>&c"}) == `{"t":"a<b>&c"}`)
	c.check("canonical JS numbers", ltx.CanonicalJSON([]interface{}{1e21, 1e-7, 0.5, 860.0}) == `[1e+21,1e-7,0.5,860]`)
	c.check("canonical UTF-16 key order", ltx.CanonicalJSON(map[string]interface{}{"\U0001F680": 1, "Ａ": 2}) == "{\"\U0001F680\":1,\"Ａ\":2}")
}

func withField(t *testing.T, raw json.RawMessage, key string, value interface{}) ltx.OrderedObject {
	o, err := ltx.ParseOrderedJSON(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	obj := append(ltx.OrderedObject(nil), o.(ltx.OrderedObject)...)
	for i := range obj {
		if obj[i].Key == key {
			obj[i].Value = value
			return obj
		}
	}
	return append(obj, ltx.OrderedMember{Key: key, Value: value})
}

func codesOf(r ltx.PlanValidation) []string {
	out := make([]string, 0, len(r.Errors))
	for _, e := range r.Errors {
		out = append(out, e.Code)
	}
	return out
}

func hasCode(r ltx.PlanValidation, code string) bool {
	for _, c := range codesOf(r) {
		if c == code {
			return true
		}
	}
	return false
}

func reservedCode(err error) string {
	var re *ltx.ReservedFieldError
	if errors.As(err, &re) {
		return re.Code
	}
	return ""
}

func TestValidatePlanReserved(t *testing.T) {
	c := &checker{t: t, name: "TestValidatePlanReserved"}
	defer c.done()
	g, by := loadGolden(t)
	for _, v := range g.Vectors {
		c.check("validatePlan accepts golden "+v.Name, ltx.ValidatePlan([]byte(v.Plan)).Valid)
	}
	base := by["v3-upgrade-delays"].Plan
	v2 := by["v2-freeze-check"].Plan
	obj := func(kv ...interface{}) ltx.OrderedObject {
		o := ltx.OrderedObject{}
		for i := 0; i < len(kv); i += 2 {
			o = append(o, ltx.OrderedMember{Key: kv[i].(string), Value: kv[i+1]})
		}
		return o
	}

	c.check("validatePlan v3 empty streams ok", ltx.ValidatePlan(withField(t, base, "streams", []interface{}{})).Valid)
	vs := ltx.ValidatePlan(withField(t, base, "streams", []interface{}{obj("id", "S1")}))
	c.check("validatePlan non-empty streams", !vs.Valid && hasCode(vs, "reserved_streams"))
	streamPath := ""
	for _, e := range vs.Errors {
		if e.Code == "reserved_streams" {
			streamPath = e.Path
			break
		}
	}
	c.check("validatePlan streams error path", streamPath == "streams")
	c.check("validatePlan streams non-array", hasCode(ltx.ValidatePlan(withField(t, base, "streams", "S1")), "reserved_streams"))
	c.check("validatePlan segment stream", hasCode(ltx.ValidatePlan(withField(t, base, "segments",
		[]interface{}{obj("type", "TX", "q", 1.0, "stream", "S1")})), "reserved_streams"))
	c.check("validatePlan branches", hasCode(ltx.ValidatePlan(withField(t, base, "branches", []interface{}{})), "reserved_branching"))
	c.check("validatePlan branching", hasCode(ltx.ValidatePlan(withField(t, base, "branching", obj("mode", "local"))), "reserved_branching"))
	vb := ltx.ValidatePlan(withField(t, base, "segments", []interface{}{obj("type", "CAUCUS", "q", 1.0, "branch", "B1")}))
	c.check("validatePlan segment branch", hasCode(vb, "reserved_branching") && vb.Errors[0].Path == "segments[0].branch")
	c.check("validatePlan v2 streams is v3 field", hasCode(ltx.ValidatePlan(withField(t, v2, "streams", []interface{}{})), "v3_field_in_v2"))
	c.check("validatePlan v2 branching", hasCode(ltx.ValidatePlan(withField(t, v2, "branching", true)), "reserved_branching"))

	// Structural checks mirror spec/ltx-schema.json
	c.check("validatePlan non-object", hasCode(ltx.ValidatePlan([]byte("null")), "not_an_object"))
	c.check("validatePlan bad version", hasCode(ltx.ValidatePlan(withField(t, v2, "v", 7.0)), "invalid_version"))
	v2o, _ := ltx.ParseOrderedJSON(v2)
	nodes, _ := v2o.(ltx.OrderedObject).Get("nodes")
	nl := nodes.([]interface{})
	c.check("validatePlan host not first", hasCode(ltx.ValidatePlan(withField(t, v2, "nodes", []interface{}{nl[1], nl[0]})), "invalid_host"))
	c.check("validatePlan unsorted delays key", hasCode(ltx.ValidatePlan(withField(t, base, "delays", obj("N1|N0", 860.0))), "invalid_delays"))
	c.check("validatePlan unknown speaker", hasCode(ltx.ValidatePlan(withField(t, v2, "segments",
		[]interface{}{obj("type", "TX", "q", 1.0, "speaker", "N9")})), "unknown_speaker"))
	c.check("validatePlan quantum out of range", hasCode(ltx.ValidatePlan(withField(t, v2, "quantum", 0.0)), "invalid_quantum"))
	c.check("validatePlan typed plan", ltx.ValidatePlan(ltx.CreatePlan(ltx.CreatePlanOpts{Start: "2026-03-15T14:00:00.000Z"})).Valid)

	// Enforcement paths return a ReservedFieldError with a code
	nik, _ := ltx.GenerateNIK(ltx.GenerateNIKOpts{NodeLabel: "Earth HQ"})
	var basePlan map[string]interface{}
	_ = json.Unmarshal(base, &basePlan)
	signed, err := ltx.SignPlan(basePlan, nik.PrivateKeyB64)
	c.check("signPlan ok", err == nil)
	_, err = ltx.CreateAmendment(signed, map[string]interface{}{"branching": map[string]interface{}{}}, nik.PrivateKeyB64)
	c.check("createAmendment rejects branching", reservedCode(err) == "reserved_branching")
	_, err = ltx.CreateAmendment(signed, map[string]interface{}{"streams": []interface{}{map[string]interface{}{"id": "S1"}}}, nik.PrivateKeyB64)
	c.check("createAmendment rejects streams", reservedCode(err) == "reserved_streams")
	_, err = ltx.CreateAmendment(signed, map[string]interface{}{"title": "x", "streams": []interface{}{}}, nik.PrivateKeyB64)
	c.check("createAmendment ok without", err == nil)
	_, err = ltx.CreateSessionFromJSON(withField(t, base, "streams", []interface{}{1.0}), "id", ltx.SessionOptions{})
	c.check("createSession rejects streams", reservedCode(err) == "reserved_streams")
	ctx, err := ltx.CreateSessionFromJSON([]byte(base), "id", ltx.SessionOptions{})
	c.check("createSession accepts golden", err == nil && ctx.State == ltx.SessionStateDraft && len(ctx.Plan.Nodes) == 4)
}

func TestReduceDecisions(t *testing.T) {
	c := &checker{t: t, name: "TestReduceDecisions"}
	defer c.done()
	host, _ := ltx.GenerateNIK(ltx.GenerateNIKOpts{NodeLabel: "HOST"})
	mars, _ := ltx.GenerateNIK(ltx.GenerateNIKOpts{NodeLabel: "MARS"})
	cache := map[string]ltx.NIK{"N0": host.NIK, "N1": mars.NIK}
	mk := func(typ string, content map[string]interface{}, node string, seq int, ts, priv, entryID string) ltx.RegisterEntry {
		e, err := ltx.CreateRegisterEntry(typ, content, ltx.CreateEntryOptions{
			SessionId: "LTX-DEC-TEST", NodeId: node, Seq: seq, Timestamp: ts, PrivateKeyB64: priv, EntryId: entryID,
		})
		if err != nil {
			t.Fatalf("createRegisterEntry: %v", err)
		}
		return e
	}
	dec1 := mk("decision", map[string]interface{}{"text": "Proceed with EVA-3", "rationale": "Weather window", "originWindow": "W2"},
		"N0", 1, "2026-08-01T12:00:00.000Z", host.PrivateKeyB64, "")
	c.check("decision id prefix DEC", dec1.EntryId == "DEC-N0-1")
	c.check("decision entry verifies", ltx.VerifyRegisterEntry(dec1, cache).Valid)
	r1, _ := ltx.ReduceDecisions([]ltx.RegisterEntry{dec1})
	d := r1["DEC-N0-1"]
	c.check("decision RECORDED", d.Status == "RECORDED" && d.Version == 1)
	c.check("decision fields", d.Text == "Proceed with EVA-3" && d.RecordedBy == "N0" && d.Rationale == "Weather window" && d.OriginWindow == "W2")

	decRev := mk("decision_update", map[string]interface{}{"did": "DEC-N0-1", "text": "Proceed with EVA-3 at 14:00", "version": 2},
		"N1", 1, "2026-08-01T12:10:00.000Z", mars.PrivateKeyB64, "")
	c.check("decision_update id prefix DEC", decRev.EntryId == "DEC-N1-1")
	decRes := mk("decision_update", map[string]interface{}{"did": "DEC-N0-1", "status": "RESCINDED", "version": 3},
		"N0", 2, "2026-08-01T12:20:00.000Z", host.PrivateKeyB64, "")
	r2, sup2 := ltx.ReduceDecisions([]ltx.RegisterEntry{decRes, dec1, decRev})
	d = r2["DEC-N0-1"]
	c.check("decision update applied", d.Text == "Proceed with EVA-3 at 14:00")
	c.check("decision RESCINDED v3", d.Status == "RESCINDED" && d.Version == 3)
	c.check("decision editor recorded", d.Editor == "N0")
	c.check("decision older update superseded", contains(sup2, decRev.EntryId))

	decA := mk("decision_update", map[string]interface{}{"did": "DEC-N0-1", "text": "From N0", "version": 5}, "N0", 7, "2026-08-01T13:00:00.000Z", host.PrivateKeyB64, "")
	decB := mk("decision_update", map[string]interface{}{"did": "DEC-N0-1", "text": "From N1", "version": 5}, "N1", 7, "2026-08-01T13:00:00.000Z", mars.PrivateKeyB64, "")
	c1, s1 := ltx.ReduceDecisions([]ltx.RegisterEntry{dec1, decB, decA})
	c2, s2 := ltx.ReduceDecisions([]ltx.RegisterEntry{decA, dec1, decB})
	c.check("decision tie lowest nodeId wins", c1["DEC-N0-1"].Text == "From N0")
	c.check("decision tie loser superseded", contains(s1, decB.EntryId) && !contains(s1, decA.EntryId))
	c.check("decision reduce order-independent", reflect.DeepEqual(c1, c2) && reflect.DeepEqual(s1, s2))
	decHi := mk("decision_update", map[string]interface{}{"did": "DEC-N0-1", "text": "N1 v6", "version": 6}, "N1", 8, "2026-08-01T12:30:00.000Z", mars.PrivateKeyB64, "")
	hi, _ := ltx.ReduceDecisions([]ltx.RegisterEntry{dec1, decA, decHi})
	c.check("decision higher version wins", hi["DEC-N0-1"].Text == "N1 v6")

	decOrphan := mk("decision_update", map[string]interface{}{"did": "DEC-NOPE-1", "version": 2}, "N1", 9, "2026-08-01T12:40:00.000Z", mars.PrivateKeyB64, "")
	decDup := mk("decision", map[string]interface{}{"text": "dup"}, "N1", 10, "2026-08-01T12:50:00.000Z", mars.PrivateKeyB64, "DEC-N0-1")
	r3, sup3 := ltx.ReduceDecisions([]ltx.RegisterEntry{dec1, decOrphan, decDup})
	c.check("decision orphan update superseded", contains(sup3, "DEC-N1-9"))
	c.check("decision duplicate create ignored", r3["DEC-N0-1"].Text == "Proceed with EVA-3" && r3["DEC-N0-1"].RecordedBy == "N0")
	only, _ := ltx.ReduceDecisions([]ltx.RegisterEntry{dec1, decRev})
	acts, _ := ltx.ReduceActions([]ltx.RegisterEntry{dec1})
	c.check("decision reducer ignores others", len(only) == 1 && len(acts) == 0)

	merged, snap, err := ltx.RunMergeSegment([]ltx.RegisterEntry{dec1}, []ltx.RegisterEntry{decRev}, cache, ltx.CreateEntryOptions{
		SessionId: "LTX-DEC-TEST", NodeId: "N0", Seq: 99, Timestamp: "2026-08-01T15:00:00.000Z", PrivateKeyB64: host.PrivateKeyB64,
	})
	c.check("runMergeSegment ok", err == nil && len(merged.Entries) == 2 && len(merged.Rejected) == 0)
	c.check("snapshot is merge_snapshot MRG", snap.Type == "merge_snapshot" && snap.EntryId == "MRG-N0-99")
	c.check("snapshot verifies", ltx.VerifyRegisterEntry(snap, cache).Valid)
	reg, _ := snap.Content["decisionRegister"].(map[string]interface{})
	entry, _ := reg["DEC-N0-1"].(map[string]interface{})
	c.check("snapshot decisionRegister", entry["version"] == 2 && entry["text"] == "Proceed with EVA-3 at 14:00" && entry["editor"] == "N1")
	c.check("snapshot has question/action registers", snap.Content["questionRegister"] != nil && snap.Content["actionRegister"] != nil)
	c.check("snapshot counts", snap.Content["entryCount"] == 2 && snap.Content["rejectedCount"] == 0)
	c.check("snapshot mergedRoot", snap.Content["mergedRoot"] == ltx.EntriesRoot(merged.Entries))
	unknown, _ := ltx.GenerateNIK(ltx.GenerateNIKOpts{})
	stray := mk("decision", map[string]interface{}{"text": "stray"}, "N7", 1, "2026-08-01T12:00:00.000Z", unknown.PrivateKeyB64, "")
	m2, snap2, _ := ltx.RunMergeSegment([]ltx.RegisterEntry{dec1, stray}, nil, cache, ltx.CreateEntryOptions{
		SessionId: "LTX-DEC-TEST", NodeId: "N0", Seq: 100, Timestamp: "2026-08-01T15:00:00.000Z", PrivateKeyB64: host.PrivateKeyB64,
	})
	c.check("merge rejects unverifiable entry", len(m2.Rejected) == 1 && m2.Rejected[0].Reason == "key_not_in_cache" && snap2.Content["rejectedCount"] == 1)
	ab := ltx.MergeLogs([]ltx.RegisterEntry{dec1}, []ltx.RegisterEntry{decRev, dec1}, cache)
	ba := ltx.MergeLogs([]ltx.RegisterEntry{decRev, dec1}, []ltx.RegisterEntry{dec1}, cache)
	c.check("mergeLogs symmetric and de-duplicated", len(ab.Entries) == 2 && reflect.DeepEqual(ab.Entries, ba.Entries))
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

// memStoreNoDelete is a persistent adapter without Delete (markers set to 0).
type memStoreNoDelete map[string]int

func (m memStoreNoDelete) Get(k string) int    { return m[k] }
func (m memStoreNoDelete) Set(k string, v int) { m[k] = v }

func TestSequenceReorderWindow(t *testing.T) {
	c := &checker{t: t, name: "TestSequenceReorderWindow"}
	defer c.done()
	tr := ltx.CreateSequenceTracker("plan-001")
	tr.NextSeq("N0")
	tr.NextSeq("N0")
	tr.RecordSeq("N0", 1)
	tr.RecordSeq("N0", 2)
	gap := tr.RecordSeq("N0", 5)
	c.check("gap detected", gap.Accepted && gap.Gap && gap.GapSize == 2 && !gap.Late)
	tr.RecordSeq("N0", 6)
	c.check("lastSeenSeq correct", tr.LastSeenSeq("N0") == 6)
	c.check("currentSeq correct", tr.CurrentSeq("N0") == 2)
	c.check("missingSeqs lists gap", reflect.DeepEqual(tr.MissingSeqs("N0"), []int{3, 4}))
	late4 := tr.RecordSeq("N0", 4)
	c.check("late seq accepted", late4.Accepted && late4.Late)
	c.check("late seq no gap, no reason", !late4.Gap && late4.GapSize == 0 && late4.Reason == "")
	c.check("late seq keeps high-water mark", tr.LastSeenSeq("N0") == 6)
	dup4 := tr.RecordSeq("N0", 4)
	c.check("late seq duplicate is replay", !dup4.Accepted && dup4.Reason == "replay" && !dup4.Late)
	c.check("in-order result late=false", !tr.RecordSeq("N0", 7).Late)
	c.check("duplicate of in-order is replay", tr.RecordSeq("N0", 6).Reason == "replay")
	c.check("missingSeqs after late", reflect.DeepEqual(tr.MissingSeqs("N0"), []int{3}))
	c.check("invalid seq rejected", ltx.CheckSeq(map[string]interface{}{"seq": 1.5}, tr, "N0").Reason == "invalid_seq" &&
		!ltx.CheckSeq(map[string]interface{}{"seq": math.NaN()}, tr, "N0").Accepted)
	c.check("unsafe seq rejected", tr.RecordSeq("N0", 1<<53).Reason == "invalid_seq")
	c.check("non-number seq is missing_seq", ltx.CheckSeq(map[string]interface{}{"seq": "8"}, tr, "N0").Reason == "missing_seq")
	c.check("default reorder window", ltx.SEQ_REORDER_WINDOW == 64 && tr.ReorderWindow() == 64)

	w4 := 4
	tw, _ := ltx.CreateSequenceTrackerWithOptions("plan-window", ltx.SequenceTrackerOptions{ReorderWindow: &w4})
	tw.RecordSeq("N1", 1)
	big := tw.RecordSeq("N1", 10)
	c.check("window gap reported in full", big.Gap && big.GapSize == 8)
	c.check("window bounds missing markers", reflect.DeepEqual(tw.MissingSeqs("N1"), []int{7, 8, 9}))
	c.check("below window rejected", tw.RecordSeq("N1", 5).Reason == "replay")
	c.check("inside window accepted late", tw.RecordSeq("N1", 8).Late)
	tw.RecordSeq("N1", 12)
	c.check("slid-out marker rejected", !tw.RecordSeq("N1", 7).Accepted)
	c.check("slid-in gap accepted late", tw.RecordSeq("N1", 11).Late)
	zero := 0
	t0, _ := ltx.CreateSequenceTrackerWithOptions("plan-strict", ltx.SequenceTrackerOptions{ReorderWindow: &zero})
	t0.RecordSeq("N0", 1)
	t0.RecordSeq("N0", 3)
	c.check("window 0 = strict monotonic", t0.RecordSeq("N0", 2).Reason == "replay")
	neg := -1
	_, err := ltx.CreateSequenceTrackerWithOptions("p", ltx.SequenceTrackerOptions{ReorderWindow: &neg})
	c.check("negative window errors", err != nil)

	persisted := memStoreNoDelete{}
	tA, _ := ltx.CreateSequenceTrackerWithOptions("plan-persist", ltx.SequenceTrackerOptions{Store: persisted})
	tA.RecordSeq("N2", 1)
	tA.RecordSeq("N2", 4)
	tB, _ := ltx.CreateSequenceTrackerWithOptions("plan-persist", ltx.SequenceTrackerOptions{Store: persisted})
	c.check("persisted late accepted", tB.RecordSeq("N2", 3).Late)
	c.check("persisted late not replayable", tB.RecordSeq("N2", 3).Reason == "replay")
	c.check("persisted replay rejected", tB.RecordSeq("N2", 4).Reason == "replay")
	c.check("storage key layout", persisted["ltx_seq_plan-persist_N2_rx"] == 4 && persisted["ltx_seq_plan-persist_N2_rx_miss_2"] == 1 &&
		persisted["ltx_seq_plan-persist_N2_rx_miss_3"] == 0)
	c.check("bundle helpers", strings.HasPrefix(fmt.Sprint(ltx.AddSeq(map[string]interface{}{}, tA, "N2")["seq"]), "1"))
}

// TestEncodeHashV3WireMatchesPlanID: the #l= wire JSON of a typed v3 plan must
// carry its v3 fields, so a receiver hashing the wire JSON (JS makePlanId)
// derives the same planId as MakePlanID (scripts/interop, issue #32).
func TestEncodeHashV3WireMatchesPlanID(t *testing.T) {
	wireOf := func(p ltx.LtxPlan) []byte {
		b, err := base64.RawURLEncoding.DecodeString(strings.TrimPrefix(ltx.EncodeHash(p), "#l="))
		if err != nil {
			t.Fatal(err)
		}
		return b
	}
	p := ltx.CreatePlan(ltx.CreatePlanOpts{Title: "Réunion Mars 🚀", Start: "2026-03-15T14:00:00.000Z", DelayS: 840})
	p.V = 3
	p.PlanVersion = 1
	p.Delays = map[string]int{"N0|N1": 842}
	wire := wireOf(p)
	if !strings.Contains(string(wire), `"delays":{"N0|N1":842}`) || !strings.Contains(string(wire), `"planVersion":1`) {
		t.Fatalf("v3 fields missing from wire JSON: %s", wire)
	}
	fromWire, err := ltx.MakePlanIDFromJSON(wire)
	if err != nil {
		t.Fatal(err)
	}
	// JS makePlanId(JSON.parse(wire)) for this plan.
	const want = "LTX-20260315-EARTHHQ-MARS-v3-4192925c"
	if got := ltx.MakePlanID(p); got != fromWire || got != want {
		t.Fatalf("MakePlanID %s, planId of wire JSON %s, JS %s", got, fromWire, want)
	}
	// A v2 plan's wire JSON is unchanged: no v3 keys.
	p.V, p.PlanVersion, p.Delays = 2, 0, nil
	if w := string(wireOf(p)); strings.Contains(w, "delays") || strings.Contains(w, "planVersion") {
		t.Fatalf("v2 wire JSON gained v3 keys: %s", w)
	}
}

// Issue #36: the typed wire JSON is exactly JSON.stringify (control
// characters; U+2028, which encoding/json would escape), MakePlanID strips
// JS \s whitespace (not only spaces, and not unicode.IsSpace), and segments
// keep speaker/label only when present.
func TestIssue36TypedWireAndWhitespace(t *testing.T) {
	p := ltx.LtxPlan{
		V:     2,
		Title: "Ctl\u0001\b\f\n\r\t\"\\\u001f\u007f \U0001F680",
		Start: "2026-03-15T14:00:00.000Z", Quantum: 3, Mode: "LTX-ASYNC",
		Nodes: []ltx.LtxNode{
			{ID: "N0", Name: "Earth\tHQ", Role: "HOST", Delay: 0, Location: "earth"},
			{ID: "N1", Name: "Ma\u00a0r\u3000s\u2009Hab-01", Role: "PARTICIPANT", Delay: 840, Location: "mars"},
			{ID: "N2", Name: "L-1\u2028Gate\ufeffway\n", Role: "PARTICIPANT", Delay: 2, Location: "moon"},
		},
		Segments: []ltx.LtxSegmentTemplate{
			{Type: "PLAN_CONFIRM", Q: 2},
			{Type: "TX", Q: 3, Speaker: "N0", Label: "Opening\tremarks"},
			{Type: "RX", Q: 3},
			{Type: "TX", Q: 2, Speaker: "N1"},
			{Type: "TX", Q: 1, Label: "Q&A \U0001F534"},
			{Type: "BUFFER", Q: 1},
		},
	}
	// JSON.stringify of the same plan object and its makePlanId, from ltx-sdk.js (node 22).
	const wantJSON = "{\"v\":2,\"title\":\"Ctl\\u0001\\b\\f\\n\\r\\t\\\"\\\\\\u001f\u007f \U0001F680\",\"start\":\"2026-03-15T14:00:00.000Z\",\"quantum\":3,\"mode\":\"LTX-ASYNC\",\"nodes\":[{\"id\":\"N0\",\"name\":\"Earth\\tHQ\",\"role\":\"HOST\",\"delay\":0,\"location\":\"earth\"},{\"id\":\"N1\",\"name\":\"Ma\u00a0r\u3000s\u2009Hab-01\",\"role\":\"PARTICIPANT\",\"delay\":840,\"location\":\"mars\"},{\"id\":\"N2\",\"name\":\"L-1\u2028Gate\ufeffway\\n\",\"role\":\"PARTICIPANT\",\"delay\":2,\"location\":\"moon\"}],\"segments\":[{\"type\":\"PLAN_CONFIRM\",\"q\":2},{\"type\":\"TX\",\"q\":3,\"speaker\":\"N0\",\"label\":\"Opening\\tremarks\"},{\"type\":\"RX\",\"q\":3},{\"type\":\"TX\",\"q\":2,\"speaker\":\"N1\"},{\"type\":\"TX\",\"q\":1,\"label\":\"Q&A \U0001F534\"},{\"type\":\"BUFFER\",\"q\":1}]}"
	const wantID = "LTX-20260315-EARTHHQ-MARS-L-1G-v2-9d8c90f7"
	wire, err := base64.RawURLEncoding.DecodeString(strings.TrimPrefix(ltx.EncodeHash(p), "#l="))
	if err != nil {
		t.Fatal(err)
	}
	if string(wire) != wantJSON {
		t.Fatalf("wire JSON is not JSON.stringify:\n got %q\nwant %q", wire, wantJSON)
	}
	parsed, err := ltx.ParseOrderedJSON(wire)
	if err != nil {
		t.Fatal(err)
	}
	if ltx.JSStringify(parsed) != string(wire) {
		t.Fatalf("wire JSON does not re-stringify identically")
	}
	fromWire, err := ltx.MakePlanIDFromJSON(wire)
	if err != nil {
		t.Fatal(err)
	}
	if got := ltx.MakePlanID(p); got != wantID || got != fromWire {
		t.Fatalf("MakePlanID %s, planId of wire JSON %s, JS %s", got, fromWire, wantID)
	}
	back := ltx.DecodeHash(ltx.EncodeHash(p))
	if back == nil || back.Title != p.Title || !reflect.DeepEqual(back.Nodes, p.Nodes) || !reflect.DeepEqual(back.Segments, p.Segments) {
		t.Fatalf("DecodeHash did not round-trip title, names, speaker/label: %+v", back)
	}

	// JS \s is not unicode.IsSpace: U+FEFF is stripped, U+0085 is kept.
	ws := ltx.LtxPlan{
		V: 2, Title: "t", Start: "2026-03-15T14:00:00.000Z", Quantum: 3, Mode: "LTX",
		Nodes: []ltx.LtxNode{
			{ID: "N0", Name: "\u00a0Ea\u1680rth\u205fHQ\u202f", Role: "HOST", Location: "earth"},
			{ID: "N1", Name: "\ufeffM\va\fr\u3000s", Role: "PARTICIPANT", Location: "mars"},
			{ID: "N2", Name: "X\u0085Y", Role: "PARTICIPANT", Location: "moon"},
		},
		Segments: []ltx.LtxSegmentTemplate{{Type: "TX", Q: 1}},
	}
	const wsWant = "LTX-20260315-EARTHHQ-MARS-X\u0085Y-v2-aa92073b"
	wsWire, _ := base64.RawURLEncoding.DecodeString(strings.TrimPrefix(ltx.EncodeHash(ws), "#l="))
	wsFromWire, err := ltx.MakePlanIDFromJSON(wsWire)
	if err != nil {
		t.Fatal(err)
	}
	if got := ltx.MakePlanID(ws); got != wsWant || wsFromWire != wsWant {
		t.Fatalf("whitespace: MakePlanID %q, planId of wire JSON %q, JS %q", got, wsFromWire, wsWant)
	}
}
