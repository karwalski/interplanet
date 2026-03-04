"""
    InterplanetLtx

Julia port of ltx-sdk.js — LTX (Light-Time eXchange) Developer SDK v1.0.0.

Provides plan creation, segment computation, URL encoding/decoding,
ICS calendar generation, and REST helpers for LTX interplanetary sessions.
"""
module InterplanetLtx

using Base64

export LtxNode, LtxSegmentSpec, LtxPlan, LtxSegmentResult, LtxNodeUrl
export PROTOCOL_VERSION, DEFAULT_QUANTUM, DEFAULT_SEGMENTS, SEG_TYPES
export create_plan, compute_segments, total_min
export make_plan_id, encode_hash, decode_hash, build_node_urls
export generate_ics, format_hms, format_utc
export store_session, get_session

# ── Constants ──────────────────────────────────────────────────────────────────

const PROTOCOL_VERSION = "1.0.0"
const DEFAULT_QUANTUM  = 3   # minutes per quantum

const SEG_TYPES = ["PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE"]

const DEFAULT_API_BASE = "https://interplanet.live/api/ltx.php"

# ── Data structures ────────────────────────────────────────────────────────────

"""Represents a participant node in an LTX session."""
struct LtxNode
    id       ::String   # "N0", "N1", …
    name     ::String
    role     ::String   # "HOST" or "PARTICIPANT"
    delay    ::Int      # one-way signal delay in seconds
    location ::String   # e.g. "earth", "mars"
end

"""A segment specification: type + quantum multiplier."""
struct LtxSegmentSpec
    type ::String
    q    ::Int
end

"""Full LTX session plan."""
struct LtxPlan
    v        ::Int                      # schema version (2)
    title    ::String
    start    ::String                   # ISO 8601 UTC
    quantum  ::Int                      # minutes per quantum
    mode     ::String
    nodes    ::Vector{LtxNode}
    segments ::Vector{LtxSegmentSpec}
end

"""A computed timed segment."""
struct LtxSegmentResult
    type     ::String
    start_ms ::Int64
    end_ms   ::Int64
    dur_min  ::Int
end

"""A perspective URL for one node."""
struct LtxNodeUrl
    node_id ::String
    name    ::String
    role    ::String
    url     ::String
end

# ── Default segments ───────────────────────────────────────────────────────────

"""The canonical 7-segment LTX template."""
const DEFAULT_SEGMENTS = LtxSegmentSpec[
    LtxSegmentSpec("PLAN_CONFIRM", 2),
    LtxSegmentSpec("TX",           2),
    LtxSegmentSpec("RX",           2),
    LtxSegmentSpec("CAUCUS",       2),
    LtxSegmentSpec("TX",           2),
    LtxSegmentSpec("RX",           2),
    LtxSegmentSpec("BUFFER",       1),
]

# ── Internal utilities ─────────────────────────────────────────────────────────

"""URL-safe base64 encode: UTF-8 bytes → standard base64 → replace + with - and / with _ → strip padding."""
function _b64enc(s::AbstractString)::String
    raw = base64encode(Vector{UInt8}(codeunits(s)))
    return replace(replace(replace(raw, "+" => "-"), "/" => "_"), "=" => "")
end

"""URL-safe base64 decode → UTF-8 string, or nothing on error."""
function _b64dec(token::AbstractString)::Union{String,Nothing}
    # Restore standard base64 characters
    b = replace(replace(String(token), "-" => "+"), "_" => "/")
    # Re-add padding to make length a multiple of 4
    pad = mod(4 - mod(length(b), 4), 4)
    b = b * "="^pad
    try
        return String(base64decode(b))
    catch
        return nothing
    end
end

# ── ISO 8601 parsing ───────────────────────────────────────────────────────────

