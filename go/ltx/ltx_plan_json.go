package ltx

// Wire-format plan helpers that mirror ltx-sdk.js exactly:
//   - ParseOrderedJSON: JSON.parse with key insertion order preserved
//   - MakePlanIDFromJSON / PlanHashFromJSON: makePlanId / planHash over the
//     plan exactly as received (the frozen v2 hash is insertion-order
//     sensitive, LTX-SPECIFICATION.md §4.3)
//   - ValidatePlan: validatePlan (§3.5, §4, §7), including the reserved
//     streams / branching rules
//
// Golden vectors: spec/golden/plan-ids.json.

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
)

// ── Ordered JSON value ──────────────────────────────────────────────────────

// OrderedMember is one key/value pair of an OrderedObject.
type OrderedMember struct {
	Key   string
	Value interface{}
}

// OrderedObject is a JSON object that keeps key insertion order, as a
// JavaScript object does. Values are nil, bool, float64, string,
// []interface{} or OrderedObject.
type OrderedObject []OrderedMember

// Get returns the value for key and whether it is present.
func (o OrderedObject) Get(key string) (interface{}, bool) {
	for _, m := range o {
		if m.Key == key {
			return m.Value, true
		}
	}
	return nil, false
}

// Has reports whether key is present (Object.prototype.hasOwnProperty).
func (o OrderedObject) Has(key string) bool {
	_, ok := o.Get(key)
	return ok
}

// set assigns key in place when present, else appends (JS assignment order).
func (o OrderedObject) set(key string, v interface{}) OrderedObject {
	for i := range o {
		if o[i].Key == key {
			o[i].Value = v
			return o
		}
	}
	return append(o, OrderedMember{Key: key, Value: v})
}

// ParseOrderedJSON parses JSON like JSON.parse, preserving object key order.
// A duplicate key keeps its first position and takes the last value.
func ParseOrderedJSON(data []byte) (interface{}, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	v, err := parseOrderedValue(dec)
	if err != nil {
		return nil, err
	}
	if _, err := dec.Token(); err != io.EOF {
		return nil, errors.New("ParseOrderedJSON: trailing data")
	}
	return v, nil
}

func parseOrderedValue(dec *json.Decoder) (interface{}, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	switch t := tok.(type) {
	case json.Delim:
		switch t {
		case '{':
			obj := OrderedObject{}
			for dec.More() {
				kt, err := dec.Token()
				if err != nil {
					return nil, err
				}
				key, ok := kt.(string)
				if !ok {
					return nil, errors.New("ParseOrderedJSON: object key is not a string")
				}
				val, err := parseOrderedValue(dec)
				if err != nil {
					return nil, err
				}
				obj = obj.set(key, val)
			}
			if _, err := dec.Token(); err != nil {
				return nil, err
			}
			return obj, nil
		case '[':
			arr := []interface{}{}
			for dec.More() {
				val, err := parseOrderedValue(dec)
				if err != nil {
					return nil, err
				}
				arr = append(arr, val)
			}
			if _, err := dec.Token(); err != nil {
				return nil, err
			}
			return arr, nil
		}
		return nil, fmt.Errorf("ParseOrderedJSON: unexpected delimiter %v", t)
	case json.Number:
		f, err := strconv.ParseFloat(string(t), 64)
		if err != nil {
			return nil, err
		}
		return f, nil
	default:
		return t, nil // string, bool, nil
	}
}

