"""
runtests.jl — Unit tests for InterplanetLtx.jl

≥80 @test assertions covering: constants, create_plan, compute_segments,
encode_hash, decode_hash, build_node_urls, generate_ics, make_plan_id,
total_min, format_hms, format_utc, and edge cases.
"""

# Load the module directly (no Pkg.test() needed; works with `julia --project=. test/runtests.jl`)
using Test

# Push src/ onto load path and load module
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))
include(joinpath(@__DIR__, "..", "src", "InterplanetLtx.jl"))
using .InterplanetLtx

# ── Fixed test plan ────────────────────────────────────────────────────────────

const TEST_START = "2026-01-01T12:00:00Z"
const TEST_PLAN  = create_plan(
    host_name       = "Earth HQ",
    remote_name     = "Mars Hab-01",
    delay           = 800,
    title           = "Test Session",
    start_iso       = TEST_START,
    quantum         = 3,
    mode            = "LTX",
    host_location   = "earth",
    remote_location = "mars",
)

@testset "InterplanetLtx" begin

# ── Constants ──────────────────────────────────────────────────────────────────
@testset "Constants" begin
    @test PROTOCOL_VERSION == "1.0.0"
    @test DEFAULT_QUANTUM == 3
    @test length(SEG_TYPES) == 6
    @test "TX" in SEG_TYPES
    @test "RX" in SEG_TYPES
    @test "CAUCUS" in SEG_TYPES
    @test "BUFFER" in SEG_TYPES
    @test "MERGE" in SEG_TYPES
    @test "PLAN_CONFIRM" in SEG_TYPES
end

# ── Default segments ───────────────────────────────────────────────────────────
@testset "DEFAULT_SEGMENTS" begin
    @test length(DEFAULT_SEGMENTS) == 7
    @test DEFAULT_SEGMENTS[1].type == "PLAN_CONFIRM"
    @test DEFAULT_SEGMENTS[1].q   == 2
    @test DEFAULT_SEGMENTS[2].type == "TX"
    @test DEFAULT_SEGMENTS[3].type == "RX"
    @test DEFAULT_SEGMENTS[4].type == "CAUCUS"
    @test DEFAULT_SEGMENTS[5].type == "TX"
    @test DEFAULT_SEGMENTS[6].type == "RX"
    @test DEFAULT_SEGMENTS[7].type == "BUFFER"
    @test DEFAULT_SEGMENTS[7].q   == 1
    # All q values are positive
    for s in DEFAULT_SEGMENTS
        @test s.q > 0
    end
end

# ── create_plan ────────────────────────────────────────────────────────────────
@testset "create_plan — basic" begin
    plan = TEST_PLAN
    @test plan.v       == 2
    @test plan.title   == "Test Session"
    @test plan.start   == TEST_START
    @test plan.quantum == 3
    @test plan.mode    == "LTX"
    @test length(plan.nodes) == 2
    @test length(plan.segments) == 7
end

@testset "create_plan — nodes" begin
    plan = TEST_PLAN
    host = plan.nodes[1]
    part = plan.nodes[2]
    @test host.id       == "N0"
    @test host.name     == "Earth HQ"
    @test host.role     == "HOST"
    @test host.delay    == 0
    @test host.location == "earth"
    @test part.id       == "N1"
    @test part.name     == "Mars Hab-01"
    @test part.role     == "PARTICIPANT"
    @test part.delay    == 800
    @test part.location == "mars"
end

@testset "create_plan — defaults" begin
    p = create_plan(host_name="Earth HQ", remote_name="Mars", delay=300, start_iso=TEST_START)
    @test p.quantum == DEFAULT_QUANTUM
    @test p.mode    == "LTX"
    @test p.v       == 2
    @test !isempty(p.title)
    @test !isempty(p.start)
end

@testset "create_plan — custom quantum" begin
    p = create_plan(host_name="A", remote_name="B", delay=0, quantum=5, start_iso=TEST_START)
    @test p.quantum == 5
end

@testset "create_plan — mode" begin
    p = create_plan(host_name="A", remote_name="B", delay=0, mode="LTX-ASYNC", start_iso=TEST_START)
    @test p.mode == "LTX-ASYNC"