"""
Parse an ISO 8601 UTC string (YYYY-MM-DDTHH:MM:SSZ or with fractional seconds)
to epoch milliseconds (Int64).
"""
function _parse_iso_ms(iso::AbstractString)::Int64
    s = strip(iso)
    # Strip trailing Z
    if endswith(s, "Z")
        s = s[1:end-1]
    end
    # Strip +00:00 suffix
    if endswith(s, "+00:00")
        s = s[1:end-6]
    end

    # Parse date and time components
    yr = parse(Int, s[1:4])
    mo = parse(Int, s[6:7])
    dy = parse(Int, s[9:10])
    hr = parse(Int, s[12:13])
    mi = parse(Int, s[15:16])
    sc = parse(Int, s[18:19])
    ms = 0
    if length(s) >= 23 && s[20] == '.'
        frac_str = s[21:min(23, length(s))]
        ms = parse(Int, rpad(frac_str, 3, '0')[1:3])
    end

    days = _days_since_epoch(yr, mo, dy)
    return Int64(days) * Int64(86_400_000) +
           Int64(hr)   * Int64(3_600_000)  +
           Int64(mi)   * Int64(60_000)     +
           Int64(sc)   * Int64(1_000)      +
           Int64(ms)
end

"""Return the number of days since 1970-01-01 (Unix epoch) for the given date."""
function _days_since_epoch(yr::Int, mo::Int, dy::Int)::Int
    y = yr - 1
    month_days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    is_leap = (mod(yr, 4) == 0 && mod(yr, 100) != 0) || mod(yr, 400) == 0
    if is_leap
        month_days[2] = 29
    end
    day_of_year = dy
    for i in 1:(mo - 1)
        day_of_year += month_days[i]
    end
    # Rata Die formula
    rata_die = 365 * y + div(y, 4) - div(y, 100) + div(y, 400) + day_of_year
    # Unix epoch 1970-01-01 = Rata Die 719163
    return rata_die - 719163
end

"""Convert days since Unix epoch to (year, month, day) tuple."""
function _days_to_date(days::Int)
    # Rata Die of the day
    z = days + 719163
    # Algorithm from Howard Hinnant's date algorithms
    z += 306
    h  = 100 * z - 25
    a  = div(h, 3652425)
    b  = a - div(a, 4)
    yr = div(100 * b + h, 36525)
    c  = b + z - 365 * yr - div(yr, 4)
    mo = div(5 * c + 456, 153)
    dy = c - div(153 * mo - 457, 5)
    if mo > 12
        yr += 1
        mo -= 12
    end
    return yr, mo, dy
end

"""Format epoch ms as ISO 8601 UTC string (YYYY-MM-DDTHH:MM:SSZ)."""
function _ms_to_iso(ms::Int64)::String
    total_s = div(ms, 1000)
    days    = div(total_s, 86400)
    rem_s   = mod(total_s, 86400)
    hr      = div(rem_s, 3600)
    mi      = div(mod(rem_s, 3600), 60)
    sc      = mod(rem_s, 60)
    yr, mo, dy = _days_to_date(Int(days))
    return string(yr) * "-" *
           lpad(mo, 2, '0') * "-" *
           lpad(dy, 2, '0') * "T" *
           lpad(hr, 2, '0') * ":" *
           lpad(mi, 2, '0') * ":" *
           lpad(sc, 2, '0') * "Z"
end

"""Format epoch ms as ICS datetime string (yyyyMMddTHHmmssZ)."""
function _ms_to_ics_dt(ms::Int64)::String
    total_s = div(ms, 1000)
    days    = div(total_s, 86400)
    rem_s   = mod(total_s, 86400)
    hr      = div(rem_s, 3600)
    mi      = div(mod(rem_s, 3600), 60)
    sc      = mod(rem_s, 60)
    yr, mo, dy = _days_to_date(Int(days))
    return string(yr) *
           lpad(mo, 2, '0') *
           lpad(dy, 2, '0') * "T" *
           lpad(hr, 2, '0') *
           lpad(mi, 2, '0') *
           lpad(sc, 2, '0') * "Z"
end

"""Return current UTC epoch milliseconds."""
function _now_ms()::Int64
    return round(Int64, time() * 1000)