// toOrdered converts a Go value (map, slice, struct, LtxPlan, number, ...)
// or an already-ordered value into the ordered representation. Plain maps
// have no insertion order, so their keys are sorted.
func toOrdered(v interface{}) interface{} {
	switch t := v.(type) {
	case nil, bool, string, float64, OrderedObject:
		return t
	case []byte:
		if o, err := ParseOrderedJSON(t); err == nil {
			return o
		}
		return nil
	case json.RawMessage:
		return toOrdered([]byte(t))
	case int:
		return float64(t)
	case int64:
		return float64(t)
	case int32:
		return float64(t)
	case float32:
		return float64(t)
	case json.Number:
		f, _ := t.Float64()
		return f
	case []interface{}:
		if t == nil {
			return nil
		}
		out := make([]interface{}, len(t))
		for i, e := range t {
			out[i] = toOrdered(e)
		}
		return out
	case map[string]interface{}:
		keys := make([]string, 0, len(t))
		for k := range t {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		out := make(OrderedObject, 0, len(keys))
		for _, k := range keys {
			out = append(out, OrderedMember{Key: k, Value: toOrdered(t[k])})
		}
		return out
	}
	data, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	o, err := ParseOrderedJSON(data)
	if err != nil {
		return nil
	}
	return o
}

// ── JavaScript-compatible serialisation ─────────────────────────────────────

// jsNumber formats a float64 as Number.prototype.toString does (which is
// also the RFC 8785 number form).
func jsNumber(f float64) string {
	if math.IsNaN(f) || math.IsInf(f, 0) {
		return "null"
	}
	if f == 0 {
		return "0"
	}
	neg := f < 0
	if neg {
		f = -f
	}
	s := strconv.FormatFloat(f, 'e', -1, 64) // d.ddddde±XX
	mant, expStr, _ := strings.Cut(s, "e")
	exp, _ := strconv.Atoi(expStr)
	digits := strings.Replace(mant, ".", "", 1)
	k := len(digits)
	n := exp + 1
	var out string
	switch {
	case k <= n && n <= 21:
		out = digits + strings.Repeat("0", n-k)
	case 0 < n && n <= 21:
		out = digits[:n] + "." + digits[n:]
	case -6 < n && n <= 0:
		out = "0." + strings.Repeat("0", -n) + digits
	default:
		e := n - 1
		sign := "+"
		if e < 0 {
			sign = "-"
			e = -e
		}
		out = digits[:1]
		if k > 1 {
			out += "." + digits[1:]
		}
		out += "e" + sign + strconv.Itoa(e)
	}
	if neg {
		return "-" + out
	}
	return out
}

// jsQuote quotes a string as JSON.stringify does.
func jsQuote(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\b':
			b.WriteString(`\b`)
		case '\f':
			b.WriteString(`\f`)
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		default:
			if r < 0x20 {
				fmt.Fprintf(&b, `\u%04x`, r)
			} else {
				b.WriteRune(r)
			}
		}
	}
	b.WriteByte('"')
	return b.String()
}

func jsSerialize(v interface{}, canonical bool) string {
	switch t := v.(type) {
	case nil:
		return "null"
	case bool:
		if t {
			return "true"
		}
		return "false"
	case float64:
		return jsNumber(t)
	case string:
		return jsQuote(t)
	case []interface{}:
		parts := make([]string, len(t))
		for i, e := range t {
			parts[i] = jsSerialize(e, canonical)
		}
		return "[" + strings.Join(parts, ",") + "]"
	case OrderedObject:
		members := t
		if canonical {
			members = append(OrderedObject(nil), t...)
			sort.SliceStable(members, func(i, j int) bool {
				return utf16Less(members[i].Key, members[j].Key)
			})
		}
		parts := make([]string, len(members))
		for i, m := range members {
			parts[i] = jsQuote(m.Key) + ":" + jsSerialize(m.Value, canonical)
		}
		return "{" + strings.Join(parts, ",") + "}"
	}
	return jsSerialize(toOrdered(v), canonical)
}

// JSStringify serialises a value as JSON.stringify does (insertion order).
func JSStringify(v interface{}) string { return jsSerialize(toOrdered(v), false) }

// CanonicalJSONOrdered serialises a value as ltx-sdk.js canonicalJSON does:
// keys sorted by UTF-16 code units at every level (RFC 8785 key order).
func CanonicalJSONOrdered(v interface{}) string { return jsSerialize(toOrdered(v), true) }

// utf16Less compares strings by UTF-16 code units (Array.prototype.sort).
func utf16Less(a, b string) bool {
	ua, ub := utf16.Encode([]rune(a)), utf16.Encode([]rune(b))
	for i := 0; i < len(ua) && i < len(ub); i++ {
		if ua[i] != ub[i] {
			return ua[i] < ub[i]
		}
	}
	return len(ua) < len(ub)
}

