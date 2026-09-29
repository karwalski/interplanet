// Interop driver for go/ltx (see scripts/interop/run.js).
package main

import (
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	ltx "github.com/interplanet/ltx"
)

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func unhash(h string) []byte {
	b, err := base64.RawURLEncoding.DecodeString(strings.TrimPrefix(h, "#l="))
	must(err)
	return b
}

func main() {
	inDir, outDir := os.Args[1], os.Args[2]

	plan := ltx.CreatePlan(ltx.CreatePlanOpts{Title: "Réunion Mars 🚀", Start: "2026-03-15T14:00:00.000Z"})
	plan.Quantum = 3
	plan.Mode = "LTX-ASYNC"
	plan.Nodes = []ltx.LtxNode{
		{ID: "N0", Name: "Earth HQ", Role: "HOST", Delay: 0, Location: "earth"},
		{ID: "N1", Name: "Mars Hab-01", Role: "PARTICIPANT", Delay: 840, Location: "mars"},
		{ID: "N2", Name: "L-1 Gateway", Role: "PARTICIPANT", Delay: 2, Location: "moon"},
	}
	plan.Segments = []ltx.LtxSegmentTemplate{
		{Type: "PLAN_CONFIRM", Q: 2},
		{Type: "TX", Q: 3, Speaker: "N0", Label: "Ouverture: état de la mission"},
		{Type: "RX", Q: 3},
		{Type: "TX", Q: 2, Speaker: "N1", Label: "Réponse 🔴"},
		{Type: "BUFFER", Q: 1},
	}

	must(os.WriteFile(filepath.Join(outDir, "wire-v2.json"), unhash(ltx.EncodeHash(plan)), 0o644))
	fmt.Println("ID_V2", ltx.MakePlanID(plan))

	// No UpgradePlanToV3 in Go: the typed plan carries the v3 fields directly.
	v3 := plan
	v3.V = 3
	v3.PlanVersion = 1
	v3.Delays = map[string]int{"N1|N2": 842}
	must(os.WriteFile(filepath.Join(outDir, "wire-v3.json"), unhash(ltx.EncodeHash(v3)), 0o644))
	fmt.Println("ID_V3", ltx.MakePlanID(v3))
	fmt.Println("NOTE v3 built by setting V/PlanVersion/Delays on LtxPlan (no upgrade function)")

	ctlCase(outDir)

	for _, v := range []string{"2", "3", "P"} {
		data, err := os.ReadFile(filepath.Join(inDir, "js-v"+v+".json"))
		must(err)
		id, err := ltx.MakePlanIDFromJSON(data)
		must(err)
		fmt.Println("JS_V"+v, id)
	}
}

// ctlCase is the issue #36 extra case (not a run.js column): control
// characters and JS \s whitespace (tab, NBSP, U+3000, U+2028, BOM, LF) in the
// title and node names, plus a speaker-only and a label-only segment. (A Go
// string cannot hold a lone surrogate, so the title has none.) The typed wire
// JSON must be exactly what JSON.stringify writes for it, and the typed
// planId must equal the JSON-based planId of that wire and the JS reference
// id (ltx-sdk.js makePlanId on the same plan object).
func ctlCase(outDir string) {
	ctl := ltx.LtxPlan{
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
	const ref = "LTX-20260315-EARTHHQ-MARS-L-1G-v2-9d8c90f7"
	wire := unhash(ltx.EncodeHash(ctl))
	must(os.WriteFile(filepath.Join(outDir, "wire-ctl.json"), wire, 0o644))
	parsed, err := ltx.ParseOrderedJSON(wire)
	must(err)
	id := ltx.MakePlanID(ctl)
	jsonID, err := ltx.MakePlanIDFromJSON(wire)
	must(err)
	ok := ltx.JSStringify(parsed) == string(wire) && id == jsonID && id == ref
	verdict := " (ok)"
	if !ok {
		verdict = " (MISMATCH)"
	}
	fmt.Printf("NOTE ctl/whitespace case: typed %s, JSON %s, JS %s%s\n", id, jsonID, ref, verdict)
	if !ok {
		os.Exit(1)
	}
}