end

"""Return current UTC time rounded down to minute + 5 minutes, as ISO string."""
function _default_start()::String
    ms = _now_ms()
    ms = (ms ÷ Int64(60_000)) * Int64(60_000) + Int64(5 * 60_000)
    return _ms_to_iso(ms)
end

# ── Plan JSON serialization ────────────────────────────────────────────────────

"""
Serialize a plan to compact JSON with exact key order:
v, title, start, quantum, mode, nodes, segments.
Node key order: id, name, role, delay, location.
Segment key order: type, q.
"""
function _plan_to_json(plan::LtxPlan)::String
    buf = IOBuffer()
    print(buf, "{\"v\":", plan.v)
    print(buf, ",\"title\":", _json_str(plan.title))
    print(buf, ",\"start\":", _json_str(plan.start))
    print(buf, ",\"quantum\":", plan.quantum)
    print(buf, ",\"mode\":", _json_str(plan.mode))
    print(buf, ",\"nodes\":[")
    for (i, n) in enumerate(plan.nodes)
        if i > 1; print(buf, ","); end
        print(buf, "{\"id\":", _json_str(n.id))
        print(buf, ",\"name\":", _json_str(n.name))
        print(buf, ",\"role\":", _json_str(n.role))
        print(buf, ",\"delay\":", n.delay)
        print(buf, ",\"location\":", _json_str(n.location), "}")
    end
    print(buf, "],\"segments\":[")
    for (i, s) in enumerate(plan.segments)
        if i > 1; print(buf, ","); end
        print(buf, "{\"type\":", _json_str(s.type), ",\"q\":", s.q, "}")
    end
    print(buf, "]}")
    return String(take!(buf))
end

"""JSON-encode a string value with proper escaping."""
function _json_str(s::AbstractString)::String
    buf = IOBuffer()
    print(buf, '"')
    for c in s
        if c == '"'
            print(buf, "\\\"")
        elseif c == '\\'
            print(buf, "\\\\")
        elseif c == '\n'
            print(buf, "\\n")
        elseif c == '\r'
            print(buf, "\\r")
        elseif c == '\t'
            print(buf, "\\t")
        else
            print(buf, c)
        end
    end
    print(buf, '"')
    return String(take!(buf))
end

# ── Plan hash ─────────────────────────────────────────────────────────────────

"""
Compute the polynomial hash of a plan's JSON string matching ltx-sdk.js makePlanId.
Uses unsigned 32-bit overflow arithmetic (equivalent to Math.imul(31, h) in JS).
"""
function _plan_hash(json_str::AbstractString)::UInt32
    h = UInt32(0)
    for c in json_str
        # h = (31 * h + codepoint(c)) as UInt32 — wraps on overflow
        h = UInt32(31) * h + UInt32(codepoint(c))
    end
    return h
end

# ── Minimal JSON parser ────────────────────────────────────────────────────────

"""Parse a JSON string literal starting at pos. Returns (value, next_pos)."""
function _parse_json_string(s::String, pos::Int)
    @assert pos <= length(s) && s[pos] == '"' "Expected '\"' at position $pos"
    buf = IOBuffer()
    i = pos + 1
    while i <= length(s)
        c = s[i]
        if c == '"'
            return String(take!(buf)), i + 1
        elseif c == '\\'
            i += 1
            i > length(s) && error("Unexpected end of string escape")
            esc = s[i]
            if     esc == '"';  print(buf, '"')
            elseif esc == '\\'; print(buf, '\\')
            elseif esc == 'n';  print(buf, '\n')
            elseif esc == 'r';  print(buf, '\r')
            elseif esc == 't';  print(buf, '\t')
            else;               print(buf, esc)
            end
        else
            print(buf, c)
        end
        i += 1
    end
    error("Unterminated JSON string")
end

"""Skip whitespace at pos; return the first non-whitespace position."""
function _skip_ws(s::String, pos::Int)::Int
    while pos <= length(s)
        c = s[pos]
        if c == ' ' || c == '\t' || c == '\n' || c == '\r'
            pos += 1
        else
            break
        end
    end
    return pos