// imul31 is the frozen v2 planId hash: h = imul(31, h) + charCodeAt(i) over
// the UTF-16 code units of s, as uint32.
func imul31(s string) uint32 {
	var h uint32
	for _, u := range utf16.Encode([]rune(s)) {
		h = h*31 + uint32(u)
	}
	return h
}

// ── makePlanId / planHash over the wire plan ────────────────────────────────

// isJSSpace reports whether r is in JS \s (ECMAScript WhiteSpace and
// LineTerminator). unicode.IsSpace differs: it includes U+0085 (NEL) and
// excludes U+FEFF.
func isJSSpace(r rune) bool {
	switch r {
	case '\t', '\n', '\v', '\f', '\r', ' ', 0x00A0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
		return true
	}
	return r >= 0x2000 && r <= 0x200A
}

// jsNameToken is name.replace(/\s+/g, "").toUpperCase().slice(0, max).
func jsNameToken(name string, max int) string {
	stripped := strings.Map(func(r rune) rune {
		if isJSSpace(r) {
			return -1
		}
		return r
	}, name)
	return utf16Prefix(strings.ToUpper(stripped), max)
}

// utf16Prefix is String.prototype.slice(0, max) (UTF-16 code units).
func utf16Prefix(s string, max int) string {
	u := utf16.Encode([]rune(s))
	if len(u) > max {
		u = u[:max]
	}
	return string(utf16.Decode(u))
}

