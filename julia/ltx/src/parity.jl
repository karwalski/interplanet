# parity.jl -- LTX parity with the JS reference SDK (issue #27)
#
# Mirrors javascript/ltx/ltx-sdk.js:
#   * insertion-ordered JSON (JsonObject) and JSON.stringify-compatible output
#   * makePlanId for JSON plans: frozen v2 imul31 hash over the UTF-16 code
#     units of JSON.stringify in the plan's own key order (§4.3); v3 SHA-256
#     over RFC 8785 canonical JSON (§4.5); planHash
#   * validatePlan (§3.5, §4, §7) incl. reserved_streams / reserved_branching
#   * upgradePlanToV3 (§4.4), which enforces the reserved fields
# Included from InterplanetLtx.jl.

using SHA

# ── Ordered JSON ───────────────────────────────────────────────────────────────

"""A JSON object that keeps its keys in source (insertion) order."""
struct JsonObject
    pairs::Vector{Pair{String,Any}}
end
JsonObject() = JsonObject(Pair{String,Any}[])

Base.haskey(o::JsonObject, k::AbstractString) = any(p -> p.first == k, o.pairs)
function Base.get(o::JsonObject, k::AbstractString, default)
    for p in o.pairs
        p.first == k && return p.second
    end
    return default
end
Base.getindex(o::JsonObject, k::AbstractString) =
    (v = get(o, k, _MISSING); v === _MISSING ? throw(KeyError(k)) : v)
Base.keys(o::JsonObject) = [p.first for p in o.pairs]
Base.length(o::JsonObject) = length(o.pairs)
const _MISSING = Symbol("json-missing")

"""Copy of `o` with key `k` set (JS spread: existing keys keep their position)."""
function json_with(o::JsonObject, k::AbstractString, v)
    ps = copy(o.pairs)
    for (i, p) in enumerate(ps)
        if p.first == k
            ps[i] = String(k) => v
            return JsonObject(ps)
        end
    end
    push!(ps, String(k) => v)
    return JsonObject(ps)
end

"""Copy of `o` without key `k`."""
json_without(o::JsonObject, k::AbstractString) = JsonObject(filter(p -> p.first != k, o.pairs))

"""
    parse_json_ordered(text) -> Any

Decode JSON text: objects become `JsonObject` (source key order), arrays
`Vector{Any}`, null `nothing`, integers `Int`, other numbers `Float64`.
"""
function parse_json_ordered(text::AbstractString)
    b = Vector{UInt8}(codeunits(String(text)))
    v, pos = _oj_value(b, _oj_ws(b, 1))
    _oj_ws(b, pos) > length(b) || error("json: trailing data at byte $pos")
    return v
end

function _oj_ws(b, pos)
    while pos <= length(b) && b[pos] in (0x20, 0x09, 0x0a, 0x0d)
        pos += 1
    end
    return pos
end

function _oj_value(b, pos)
    pos > length(b) && error("json: unexpected end")
    c = b[pos]
    c == UInt8('"') && return _oj_string(b, pos)
    c == UInt8('{') && return _oj_object(b, pos)
    c == UInt8('[') && return _oj_array(b, pos)
    if c == UInt8('t'); return true, pos + 4; end
    if c == UInt8('f'); return false, pos + 5; end
    if c == UInt8('n'); return nothing, pos + 4; end
    start = pos
    while pos <= length(b) && (UInt8('0') <= b[pos] <= UInt8('9') || b[pos] in UInt8.(('-', '+', '.', 'e', 'E')))
        pos += 1
    end
    tok = String(b[start:pos-1])
    isempty(tok) && error("json: unexpected byte $(Char(c)) at $start")
    v = any(ch -> ch in ('.', 'e', 'E'), tok) ? parse(Float64, tok) : parse(Int, tok)
    return v, pos
end