end

"""Parse a JSON number starting at pos. Returns (value, next_pos)."""
function _parse_json_number(s::String, pos::Int)
    start = pos
    if pos <= length(s) && s[pos] == '-'; pos += 1; end
    while pos <= length(s) && isdigit(s[pos]); pos += 1; end
    if pos <= length(s) && s[pos] == '.'
        pos += 1
        while pos <= length(s) && isdigit(s[pos]); pos += 1; end
    end
    if pos <= length(s) && (s[pos] == 'e' || s[pos] == 'E')
        pos += 1
        if pos <= length(s) && (s[pos] == '+' || s[pos] == '-'); pos += 1; end
        while pos <= length(s) && isdigit(s[pos]); pos += 1; end
    end
    numstr = s[start:pos-1]
    if '.' in numstr || 'e' in numstr || 'E' in numstr
        return parse(Float64, numstr), pos
    else
        return parse(Int, numstr), pos
    end
end

"""Parse any JSON value starting at pos. Returns (value, next_pos)."""
function _parse_json_value(s::String, pos::Int)
    pos = _skip_ws(s, pos)
    pos > length(s) && error("Unexpected end of JSON input at pos $pos")
    c = s[pos]
    if c == '"'
        return _parse_json_string(s, pos)
    elseif c == '{'
        return _parse_json_object(s, pos)
    elseif c == '['
        return _parse_json_array(s, pos)
    elseif c == 't'
        return true, pos + 4
    elseif c == 'f'
        return false, pos + 5
    elseif c == 'n'
        return nothing, pos + 4
    elseif c == '-' || isdigit(c)
        return _parse_json_number(s, pos)
    else
        error("Unexpected JSON character '$c' at pos $pos")
    end
end

"""Parse a JSON object `{...}` starting at pos. Returns (Dict{String,Any}, next_pos)."""
function _parse_json_object(s::String, pos::Int)
    @assert pos <= length(s) && s[pos] == '{' "Expected '{' at pos $pos"
    pos += 1
    result = Dict{String,Any}()
    pos = _skip_ws(s, pos)
    if pos <= length(s) && s[pos] == '}'
        return result, pos + 1
    end
    while true
        pos = _skip_ws(s, pos)
        key, pos = _parse_json_string(s, pos)
        pos = _skip_ws(s, pos)
        pos <= length(s) && s[pos] == ':' || error("Expected ':' at pos $pos")
        pos += 1
        pos = _skip_ws(s, pos)
        val, pos = _parse_json_value(s, pos)
        result[key] = val
        pos = _skip_ws(s, pos)
        if pos > length(s) || s[pos] == '}'
            return result, (pos <= length(s) ? pos + 1 : pos)
        end
        s[pos] == ',' || error("Expected ',' or '}' at pos $pos, got '$(s[pos])'")
        pos += 1
    end
end

"""Parse a JSON array `[...]` starting at pos. Returns (Vector{Any}, next_pos)."""
function _parse_json_array(s::String, pos::Int)
    @assert pos <= length(s) && s[pos] == '[' "Expected '[' at pos $pos"
    pos += 1
    result = Any[]
    pos = _skip_ws(s, pos)
    if pos <= length(s) && s[pos] == ']'
        return result, pos + 1
    end
    while true
        pos = _skip_ws(s, pos)
        val, pos = _parse_json_value(s, pos)
        push!(result, val)
        pos = _skip_ws(s, pos)
        if pos > length(s) || s[pos] == ']'
            return result, (pos <= length(s) ? pos + 1 : pos)
        end
        s[pos] == ',' || error("Expected ',' or ']' at pos $pos")
        pos += 1
    end
end

"""Parse a JSON object string into a Dict{String,Any}. Returns nothing on failure."""
function _parse_plan_json(json::String)::Union{Dict{String,Any},Nothing}
    try
        result, _ = _parse_json_object(json, _skip_ws(json, 1))
        return result
    catch
        return nothing
    end