end

@testset "create_plan — zero delay" begin
    p = create_plan(host_name="Earth HQ", remote_name="Moon Base", delay=0,
                    remote_location="moon", start_iso=TEST_START)
    @test p.nodes[2].delay    == 0
    @test p.nodes[2].location == "moon"
end

@testset "create_plan — segments are copy" begin
    p1 = create_plan(host_name="A", remote_name="B", delay=0, start_iso=TEST_START)
    p2 = create_plan(host_name="A", remote_name="B", delay=0, start_iso=TEST_START)
    # Mutating one should not affect the other
    @test p1.segments[1].type == p2.segments[1].type
end

# ── total_min ──────────────────────────────────────────────────────────────────
@testset "total_min" begin
    plan = TEST_PLAN
    # Default: 2+2+2+2+2+2+1 = 13 quanta × 3 min = 39 min
    @test total_min(plan) == 39
    # Custom quantum
    p = create_plan(host_name="A", remote_name="B", delay=0, quantum=5, start_iso=TEST_START)
    @test total_min(p) == 13 * 5
    # Single quantum
    p2 = create_plan(host_name="A", remote_name="B", delay=0, quantum=1, start_iso=TEST_START)
    @test total_min(p2) == 13
end

# ── compute_segments ───────────────────────────────────────────────────────────
@testset "compute_segments — count and types" begin
    segs = compute_segments(TEST_PLAN)
    @test length(segs) == 7
    @test segs[1].type == "PLAN_CONFIRM"
    @test segs[2].type == "TX"
    @test segs[3].type == "RX"
    @test segs[4].type == "CAUCUS"
    @test segs[5].type == "TX"
    @test segs[6].type == "RX"
    @test segs[7].type == "BUFFER"
end

@testset "compute_segments — timing" begin
    segs = compute_segments(TEST_PLAN)
    start_ms = InterplanetLtx._parse_iso_ms(TEST_START)
    @test segs[1].start_ms == start_ms
    # Each segment ends where the next begins
    for i in 1:length(segs)-1
        @test segs[i].end_ms == segs[i+1].start_ms
    end
    # Total duration matches total_min
    total_dur_ms = segs[end].end_ms - segs[1].start_ms
    @test total_dur_ms == Int64(total_min(TEST_PLAN)) * Int64(60_000)
end

@testset "compute_segments — dur_min" begin
    segs = compute_segments(TEST_PLAN)
    for (i, seg) in enumerate(segs)
        expected = TEST_PLAN.segments[i].q * TEST_PLAN.quantum
        @test seg.dur_min == expected
        @test seg.end_ms - seg.start_ms == Int64(expected) * Int64(60_000)
    end
end

@testset "compute_segments — start/end are Int64" begin
    segs = compute_segments(TEST_PLAN)
    for seg in segs
        @test isa(seg.start_ms, Int64)
        @test isa(seg.end_ms, Int64)
        @test seg.start_ms > 0
        @test seg.end_ms > seg.start_ms
    end
end

# ── make_plan_id ───────────────────────────────────────────────────────────────
@testset "make_plan_id — format" begin
    id = make_plan_id(TEST_PLAN)
    @test startswith(id, "LTX-")
    @test occursin("-v2-", id)
    # Has 6 dash-separated sections
    parts = split(id, "-")
    @test length(parts) >= 6
end

@testset "make_plan_id — date portion" begin
    id = make_plan_id(TEST_PLAN)
    # start = 2026-01-01, so date = 20260101
    @test occursin("20260101", id)
end

@testset "make_plan_id — host portion" begin
    id = make_plan_id(TEST_PLAN)
    # Earth HQ → EARTHHQ
    @test occursin("EARTHHQ", id)
end

@testset "make_plan_id — deterministic" begin
    id1 = make_plan_id(TEST_PLAN)
    id2 = make_plan_id(TEST_PLAN)
    @test id1 == id2
end

@testset "make_plan_id — different plans differ" begin
    p1 = create_plan(host_name="A", remote_name="B", delay=100, start_iso=TEST_START)
    p2 = create_plan(host_name="A", remote_name="B", delay=200, start_iso=TEST_START)
    @test make_plan_id(p1) != make_plan_id(p2)