function _oj_string(b, pos)
    out = UInt8[]
    pos += 1
    while true
        pos > length(b) && error("json: unterminated string")
        c = b[pos]
        if c == UInt8('"')
            return String(out), pos + 1
        elseif c == UInt8('\\')
            e = Char(b[pos + 1])
            if e == 'u'
                cp = parse(Int, String(b[pos+2:pos+5]); base = 16)
                pos += 6
                if 0xD800 <= cp <= 0xDBFF && pos + 5 <= length(b) && b[pos] == UInt8('\\') && b[pos+1] == UInt8('u')
                    lo = parse(Int, String(b[pos+2:pos+5]); base = 16)
                    if 0xDC00 <= lo <= 0xDFFF
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                        pos += 6
                    end
                end
                # a lone surrogate is kept (as WTF-8), as JSON.parse keeps it
                append!(out, codeunits(string(Char(cp))))
            else
                m = Dict('n' => '\n', 't' => '\t', 'r' => '\r', 'b' => '\b', 'f' => '\f',
                         '/' => '/', '\\' => '\\', '"' => '"')
                haskey(m, e) || error("json: bad escape \\$e")
                push!(out, UInt8(m[e]))
                pos += 2
            end
        else
            push!(out, c)
            pos += 1
        end
    end
end

function _oj_object(b, pos)
    ps = Pair{String,Any}[]
    pos = _oj_ws(b, pos + 1)
    if pos <= length(b) && b[pos] == UInt8('}')
        return JsonObject(ps), pos + 1
    end
    while true
        pos = _oj_ws(b, pos)
        k, pos = _oj_string(b, pos)
        pos = _oj_ws(b, pos)
        b[pos] == UInt8(':') || error("json: expected : at $pos")
        v, pos = _oj_value(b, _oj_ws(b, pos + 1))
        push!(ps, k => v)
        pos = _oj_ws(b, pos)
        if b[pos] == UInt8('}')
            return JsonObject(ps), pos + 1
        end
        b[pos] == UInt8(',') || error("json: expected , or } at $pos")
        pos += 1
    end
end

function _oj_array(b, pos)
    out = Any[]
    pos = _oj_ws(b, pos + 1)
    if pos <= length(b) && b[pos] == UInt8(']')
        return out, pos + 1
    end
    while true
        v, pos = _oj_value(b, _oj_ws(b, pos))
        push!(out, v)
        pos = _oj_ws(b, pos)
        if b[pos] == UInt8(']')
            return out, pos + 1
        end
        b[pos] == UInt8(',') || error("json: expected , or ] at $pos")
        pos += 1
    end
end

# ── JSON.stringify / canonical JSON ────────────────────────────────────────────

"""
JSON.stringify string quoting: \\b \\t \\n \\f \\r, other C0 controls as \\u00xx,
everything else (DEL, U+2028, U+2029) raw. A Julia String can hold a lone
UTF-16 surrogate (as WTF-8); JSON.stringify writes one as a lowercase \\udxxx
escape, and a high+low pair (CESU-8) as its code point.
"""
function _js_quote(s::AbstractString)
    io = IOBuffer()
    print(io, '"')
    cs = collect(s)
    i = 1
    while i <= length(cs)
        c = cs[i]
        u = UInt32(c)
        if 0xD800 <= u <= 0xDFFF
            lo = i < length(cs) ? UInt32(cs[i + 1]) : UInt32(0)
            if u <= 0xDBFF && 0xDC00 <= lo <= 0xDFFF
                print(io, Char(0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)))
                i += 2
                continue
            end
            print(io, "\\u", string(u; base = 16, pad = 4))
        elseif c == '"'; print(io, "\\\"")
        elseif c == '\\'; print(io, "\\\\")
        elseif c == '\b'; print(io, "\\b")
        elseif c == '\f'; print(io, "\\f")
        elseif c == '\n'; print(io, "\\n")
        elseif c == '\r'; print(io, "\\r")
        elseif c == '\t'; print(io, "\\t")
        elseif u < 0x20; print(io, "\\u", lpad(string(u; base = 16), 4, '0'))
        else print(io, c)
        end
        i += 1
    end
    print(io, '"')
    return String(take!(io))