end

"""Convert a Dict{String,Any} parsed from JSON into an LtxPlan. Returns nothing on failure."""
function _dict_to_plan(d::Dict{String,Any})::Union{LtxPlan,Nothing}
    try
        v_raw   = get(d, "v", 2)
        v_int   = v_raw isa Int ? v_raw : Int(v_raw)
        title   = get(d, "title", "")::String
        start   = get(d, "start", "")::String
        q_raw   = get(d, "quantum", DEFAULT_QUANTUM)
        quantum = q_raw isa Int ? q_raw : Int(q_raw)
        mode    = get(d, "mode", "LTX")::String

        # Parse nodes
        nodes = LtxNode[]
        for rn in get(d, "nodes", Any[])
            nd = rn isa Dict{String,Any} ? rn : Dict{String,Any}()
            delay_raw = get(nd, "delay", 0)
            delay_int = delay_raw isa Int ? delay_raw : Int(delay_raw)
            push!(nodes, LtxNode(
                get(nd, "id",       "N0")::String,
                get(nd, "name",     "")::String,
                get(nd, "role",     "HOST")::String,
                delay_int,
                get(nd, "location", "earth")::String,
            ))
        end

        # Parse segments
        segs = LtxSegmentSpec[]
        for rs in get(d, "segments", Any[])
            sd = rs isa Dict{String,Any} ? rs : Dict{String,Any}()
            q_raw2 = get(sd, "q", 2)
            q_int  = q_raw2 isa Int ? q_raw2 : Int(q_raw2)
            push!(segs, LtxSegmentSpec(get(sd, "type", "TX")::String, q_int))
        end

        return LtxPlan(v_int, title, start, quantum, mode, nodes, segs)
    catch
        return nothing
    end
end

# ── Plan creation ──────────────────────────────────────────────────────────────

"""
    create_plan(; host_name, remote_name, delay, title, start_iso,
                  quantum, mode, host_location, remote_location) -> LtxPlan

Create a new LTX session plan with two nodes (HOST + PARTICIPANT) and
the canonical 7-segment template.

# Keyword arguments
- `host_name`        Name of the host node (default: "Earth HQ")
- `remote_name`      Name of the remote node (default: "Mars Hab-01")
- `delay`            One-way signal delay in seconds (default: 0)
- `title`            Session title (default: "LTX Session")
- `start_iso`        ISO 8601 UTC start time (default: current time + 5 min)
- `quantum`          Minutes per quantum (default: 3)
- `mode`             Protocol mode (default: "LTX")
- `host_location`    Host location key (default: "earth")
- `remote_location`  Remote location key (default: "mars")
"""
function create_plan(;
    host_name        ::String = "Earth HQ",
    remote_name      ::String = "Mars Hab-01",
    delay            ::Int    = 0,
    title            ::String = "LTX Session",
    start_iso        ::String = "",
    quantum          ::Int    = DEFAULT_QUANTUM,
    mode             ::String = "LTX",
    host_location    ::String = "earth",
    remote_location  ::String = "mars",
)::LtxPlan
    start = isempty(start_iso) ? _default_start() : start_iso
    nodes = LtxNode[
        LtxNode("N0", host_name,   "HOST",        0,     host_location),
        LtxNode("N1", remote_name, "PARTICIPANT",  delay, remote_location),
    ]
    segs = copy(DEFAULT_SEGMENTS)
    return LtxPlan(2, title, start, quantum, mode, nodes, segs)
end

# ── Segment computation ────────────────────────────────────────────────────────

"""
    compute_segments(plan) -> Vector{LtxSegmentResult}

Compute the timed segment array for a plan.
Each result has: type, start_ms, end_ms, dur_min.
"""
function compute_segments(plan::LtxPlan)::Vector{LtxSegmentResult}
    q_ms   = Int64(plan.quantum) * Int64(60_000)
    t      = _parse_iso_ms(plan.start)
    result = LtxSegmentResult[]
    for s in plan.segments
        dur_ms  = Int64(s.q) * q_ms
        end_ms  = t + dur_ms
        dur_min = s.q * plan.quantum
        push!(result, LtxSegmentResult(s.type, t, end_ms, dur_min))
        t = end_ms
    end
    return result