end

@testset "make_plan_id — hash is 8 hex chars" begin
    id = make_plan_id(TEST_PLAN)
    parts = split(id, "-")
    hash_part = parts[end]
    @test length(hash_part) == 8
    @test all(c -> c in "0123456789abcdef", hash_part)
end

# ── encode_hash / decode_hash ──────────────────────────────────────────────────
@testset "encode_hash — format" begin
    h = encode_hash(TEST_PLAN)
    @test startswith(h, "#l=")
    @test length(h) > 10
    # No padding chars in the base64 portion
    @test !occursin("=", h[4:end])
    # URL-safe (no + or /)
    @test !occursin("+", h)
    @test !occursin("/", h)
end

@testset "encode_hash — deterministic" begin
    h1 = encode_hash(TEST_PLAN)
    h2 = encode_hash(TEST_PLAN)
    @test h1 == h2
end

@testset "decode_hash — round-trip" begin
    h    = encode_hash(TEST_PLAN)
    plan = decode_hash(h)
    @test plan !== nothing
    @test plan.v       == TEST_PLAN.v
    @test plan.title   == TEST_PLAN.title
    @test plan.start   == TEST_PLAN.start
    @test plan.quantum == TEST_PLAN.quantum
    @test plan.mode    == TEST_PLAN.mode
    @test length(plan.nodes) == length(TEST_PLAN.nodes)
    @test length(plan.segments) == length(TEST_PLAN.segments)
end

@testset "decode_hash — nodes preserved" begin
    h    = encode_hash(TEST_PLAN)
    plan = decode_hash(h)
    @test plan !== nothing
    @test plan.nodes[1].name     == "Earth HQ"
    @test plan.nodes[1].role     == "HOST"
    @test plan.nodes[1].delay    == 0
    @test plan.nodes[2].name     == "Mars Hab-01"
    @test plan.nodes[2].role     == "PARTICIPANT"
    @test plan.nodes[2].delay    == 800
    @test plan.nodes[2].location == "mars"
end

@testset "decode_hash — segments preserved" begin
    h    = encode_hash(TEST_PLAN)
    plan = decode_hash(h)
    @test plan !== nothing
    for i in 1:length(TEST_PLAN.segments)
        @test plan.segments[i].type == TEST_PLAN.segments[i].type
        @test plan.segments[i].q    == TEST_PLAN.segments[i].q
    end
end

@testset "decode_hash — strip # prefix" begin
    h_raw = lstrip(encode_hash(TEST_PLAN), '#')
    plan  = decode_hash(h_raw)
    @test plan !== nothing
    @test plan.title == TEST_PLAN.title
end

@testset "decode_hash — strip l= prefix" begin
    token = lstrip(encode_hash(TEST_PLAN), '#')
    @test startswith(token, "l=")
    plan = decode_hash(token)
    @test plan !== nothing
end

@testset "decode_hash — invalid returns nothing" begin
    @test decode_hash("not-valid-base64!!!")  === nothing
    @test decode_hash("")                      === nothing
    @test decode_hash("#l=AAAA")               === nothing
end

# ── build_node_urls ────────────────────────────────────────────────────────────
@testset "build_node_urls — count" begin
    urls = build_node_urls(TEST_PLAN, "https://interplanet.live/ltx.html")
    @test length(urls) == 2
end

@testset "build_node_urls — structure" begin
    urls = build_node_urls(TEST_PLAN, "https://interplanet.live/ltx.html")
    @test urls[1].node_id == "N0"
    @test urls[1].name    == "Earth HQ"
    @test urls[1].role    == "HOST"
    @test urls[2].node_id == "N1"
    @test urls[2].name    == "Mars Hab-01"
    @test urls[2].role    == "PARTICIPANT"
end

@testset "build_node_urls — URL format" begin
    base = "https://interplanet.live/ltx.html"
    urls = build_node_urls(TEST_PLAN, base)
    for (i, u) in enumerate(urls)
        @test startswith(u.url, base)
        @test occursin("?node=", u.url)
        @test occursin("#l=", u.url)
    end
    @test occursin("node=N0", urls[1].url)
    @test occursin("node=N1", urls[2].url)