end

_js_number(x::Integer) = string(x)
function _js_number(x::AbstractFloat)
    isfinite(x) || return "null"
    (isinteger(x) && abs(x) < 1e21) && return string(Int128(x))
    return string(x)
end

"""
    json_stringify(x; canonical = false) -> String

Serialise like JavaScript `JSON.stringify` (no whitespace). `JsonObject` keeps
its key order; `Dict` keys are sorted. `canonical = true` sorts every object's
keys (RFC 8785 canonical JSON as used for v3 planIds and planHash).
"""
function json_stringify(x; canonical::Bool = false)
    x === nothing && return "null"
    x isa Bool && return x ? "true" : "false"
    x isa Number && return _js_number(x)
    x isa AbstractString && return _js_quote(x)
    if x isa JsonObject || x isa AbstractDict
        ps = x isa JsonObject ? x.pairs : [String(k) => v for (k, v) in x]
        if canonical || x isa AbstractDict
            ps = sort(ps; by = p -> transcode(UInt16, p.first))
        end
        return "{" * join([_js_quote(p.first) * ":" * json_stringify(p.second; canonical) for p in ps], ",") * "}"
    end
    x isa AbstractVector && return "[" * join([json_stringify(v; canonical) for v in x], ",") * "]"
    error("json_stringify: unsupported type $(typeof(x))")
end

"""RFC 8785 canonical JSON (sorted keys, no whitespace)."""
canonical_json(x) = json_stringify(x; canonical = true)

"""
    imul31_hex(s) -> String

`h = (Math.imul(31, h) + charCodeAt(i)) >>> 0` over the UTF-16 code units of
`s`, as 8 lowercase hex digits (LTX-SPECIFICATION.md §4.3).
"""
function imul31_hex(s::AbstractString)
    h = UInt32(0)
    for u in transcode(UInt16, String(s))
        h = UInt32(31) * h + UInt32(u)
    end
    return string(h; base = 16, pad = 8)
end

"""SHA-256 hex of the canonical JSON of a plan (prevPlanHash, §6.4)."""
plan_hash(plan) = bytes2hex(sha256(canonical_json(_as_json(plan))))

# ── Plans as JSON ──────────────────────────────────────────────────────────────

"""An `LtxPlan` as the ordered JSON object it serialises to (nodes before segments)."""
_as_json(plan::LtxPlan) = parse_json_ordered(_plan_to_json(plan))
_as_json(x) = x

_jget(o, k) = o isa JsonObject ? get(o, k, nothing) : o isa AbstractDict ? get(o, k, nothing) : nothing
_jhas(o, k) = (o isa JsonObject || o isa AbstractDict) && haskey(o, k)
_is_obj(x) = x isa JsonObject || x isa AbstractDict

"""ECMAScript \\s (WhiteSpace and LineTerminator). Julia's r"\\s" also matches
U+0085 and misses U+FEFF."""
_is_js_space(c::Char) = (u = UInt32(c);
    u == 0x20 || 0x09 <= u <= 0x0D || u == 0xA0 || u == 0x1680 || 0x2000 <= u <= 0x200A ||
    u == 0x2028 || u == 0x2029 || u == 0x202F || u == 0x205F || u == 0x3000 || u == 0xFEFF)

"""s.replace(/\\s+/g, rep) with JavaScript's \\s."""
function _js_space_replace(s::AbstractString, rep::AbstractString = "")
    io = IOBuffer()
    in_space = false
    for c in s
        if _is_js_space(c)
            in_space || print(io, rep)
            in_space = true
        else
            print(io, c)
            in_space = false
        end
    end
    return String(take!(io))
end