end

"""
    total_min(plan) -> Int

Total session duration in minutes.
"""
function total_min(plan::LtxPlan)::Int
    return sum(s.q * plan.quantum for s in plan.segments)
end

# ── Plan ID ────────────────────────────────────────────────────────────────────

"""
    make_plan_id(plan) -> String

Compute the deterministic plan ID string.
Format: "LTX-YYYYMMDD-HOSTSTR-NODESTR-v2-XXXXXXXX"
"""
function make_plan_id(plan::LtxPlan)::String
    # Extract date from start timestamp
    start_ms = _parse_iso_ms(plan.start)
    days     = Int(div(div(start_ms, 1000), 86400))
    yr, mo, dy = _days_to_date(days)
    date_str = string(yr) * lpad(mo, 2, '0') * lpad(dy, 2, '0')

    # Host string: first node name, spaces removed, uppercased, max 8 chars
    host_str = if !isempty(plan.nodes)
        s = uppercase(replace(plan.nodes[1].name, " " => ""))
        length(s) > 8 ? s[1:8] : s
    else
        "HOST"
    end

    # Node string: remaining nodes abbreviated to 4 chars each, max 16 chars total
    node_str = if length(plan.nodes) > 1
        parts = map(plan.nodes[2:end]) do n
            s = uppercase(replace(n.name, " " => ""))
            length(s) > 4 ? s[1:4] : s
        end
        joined = join(parts, "-")
        length(joined) > 16 ? joined[1:16] : joined
    else
        "RX"
    end

    # Hash of the JSON representation (unsigned 32-bit polynomial)
    json_str = _plan_to_json(plan)
    h        = _plan_hash(json_str)
    hash_hex = string(h; base=16, pad=8)

    return "LTX-$(date_str)-$(host_str)-$(node_str)-v2-$(hash_hex)"
end

# ── URL hash encoding ──────────────────────────────────────────────────────────

"""
    encode_hash(plan) -> String

Encode a plan to a URL hash fragment "#l=…" using base64url encoding.
JSON is serialized with exact key order: v, title, start, quantum, mode, nodes, segments.
"""
function encode_hash(plan::LtxPlan)::String
    return "#l=" * _b64enc(_plan_to_json(plan))
end

"""
    decode_hash(fragment) -> Union{LtxPlan,Nothing}

Decode a plan from a URL hash fragment ("#l=…", "l=…", or raw base64url token).
Returns nothing if the fragment is invalid.
"""
function decode_hash(fragment::AbstractString)::Union{LtxPlan,Nothing}
    token = String(fragment)
    if startswith(token, "#"); token = token[2:end]; end
    if startswith(token, "l="); token = token[3:end]; end
    json_str = _b64dec(token)
    json_str === nothing && return nothing
    d = _parse_plan_json(json_str)
    d === nothing && return nothing
    return _dict_to_plan(d)
end

# ── Node URLs ──────────────────────────────────────────────────────────────────

"""
    build_node_urls(plan, base_url="") -> Vector{LtxNodeUrl}

Build perspective URLs for all nodes in a plan.
Each URL is: base_url?node=<id>#l=<encoded_plan>
"""
function build_node_urls(plan::LtxPlan, base_url::AbstractString = "")::Vector{LtxNodeUrl}
    hash      = encode_hash(plan)             # "#l=…"
    hash_part = lstrip(hash, '#')             # "l=…"
    # Strip any existing query string or fragment from the base URL
    clean_base = let s = String(base_url)
        idx = findfirst(c -> c == '?' || c == '#', s)
        idx === nothing ? s : s[1:idx-1]
    end
    return LtxNodeUrl[
        LtxNodeUrl(n.id, n.name, n.role,
                   "$(clean_base)?node=$(n.id)#$(hash_part)")
        for n in plan.nodes
    ]