end

@testset "build_node_urls — hash in URL matches encode_hash" begin
    urls  = build_node_urls(TEST_PLAN, "https://interplanet.live/ltx.html")
    token = encode_hash(TEST_PLAN)   # "#l=…"
    hash_part = lstrip(token, '#')   # "l=…"
    for u in urls
        @test occursin(hash_part, u.url)
    end
end

@testset "build_node_urls — strips base query/fragment" begin
    urls = build_node_urls(TEST_PLAN, "https://interplanet.live/ltx.html?foo=bar#old")
    for u in urls
        @test startswith(u.url, "https://interplanet.live/ltx.html?node=")
    end
end

# ── generate_ics ───────────────────────────────────────────────────────────────
@testset "generate_ics — structure" begin
    ics = generate_ics(TEST_PLAN)
    @test occursin("BEGIN:VCALENDAR", ics)
    @test occursin("END:VCALENDAR", ics)
    @test occursin("BEGIN:VEVENT", ics)
    @test occursin("END:VEVENT", ics)
    @test occursin("VERSION:2.0", ics)
end

@testset "generate_ics — PRODID" begin
    ics = generate_ics(TEST_PLAN)
    @test occursin("PRODID:", ics)
    @test occursin("InterPlanet", ics)
end

@testset "generate_ics — DTSTART" begin
    ics = generate_ics(TEST_PLAN)
    @test occursin("DTSTART:20260101T120000Z", ics)
end

@testset "generate_ics — SUMMARY" begin
    ics = generate_ics(TEST_PLAN)
    @test occursin("SUMMARY:Test Session", ics)
end

@testset "generate_ics — UID" begin
    ics = generate_ics(TEST_PLAN)
    @test occursin("UID:", ics)
    @test occursin("@interplanet.live", ics)
end

@testset "generate_ics — LTX extensions" begin
    ics = generate_ics(TEST_PLAN)
    @test occursin("LTX:1", ics)
    @test occursin("LTX-PLANID:", ics)
    @test occursin("LTX-QUANTUM:PT3M", ics)
    @test occursin("LTX-SEGMENT-TEMPLATE:", ics)
    @test occursin("LTX-MODE:LTX", ics)
    @test occursin("LTX-NODE:", ics)
    @test occursin("LTX-DELAY;", ics)
    @test occursin("LTX-READINESS:", ics)
end

@testset "generate_ics — mars localtime" begin
    ics = generate_ics(TEST_PLAN)
    # Mars Hab-01 has location="mars" → should have LTX-LOCALTIME
    @test occursin("LTX-LOCALTIME:", ics)
    @test occursin("LMST", ics)
end

@testset "generate_ics — CRLF line endings" begin
    ics = generate_ics(TEST_PLAN)
    @test occursin("\r\n", ics)
end

@testset "generate_ics — DTEND after DTSTART" begin
    ics = generate_ics(TEST_PLAN)
    dtstart_pos = findfirst("DTSTART:", ics)
    dtend_pos   = findfirst("DTEND:", ics)
    @test dtstart_pos !== nothing
    @test dtend_pos   !== nothing
    # DTEND should come after DTSTART in the string
    @test first(dtend_pos) > first(dtstart_pos)
end

# ── format_hms ─────────────────────────────────────────────────────────────────
@testset "format_hms" begin
    @test format_hms(0)    == "00:00"
    @test format_hms(59)   == "00:59"
    @test format_hms(60)   == "01:00"
    @test format_hms(90)   == "01:30"
    @test format_hms(3599) == "59:59"
    @test format_hms(3600) == "01:00:00"
    @test format_hms(3661) == "01:01:01"
    @test format_hms(7200) == "02:00:00"
    @test format_hms(7320) == "02:02:00"
    # Negative clamped to 0
    @test format_hms(-1)   == "00:00"
    @test format_hms(-100) == "00:00"
end