"""
s.slice(0, n) in UTF-16 code units. When the cut splits a surrogate pair, JS
keeps the lone high surrogate, and so does this: a Julia String holds it as
WTF-8, as the JSON layer does (planIdWtf8Hex in
spec/golden/plan-id-prefixes.json).
"""
function _utf16_first(s::AbstractString, n::Integer)
    io = IOBuffer()
    units = 0
    for c in s
        w = isvalid(c) && UInt32(c) >= 0x10000 ? 2 : 1
        if units + w > n
            units < n && print(io, Char(0xD800 + ((UInt32(c) - 0x10000) >> 10)))
            break
        end
        units += w
        print(io, c)
    end
    return String(take!(io))
end

"""name.replace(/\\s+/g, '').toUpperCase().slice(0, n): JS whitespace, JS
toUpperCase (full mapping, `js_uppercase` in upper.jl), UTF-16 code units."""
_short(name, n) = _utf16_first(js_uppercase(_js_space_replace(String(name))), n)

"""
    make_plan_id(plan::JsonObject) -> String

planId of a parsed JSON plan, exactly as `makePlanId` in ltx-sdk.js: v2 hashes
JSON.stringify in the plan's own key order over UTF-16 code units; v3 plans
(`v >= 3`) use SHA-256 over canonical JSON with a `-v3-` infix.
"""
function make_plan_id(plan::Union{JsonObject,AbstractDict})
    start = String(_jget(plan, "start"))
    date = replace(first(start, 10), "-" => "")
    nodes = something(_jget(plan, "nodes"), Any[])
    host_str = isempty(nodes) ? "HOST" : _short(something(_jget(nodes[1], "name"), "HOST"), 8)
    node_str = length(nodes) > 1 ?
        _utf16_first(join([_short(_jget(n, "name"), 4) for n in nodes[2:end]], "-"), 16) : "RX"
    v = _jget(plan, "v")
    if v isa Number && v >= 3
        return "LTX-$(date)-$(host_str)-$(node_str)-v3-$(first(plan_hash(plan), 8))"
    end
    return "LTX-$(date)-$(host_str)-$(node_str)-v2-$(imul31_hex(json_stringify(plan)))"
end

"""planId of a plan given as JSON text (key order preserved)."""
plan_id_from_json(text::AbstractString) = make_plan_id(parse_json_ordered(text))

# ── validatePlan (§3.5, §4, §7) ────────────────────────────────────────────────

const PLAN_SEGMENT_TYPES = vcat(SEG_TYPES, ["SPEAK", "REST", "PAD", "OPEN", "RELAY"])
const PLAN_MODES = ["LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC"]
const V3_ONLY_FIELDS = ["delays", "planVersion", "prevPlanHash", "questions", "actions", "streams"]

const PlanError = NamedTuple{(:code, :path, :message),Tuple{String,String,String}}
_perr(code, path, message) = PlanError((code, path, message))

"""Raised by `upgrade_plan_to_v3` when a plan uses reserved stream/branch fields."""
struct ReservedFieldError <: Exception
    code::String
    errors::Vector{PlanError}
    message::String
end
Base.showerror(io::IO, e::ReservedFieldError) = print(io, e.message)

"""Reserved-field violations only (§3.5 streams, §7 branching)."""
function reserved_field_errors(plan)
    plan = _as_json(plan)
    errors = PlanError[]
    _is_obj(plan) || return errors
    if _jhas(plan, "streams")
        s = _jget(plan, "streams")
        (s isa AbstractVector && isempty(s)) ||
            push!(errors, _perr("reserved_streams", "streams", "streams[] is reserved (§3.5) and MUST be absent or empty"))
    end
    for f in ("branches", "branching")
        _jhas(plan, f) && push!(errors, _perr("reserved_branching", f,
            "$f is reserved for branching (§7, not yet implemented) and MUST be absent"))
    end
    segs = _jget(plan, "segments")
    if segs isa AbstractVector
        for (i, s) in enumerate(segs)
            _is_obj(s) || continue
            _jhas(s, "stream") && push!(errors, _perr("reserved_streams", "segments[$(i-1)].stream",
                "segment stream is reserved (§3.5) and MUST be absent"))
            _jhas(s, "branch") && push!(errors, _perr("reserved_branching", "segments[$(i-1)].branch",
                "segment branch is reserved for branching (§7) and MUST be absent"))
        end
    end
    return errors