end

# ── ICS generation ─────────────────────────────────────────────────────────────

"""Convert a node name to an ICS-safe ID (whitespace → "-", uppercased)."""
function _to_node_id(name::AbstractString)::String
    return uppercase(replace(String(name), r"\s+" => "-"))
end

"""
    generate_ics(plan) -> String

Generate LTX-extended iCalendar (.ics) content for a plan.
Lines are joined with CRLF (\\r\\n) per RFC 5545.
"""
function generate_ics(plan::LtxPlan)::String
    segs     = compute_segments(plan)
    start_ms = _parse_iso_ms(plan.start)
    end_ms   = isempty(segs) ? start_ms : segs[end].end_ms
    plan_id  = make_plan_id(plan)
    dt_stamp = _ms_to_ics_dt(_now_ms())
    dt_start = _ms_to_ics_dt(start_ms)
    dt_end   = _ms_to_ics_dt(end_ms)

    nodes        = plan.nodes
    host         = isempty(nodes) ? LtxNode("N0", "Earth HQ", "HOST", 0, "earth") : nodes[1]
    participants = length(nodes) > 1 ? nodes[2:end] : LtxNode[]

    part_names = isempty(participants) ?
        "remote nodes" :
        join([p.name for p in participants], ", ")

    delay_desc = isempty(participants) ?
        "no participant delay configured" :
        join(["$(p.name): $(div(p.delay, 60)) min one-way" for p in participants], " · ")

    seg_tpl = join([s.type for s in plan.segments], ",")

    lines = String[
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//InterPlanet//LTX v1.1//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "BEGIN:VEVENT",
        "UID:$(plan_id)@interplanet.live",
        "DTSTAMP:$(dt_stamp)",
        "DTSTART:$(dt_start)",
        "DTEND:$(dt_end)",
        "SUMMARY:$(plan.title)",
        "DESCRIPTION:LTX session — $(host.name) with $(part_names)\\n" *
            "Signal delays: $(delay_desc)\\n" *
            "Mode: $(plan.mode) · Segment plan: $(seg_tpl)\\n" *
            "Generated by InterPlanet (https://interplanet.live)",
        "LTX:1",
        "LTX-PLANID:$(plan_id)",
        "LTX-QUANTUM:PT$(plan.quantum)M",
        "LTX-SEGMENT-TEMPLATE:$(seg_tpl)",
        "LTX-MODE:$(plan.mode)",
    ]

    # LTX-NODE lines for all nodes
    for n in nodes
        push!(lines, "LTX-NODE:ID=$(_to_node_id(n.name));ROLE=$(n.role)")
    end

    # LTX-DELAY lines for participants
    for n in participants
        d = n.delay
        push!(lines, "LTX-DELAY;NODEID=$(_to_node_id(n.name)):ONEWAY-MIN=$(d);ONEWAY-MAX=$(d + 120);ONEWAY-ASSUMED=$(d)")
    end

    push!(lines, "LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY")

    # LTX-LOCALTIME for Mars nodes
    for n in nodes
        if n.location == "mars"
            push!(lines, "LTX-LOCALTIME:NODE=$(_to_node_id(n.name));SCHEME=LMST;PARAMS=LONGITUDE:0E")
        end
    end

    push!(lines, "END:VEVENT")
    push!(lines, "END:VCALENDAR")

    return join(lines, "\r\n")
end

# ── Formatting ─────────────────────────────────────────────────────────────────

"""
    format_hms(sec) -> String

Format seconds as "MM:SS" (when < 1 hour) or "HH:MM:SS".
Negative values are clamped to 0.
"""
function format_hms(sec::Number)::String
    s  = max(0, Int(floor(sec)))
    h  = div(s, 3600)
    m  = div(mod(s, 3600), 60)
    sc = mod(s, 60)
    if h > 0
        return "$(lpad(h, 2, '0')):$(lpad(m, 2, '0')):$(lpad(sc, 2, '0'))"
    else
        return "$(lpad(m, 2, '0')):$(lpad(sc, 2, '0'))"
    end