# ── format_utc ─────────────────────────────────────────────────────────────────
@testset "format_utc" begin
    # Unix epoch = 00:00:00 UTC
    @test format_utc(0)        == "00:00:00 UTC"
    # 1 hour = 3600000 ms
    @test format_utc(3_600_000) == "01:00:00 UTC"
    # Noon
    @test format_utc(43_200_000) == "12:00:00 UTC"
    # Ends with " UTC"
    @test endswith(format_utc(12345678), " UTC")
    # 8 chars before " UTC"
    s = format_utc(12345678)
    @test length(s) == 12   # "HH:MM:SS UTC"
end

# ── ISO parsing ────────────────────────────────────────────────────────────────
@testset "_parse_iso_ms" begin
    # 1970-01-01T00:00:00Z = 0 ms
    @test InterplanetLtx._parse_iso_ms("1970-01-01T00:00:00Z") == 0
    # 1 second
    @test InterplanetLtx._parse_iso_ms("1970-01-01T00:00:01Z") == 1000
    # 1 hour
    @test InterplanetLtx._parse_iso_ms("1970-01-01T01:00:00Z") == 3_600_000
    # 2026-01-01T12:00:00Z (known value)
    ms_2026 = InterplanetLtx._parse_iso_ms("2026-01-01T12:00:00Z")
    @test ms_2026 > 0
    # Should match: 2026 is 56 years after 1970
    @test ms_2026 > Int64(1_000_000_000_000)
end

@testset "_ms_to_iso round-trip" begin
    for ms in [Int64(0), Int64(1_000_000_000_000), Int64(1_700_000_000_000)]
        iso = InterplanetLtx._ms_to_iso(ms)
        @test endswith(iso, "Z")
        @test length(iso) == 20
        back = InterplanetLtx._parse_iso_ms(iso)
        @test back == ms
    end
end

# ── Base64 helpers ─────────────────────────────────────────────────────────────
@testset "_b64enc / _b64dec" begin
    for s in ["hello", "LTX SDK test", "{\"v\":2}", ""]
        encoded = InterplanetLtx._b64enc(s)
        # No padding
        @test !occursin("=", encoded)
        # URL-safe
        @test !occursin("+", encoded)
        @test !occursin("/", encoded)
        # Round-trip
        decoded = InterplanetLtx._b64dec(encoded)
        @test decoded == s
    end
end

@testset "_b64dec — invalid input" begin
    @test InterplanetLtx._b64dec("!!!") === nothing
end

# ── JSON serialization ─────────────────────────────────────────────────────────
@testset "_plan_to_json — key order" begin
    json = InterplanetLtx._plan_to_json(TEST_PLAN)
    # Keys should appear in order: v, title, start, quantum, mode, nodes, segments
    v_pos       = findfirst("\"v\"", json)
    title_pos   = findfirst("\"title\"", json)
    start_pos   = findfirst("\"start\"", json)
    quantum_pos = findfirst("\"quantum\"", json)
    mode_pos    = findfirst("\"mode\"", json)
    nodes_pos   = findfirst("\"nodes\"", json)
    segs_pos    = findfirst("\"segments\"", json)
    @test first(v_pos)       < first(title_pos)
    @test first(title_pos)   < first(start_pos)
    @test first(start_pos)   < first(quantum_pos)
    @test first(quantum_pos) < first(mode_pos)
    @test first(mode_pos)    < first(nodes_pos)
    @test first(nodes_pos)   < first(segs_pos)
end

@testset "_plan_to_json — parseable" begin
    json = InterplanetLtx._plan_to_json(TEST_PLAN)
    d = InterplanetLtx._parse_plan_json(json)
    @test d !== nothing
    @test d["title"] == "Test Session"
    @test d["quantum"] == 3
    @test d["mode"] == "LTX"
end

# ── Full encode → decode → re-encode consistency ────────────────────────────────
@testset "encode→decode→encode consistency" begin
    h1   = encode_hash(TEST_PLAN)
    p2   = decode_hash(h1)
    @test p2 !== nothing
    h2   = encode_hash(p2)
    @test h1 == h2
end

@testset "planId consistent with encode/decode" begin
    id1 = make_plan_id(TEST_PLAN)
    h   = encode_hash(TEST_PLAN)
    p2  = decode_hash(h)
    @test p2 !== nothing
    id2 = make_plan_id(p2)
    @test id1 == id2
end

end  # @testset "InterplanetLtx"