// parseJSDate parses the ISO 8601 forms Date.parse accepts for plan start.
func parseJSDate(s string) (time.Time, bool) {
	for _, layout := range []string{time.RFC3339Nano, "2006-01-02T15:04:05.000Z07:00", "2006-01-02T15:04Z07:00", "2006-01-02"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

// upgradeConfigOrdered mirrors upgradeConfig: v2+ plans with nodes are
// returned unchanged; v1 configs (txName/rxName/delay) gain v:2 and nodes.
func upgradeConfigOrdered(cfg OrderedObject) OrderedObject {
	v, _ := cfg.Get("v")
	vn, _ := v.(float64)
	if nodes, ok := cfg.Get("nodes"); ok && vn >= 2 {
		if arr, ok := nodes.([]interface{}); ok && len(arr) > 0 {
			return cfg
		}
	}
	str := func(k, def string) string {
		if s, ok := getString(cfg, k); ok && s != "" {
			return s
		}
		return def
	}
	rx, _ := getString(cfg, "rxName")
	loc := "earth"
	if strings.Contains(strings.ToLower(rx), "mars") {
		loc = "mars"
	} else if strings.Contains(strings.ToLower(rx), "moon") {
		loc = "moon"
	}
	delay := 0.0
	if d, ok := cfg.Get("delay"); ok {
		if f, ok := d.(float64); ok {
			delay = f
		}
	}
	out := append(OrderedObject(nil), cfg...)
	out = out.set("v", 2.0)
	out = out.set("nodes", []interface{}{
		OrderedObject{{"id", "N0"}, {"name", str("txName", "Earth HQ")}, {"role", "HOST"}, {"delay", 0.0}, {"location", "earth"}},
		OrderedObject{{"id", "N1"}, {"name", str("rxName", "Mars Hab-01")}, {"role", "PARTICIPANT"}, {"delay", delay}, {"location", loc}},
	})
	return out
}

func getString(o OrderedObject, k string) (string, bool) {
	v, ok := o.Get(k)
	if !ok {
		return "", false
	}
	s, ok := v.(string)
	return s, ok
}

// MakePlanIDFromJSON computes the planId of a plan exactly as ltx-sdk.js
// makePlanId does, from the plan's JSON as received. Unlike MakePlanID (which
// serialises the typed LtxPlan in a fixed key order), this preserves the
// wire key order the frozen v2 hash depends on, and keeps every field the
// plan carries (relay, questions, streams, ...). plan may be JSON bytes, an
// OrderedObject, a map or an LtxPlan.
func MakePlanIDFromJSON(plan interface{}) (string, error) {
	o, ok := toOrdered(plan).(OrderedObject)
	if !ok {
		return "", errors.New("makePlanId: plan must be a JSON object")
	}
	c := upgradeConfigOrdered(o)
	start, _ := getString(c, "start")
	t, ok := parseJSDate(start)
	if !ok {
		return "", fmt.Errorf("makePlanId: invalid start %q", start)
	}
	date := t.UTC().Format("20060102")
	nodesV, _ := c.Get("nodes")
	nodes, _ := nodesV.([]interface{})
	hostStr := "HOST"
	if len(nodes) > 0 {
		if n0, ok := nodes[0].(OrderedObject); ok {
			if name, ok := getString(n0, "name"); ok && name != "" {
				hostStr = jsNameToken(name, 8)
			}
		}
	}
	nodeStr := "RX"
	if len(nodes) > 1 {
		parts := make([]string, 0, len(nodes)-1)
		for _, n := range nodes[1:] {
			no, _ := n.(OrderedObject)
			name, _ := getString(no, "name")
			parts = append(parts, jsNameToken(name, 4))
		}
		nodeStr = utf16Prefix(strings.Join(parts, "-"), 16)
	}
	vv, _ := c.Get("v")
	if v, _ := vv.(float64); v >= 3 {
		digest := sha256.Sum256([]byte(jsSerialize(c, true)))
		return fmt.Sprintf("LTX-%s-%s-%s-v3-%x", date, hostStr, nodeStr, digest[:4]), nil
	}
	return fmt.Sprintf("LTX-%s-%s-%s-v2-%08x", date, hostStr, nodeStr, imul31(jsSerialize(c, false))), nil
}

// PlanHashFromJSON is planHash over the plan as received: SHA-256 hex of its
// canonical JSON (used for prevPlanHash, §6.4). plan may be JSON bytes or any
// value MakePlanIDFromJSON accepts.
func PlanHashFromJSON(plan interface{}) string {
	digest := sha256.Sum256([]byte(CanonicalJSONOrdered(plan)))
	return fmt.Sprintf("%x", digest[:])
}

// ── validatePlan (LTX-SPECIFICATION.md §3.5, §4, §7) ────────────────────────

// PlanError is one validatePlan finding.
type PlanError struct {
	Code    string `json:"code"`
	Path    string `json:"path"`
	Message string `json:"message"`
}

// PlanValidation is the validatePlan result.
type PlanValidation struct {
	Valid  bool        `json:"valid"`
	Errors []PlanError `json:"errors"`
}

// ReservedFieldError is returned by the constructing paths (CreateAmendment,
// CreateSessionFromJSON) when a plan uses reserved stream or branching
// fields. Code is the first error's code ("reserved_streams" or
// "reserved_branching"); Errors lists all of them.
type ReservedFieldError struct {
	Code   string
	Errors []PlanError
	msg    string
}

func (e *ReservedFieldError) Error() string { return e.msg }

var (
	planSegmentTypes = []string{"PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE", "SPEAK", "REST", "PAD", "OPEN", "RELAY"}
	planModes        = []string{"LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC"}
	v3OnlyFields     = []string{"delays", "planVersion", "prevPlanHash", "questions", "actions", "streams"}
	prevHashRe       = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

func inList(list []string, v interface{}) bool {
	s, ok := v.(string)
	if !ok {
		return false
	}
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

func isJSInteger(v interface{}) (float64, bool) {
	f, ok := v.(float64)
	if !ok || math.IsNaN(f) || math.IsInf(f, 0) || f != math.Trunc(f) {
		return 0, false
	}
	return f, true
}

// isJSObject reports typeof v === 'object' && v !== null (arrays included).
func isJSObject(v interface{}) bool {
	switch v.(type) {
	case OrderedObject, []interface{}:
		return true
	}
	return false
}

// reservedFieldErrors lists reserved-field violations only (§3.5, §7).
func reservedFieldErrors(v interface{}) []PlanError {
	plan, ok := v.(OrderedObject)
	if !ok {
		return nil
	}
	var errs []PlanError
	if s, has := plan.Get("streams"); has {
		arr, isArr := s.([]interface{})
		if !isArr || len(arr) != 0 {
			errs = append(errs, PlanError{"reserved_streams", "streams", "streams[] is reserved (§3.5) and MUST be absent or empty"})
		}
	}
	for _, f := range []string{"branches", "branching"} {
		if plan.Has(f) {
			errs = append(errs, PlanError{"reserved_branching", f, f + " is reserved for branching (§7, not yet implemented) and MUST be absent"})
		}
	}
	segsV, _ := plan.Get("segments")
	segs, _ := segsV.([]interface{})
	for i, s := range segs {
		so, ok := s.(OrderedObject)
		if !ok {
			continue
		}
		if so.Has("stream") {
			errs = append(errs, PlanError{"reserved_streams", fmt.Sprintf("segments[%d].stream", i), "segment stream is reserved (§3.5) and MUST be absent"})
		}
		if so.Has("branch") {
			errs = append(errs, PlanError{"reserved_branching", fmt.Sprintf("segments[%d].branch", i), "segment branch is reserved for branching (§7) and MUST be absent"})
		}
	}
	return errs
}

// assertNoReservedFields returns a *ReservedFieldError when plan uses
// reserved stream / branching fields.
func assertNoReservedFields(plan interface{}, fnName string) error {
	errs := reservedFieldErrors(toOrdered(plan))
	if len(errs) == 0 {
		return nil
	}
	return &ReservedFieldError{Code: errs[0].Code, Errors: errs, msg: fnName + ": " + errs[0].Message}
}

// ValidatePlan validates a v2 or v3 plan against the wire format
// (spec/ltx-schema.json, LTX-SPECIFICATION.md §4) and the reserved-field
// rules (§3.5 streams, §7 branching), mirroring ltx-sdk.js validatePlan.
// plan may be JSON bytes, an OrderedObject, a map or an LtxPlan. Pure;
// never panics.
//
// Error codes: not_an_object, invalid_version, missing_field, invalid_field,
// invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
// duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
// invalid_delays, reserved_streams, reserved_branching.
func ValidatePlan(planIn interface{}) PlanValidation {
	errs := []PlanError{}
	add := func(code, path, msg string) { errs = append(errs, PlanError{code, path, msg}) }
	plan, ok := toOrdered(planIn).(OrderedObject)
	if !ok {
		add("not_an_object", "", "plan must be an object")
		return PlanValidation{Valid: false, Errors: errs}
	}
	vRaw, _ := plan.Get("v")
	isV2, isV3 := false, false
	if f, ok := vRaw.(float64); ok {
		isV2, isV3 = f == 2, f == 3
	}
	if !isV2 && !isV3 {
		add("invalid_version", "v", "v must be 2 or 3")
	}
	for _, f := range []string{"title", "start", "quantum", "mode", "nodes", "segments"} {
		if !plan.Has(f) {
			add("missing_field", f, f+" is required")
		}
	}
	if t, has := plan.Get("title"); has {
		if _, ok := t.(string); !ok {
			add("invalid_field", "title", "title must be a string")
		}
	}
	if s, has := plan.Get("start"); has {
		str, ok := s.(string)
		if !ok {
			add("invalid_field", "start", "start must be an ISO 8601 UTC timestamp")
		} else if _, ok := parseJSDate(str); !ok {
			add("invalid_field", "start", "start must be an ISO 8601 UTC timestamp")
		}
	}
	if q, has := plan.Get("quantum"); has {
		if f, ok := isJSInteger(q); !ok || f < 1 || f > 60 {
			add("invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)")
		}
	}
	if m, has := plan.Get("mode"); has && !inList(planModes, m) {
		add("invalid_mode", "mode", "mode must be one of "+strings.Join(planModes, ", "))
	}

	ids := map[string]bool{}
	if nv, has := plan.Get("nodes"); has {
		nodes, isArr := nv.([]interface{})
		if !isArr || len(nodes) == 0 {
			add("invalid_nodes", "nodes", "nodes must be a non-empty array")
		} else {
			hosts := 0
			for i, n := range nodes {
				no, _ := n.(OrderedObject)
				id, idOK := getString(no, "id")
				_, nameOK := getString(no, "name")
				role, _ := no.Get("role")
				dv, _ := no.Get("delay")
				delay, delayOK := dv.(float64)
				if no == nil || !idOK || id == "" || strings.Contains(id, "|") || !nameOK ||
					!inList([]string{"HOST", "PARTICIPANT", "OBSERVER"}, role) || !delayOK || !(delay >= 0) {
					add("invalid_nodes", fmt.Sprintf("nodes[%d]", i), `node needs id (no "|"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0`)
					continue
				}
				if ids[id] {
					add("duplicate_node_id", fmt.Sprintf("nodes[%d].id", i), "duplicate node id "+id)
				}
				ids[id] = true
				if role == "HOST" {
					hosts++
				}
			}
			h, _ := nodes[0].(OrderedObject)
			hRole, _ := h.Get("role")
			hDelay, _ := h.Get("delay")
			if hosts != 1 || h == nil || hRole != "HOST" || hDelay != 0.0 {
				add("invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)")
			}
		}
	}

	if sv, has := plan.Get("segments"); has {
		segs, isArr := sv.([]interface{})
		if !isArr {
			add("invalid_segment", "segments", "segments must be an array")
		} else {
			for i, s := range segs {
				so, _ := s.(OrderedObject)
				typ, _ := so.Get("type")
				qv, _ := so.Get("q")
				q, qOK := isJSInteger(qv)
				if !isJSObject(s) || !inList(planSegmentTypes, typ) || !qOK || q < 1 {
					add("invalid_segment", fmt.Sprintf("segments[%d]", i), "segment needs a known type and integer q >= 1")
					continue
				}
				if sp, has := so.Get("speaker"); has {
					spStr, isStr := sp.(string)
					if !isStr || !ids[spStr] {
						add("unknown_speaker", fmt.Sprintf("segments[%d].speaker", i), fmt.Sprintf("speaker %s is not a node id", jsDisplay(sp)))
					}
				}
			}
		}
	}

	if isV2 {
		for _, f := range v3OnlyFields {
			if plan.Has(f) {
				add("v3_field_in_v2", f, f+" is a v3 field and MUST NOT appear in a v2 plan (§4.3)")
			}
		}
	} else if isV3 {
		if d, has := plan.Get("delays"); has {
			dObj, ok := d.(OrderedObject)
			if !ok {
				add("invalid_delays", "delays", "delays must be an object")
			} else {
				for _, m := range dObj {
					parts := strings.Split(m.Key, "|")
					val, isNum := m.Value.(float64)
					if len(parts) != 2 || !utf16Less(parts[0], parts[1]) ||
						(len(ids) > 0 && (!ids[parts[0]] || !ids[parts[1]])) ||
						!isNum || !(val >= 0) {
						add("invalid_delays", "delays."+m.Key, `key must be two known node ids joined by "|" in sorted order; value >= 0 (§3.7.2)`)
					}
				}
			}
		}
		if pv, has := plan.Get("planVersion"); has {
			if f, ok := isJSInteger(pv); !ok || f < 1 {
				add("invalid_field", "planVersion", "planVersion must be an integer >= 1")
			}
		}
		if ph, has := plan.Get("prevPlanHash"); has {
			if s, ok := ph.(string); !ok || !prevHashRe.MatchString(s) {
				add("invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters")
			}
		}
		for _, f := range []string{"questions", "actions"} {
			if v, has := plan.Get(f); has {
				if _, ok := v.([]interface{}); !ok {
					add("invalid_field", f, f+" must be an array")
				}
			}
		}
	}

	errs = append(errs, reservedFieldErrors(plan)...)
	return PlanValidation{Valid: len(errs) == 0, Errors: errs}
}

func jsDisplay(v interface{}) string {
	if s, ok := v.(string); ok {
		return s
	}
	return JSStringify(v)
}