end

"""
    format_utc(epoch_ms) -> String

Format a UTC epoch milliseconds value as "HH:MM:SS UTC".
"""
function format_utc(epoch_ms::Integer)::String
    rem = mod(div(Int64(epoch_ms), 1000), 86400)
    h   = div(rem, 3600)
    m   = div(mod(rem, 3600), 60)
    sc  = mod(rem, 60)
    return "$(lpad(h, 2, '0')):$(lpad(m, 2, '0')):$(lpad(sc, 2, '0')) UTC"
end

# ── REST API client ─────────────────────────────────────────────────────────────

"""
    store_session(plan; api_base) -> Dict{String,Any}

Store a session plan on the server (best-effort; returns empty Dict on failure).
Requires the Downloads stdlib (Julia 1.6+) at runtime.
"""
function store_session(plan::LtxPlan; api_base::String = DEFAULT_API_BASE)::Dict{String,Any}
    json_body = _plan_to_json(plan)
    url       = api_base * "?action=session"
    try
        resp_body = _http_post_str(url, json_body)
        d = _parse_plan_json(resp_body)
        return d === nothing ? Dict{String,Any}() : d
    catch e
        @warn "store_session failed: $e"
        return Dict{String,Any}()
    end
end

"""
    get_session(plan_id; api_base) -> Union{LtxPlan,Nothing}

Retrieve a stored session plan by plan ID (best-effort).
"""
function get_session(plan_id::AbstractString; api_base::String = DEFAULT_API_BASE)::Union{LtxPlan,Nothing}
    url = api_base * "?action=session&plan_id=" * _url_encode(String(plan_id))
    try
        resp_body = _http_get_str(url)
        d = _parse_plan_json(resp_body)
        d === nothing && return nothing
        plan_d = haskey(d, "plan") && d["plan"] isa Dict{String,Any} ? d["plan"] : d
        return _dict_to_plan(plan_d)
    catch e
        @warn "get_session failed: $e"
        return nothing
    end
end

# ── HTTP helpers ───────────────────────────────────────────────────────────────

"""URL-percent-encode a string."""
function _url_encode(s::AbstractString)::String
    out = IOBuffer()
    for c in String(s)
        if isletter(c) || isdigit(c) || c == '-' || c == '_' || c == '.' || c == '~'
            print(out, c)
        else
            for b in codeunits(string(c))
                print(out, '%', uppercase(string(b; base=16, pad=2)))
            end
        end
    end
    return String(take!(out))
end

"""POST a JSON body to url; return response body as String. Uses Downloads stdlib."""
function _http_post_str(url::String, body::String)::String
    # Downloads is a stdlib since Julia 1.6; load it dynamically to avoid
    # a hard compile-time dependency (unit tests do not need HTTP).
    dl = try
        Base.require(Base.PkgId(Base.UUID("87e2bd06-a317-5318-96d9-3ecbac512b30"), "Downloads"))
    catch
        error("HTTP POST requires the Downloads stdlib (Julia 1.6+)")
    end
    buf = IOBuffer()
    dl.request(url;
        method  = "POST",
        input   = IOBuffer(Vector{UInt8}(codeunits(body))),
        output  = buf,
        headers = ["Content-Type" => "application/json"],
    )
    return String(take!(buf))
end

"""GET url; return response body as String. Uses Downloads stdlib."""
function _http_get_str(url::String)::String
    dl = try
        Base.require(Base.PkgId(Base.UUID("87e2bd06-a317-5318-96d9-3ecbac512b30"), "Downloads"))
    catch
        error("HTTP GET requires the Downloads stdlib (Julia 1.6+)")
    end
    buf = IOBuffer()
    dl.download(url, buf)
    return String(take!(buf))
end

end  # module InterplanetLtx