end

"""Throw `ReservedFieldError` if a plan uses reserved stream/branch fields."""
function assert_no_reserved_fields(plan, fn_name::AbstractString)
    errors = reserved_field_errors(plan)
    isempty(errors) && return nothing
    throw(ReservedFieldError(errors[1].code, errors, "$(fn_name): $(errors[1].message)"))
end

_js_int(x) = x isa Integer && !(x isa Bool) || (x isa AbstractFloat && isfinite(x) && isinteger(x))
_js_num(x) = x isa Real && !(x isa Bool)

const _ISO_RE = r"^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])(T([01]\d|2[0-4]):[0-5]\d(:[0-5]\d(\.\d+)?)?(Z|[+-]\d{2}:\d{2})?)?$"

"""
    validate_plan(plan) -> (valid = Bool, errors = Vector{PlanError})

Validate a v2 or v3 plan (`JsonObject`, `Dict{String,Any}` or `LtxPlan`)
against the wire format and the reserved-field rules, mirroring
`validatePlan` in ltx-sdk.js. Pure; never throws. Error codes:
not_an_object, invalid_version, missing_field, invalid_field,
invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
invalid_delays, reserved_streams, reserved_branching.
"""
function validate_plan(plan)
    plan = _as_json(plan)
    errors = PlanError[]
    err(code, path, msg) = push!(errors, _perr(code, path, msg))
    if !_is_obj(plan)
        err("not_an_object", "", "plan must be an object")
        return (valid = false, errors = errors)
    end
    v = _jget(plan, "v")
    isv(n) = _js_num(v) && v == n
    (isv(2) || isv(3)) || err("invalid_version", "v", "v must be 2 or 3")
    for f in ("title", "start", "quantum", "mode", "nodes", "segments")
        _jhas(plan, f) || err("missing_field", f, "$f is required")
    end
    _jhas(plan, "title") && !(_jget(plan, "title") isa AbstractString) &&
        err("invalid_field", "title", "title must be a string")
    if _jhas(plan, "start")
        st = _jget(plan, "start")
        (st isa AbstractString && occursin(_ISO_RE, st)) ||
            err("invalid_field", "start", "start must be an ISO 8601 UTC timestamp")
    end
    if _jhas(plan, "quantum")
        q = _jget(plan, "quantum")
        (_js_int(q) && 1 <= q <= 60) || err("invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)")
    end
    _jhas(plan, "mode") && !(_jget(plan, "mode") in PLAN_MODES) &&
        err("invalid_mode", "mode", "mode must be one of $(join(PLAN_MODES, ", "))")

    ids = Set{String}()
    if _jhas(plan, "nodes")
        nodes = _jget(plan, "nodes")
        if !(nodes isa AbstractVector) || isempty(nodes)
            err("invalid_nodes", "nodes", "nodes must be a non-empty array")
        else
            hosts = 0
            for (i, n) in enumerate(nodes)
                id = _jget(n, "id"); role = _jget(n, "role"); d = _jget(n, "delay")
                ok = _is_obj(n) && id isa AbstractString && !isempty(id) && !occursin('|', id) &&
                     _jget(n, "name") isa AbstractString && role in ("HOST", "PARTICIPANT", "OBSERVER") &&
                     _js_num(d) && d >= 0
                if !ok
                    err("invalid_nodes", "nodes[$(i-1)]", "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0")
                    continue
                end
                id in ids && err("duplicate_node_id", "nodes[$(i-1)].id", "duplicate node id $id")
                push!(ids, id)
                role == "HOST" && (hosts += 1)
            end
            h = nodes[1]
            h_ok = _is_obj(h) && _jget(h, "role") == "HOST" && _js_num(_jget(h, "delay")) && _jget(h, "delay") == 0
            (hosts == 1 && h_ok) || err("invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)")
        end
    end

    if _jhas(plan, "segments")
        segs = _jget(plan, "segments")
        if !(segs isa AbstractVector)
            err("invalid_segment", "segments", "segments must be an array")
        else
            for (i, s) in enumerate(segs)
                q = _jget(s, "q")
                if !(_is_obj(s) && _jget(s, "type") in PLAN_SEGMENT_TYPES && _js_int(q) && q >= 1)
                    err("invalid_segment", "segments[$(i-1)]", "segment needs a known type and integer q >= 1")
                    continue
                end
                if _jhas(s, "speaker") && !(_jget(s, "speaker") in ids)
                    err("unknown_speaker", "segments[$(i-1)].speaker", "speaker $(_jget(s, "speaker")) is not a node id")
                end
            end
        end
    end

    if isv(2)
        for f in V3_ONLY_FIELDS
            _jhas(plan, f) && err("v3_field_in_v2", f, "$f is a v3 field and MUST NOT appear in a v2 plan (§4.3)")
        end
    elseif isv(3)
        if _jhas(plan, "delays")
            d = _jget(plan, "delays")
            if !_is_obj(d)
                err("invalid_delays", "delays", "delays must be an object")
            else
                for k in keys(d)
                    parts = split(k, '|')
                    val = _jget(d, k)
                    ok = length(parts) == 2 && transcode(UInt16, String(parts[1])) < transcode(UInt16, String(parts[2])) &&
                         (isempty(ids) || (parts[1] in ids && parts[2] in ids)) && _js_num(val) && val >= 0
                    ok || err("invalid_delays", "delays.$k",
                              "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)")
                end
            end
        end
        if _jhas(plan, "planVersion")
            pv = _jget(plan, "planVersion")
            (_js_int(pv) && pv >= 1) || err("invalid_field", "planVersion", "planVersion must be an integer >= 1")
        end
        if _jhas(plan, "prevPlanHash")
            ph = _jget(plan, "prevPlanHash")
            (ph isa AbstractString && occursin(r"^[0-9a-f]{64}$", ph)) ||
                err("invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters")
        end
        for f in ("questions", "actions")
            _jhas(plan, f) && !(_jget(plan, f) isa AbstractVector) && err("invalid_field", f, "$f must be an array")
        end
    end

    append!(errors, reserved_field_errors(plan))
    return (valid = isempty(errors), errors = errors)
end

# ── upgradePlanToV3 (§4.4) ─────────────────────────────────────────────────────

"""
    upgrade_plan_to_v3(plan; extras = Pair{String,Any}[]) -> JsonObject

Explicitly upgrade a v2 plan (`JsonObject` or `LtxPlan`) to v3. Never
automatic: the result is a NEW plan with a new (v3) planId. `extras`
(e.g. `["delays" => JsonObject(["N0|N1" => 900])]`) are merged with JS spread
semantics; `v` becomes 3 and `planVersion` defaults to 1. Throws
`ReservedFieldError` (code "reserved_streams" or "reserved_branching") if the
result carries reserved fields (§3.5, §7).
"""
function upgrade_plan_to_v3(plan; extras = Pair{String,Any}[])
    out = _as_json(plan)
    for (k, v) in extras
        out = json_with(out, k, v)
    end
    pv = 1
    for (k, v) in extras
        k == "planVersion" && (pv = v)
    end
    out = json_with(json_with(out, "v", 3), "planVersion", pv)
    assert_no_reserved_fields(out, "upgradePlanToV3")
    return out
end
