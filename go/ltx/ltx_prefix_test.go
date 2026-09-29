package ltx_test

// Conformance: spec/golden/plan-id-prefixes.json (issue #37, spec §4.3).
// HOSTSTR / NODESTR use JS whitespace, JS toUpperCase (full Unicode mapping
// with special casing) and UTF-16 slicing. A Go string must hold valid UTF-8
// here, so a lone surrogate left by the slicing is U+FFFD: the expected id is
// planIdUtf8 on the JSON path (MakePlanIDFromJSON) and the typed path
// (MakePlanID on LtxPlan, which writes nodes before segments: the v2 hash
// matches only for nodes-first vectors, the prefix always).

import (
	"encoding/json"
	"os"
	"strings"
	"testing"

	ltx "github.com/interplanet/ltx"
)

type prefixVector struct {
	Name          string          `json:"name"`
	Plan          json.RawMessage `json:"plan"`
	PlanID        string          `json:"planId"`
	PlanIDUtf8    string          `json:"planIdUtf8"`
	LoneSurrogate bool            `json:"loneSurrogate"`
}

func TestGoldenPlanIDPrefixes(t *testing.T) {
	c := &checker{t: t, name: "TestGoldenPlanIDPrefixes"}
	defer c.done()
	data, err := os.ReadFile("../../spec/golden/plan-id-prefixes.json")
	if err != nil {
		t.Fatalf("read prefix vectors: %v", err)
	}
	var g struct {
		Vectors []prefixVector `json:"vectors"`
	}
	if err := json.Unmarshal(data, &g); err != nil {
		t.Fatalf("parse prefix vectors: %v", err)
	}
	c.check("prefix vectors present", len(g.Vectors) >= 18)
	prefix := func(id string) string { return id[:len(id)-12] }
	for _, v := range g.Vectors {
		want := v.PlanIDUtf8
		id, err := ltx.MakePlanIDFromJSON([]byte(v.Plan))
		c.check("prefix json "+v.Name+" (got "+id+", want "+want+")", err == nil && id == want)

		var typed ltx.LtxPlan
		if err := json.Unmarshal(v.Plan, &typed); err != nil {
			t.Fatalf("typed %s: %v", v.Name, err)
		}
		tid := ltx.MakePlanID(typed)
		c.check("prefix typed prefix "+v.Name+" (got "+tid+")", prefix(tid) == prefix(want))
		raw := string(v.Plan)
		if typed.V >= 3 || strings.Index(raw, `"nodes"`) < strings.Index(raw, `"segments"`) {
			c.check("prefix typed "+v.Name+" (got "+tid+")", tid == want)
		}
	}
}
