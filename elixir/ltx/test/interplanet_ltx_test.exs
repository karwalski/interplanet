# test/interplanet_ltx_test.exs
# Standalone test script for the InterplanetLtx Elixir library.
# Run with: elixir test/interplanet_ltx_test.exs

# Load the library files
Code.require_file("../lib/interplanet_ltx/constants.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/models.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/interplanet_ltx.ex", __DIR__)

import InterplanetLtx
import Test

alias InterplanetLtx.Models.LtxNode
alias InterplanetLtx.Models.LtxSegmentTemplate
alias InterplanetLtx.Models.LtxPlan

# ── Constants ──────────────────────────────────────────────────────────────────

check InterplanetLtx.Constants.version() == "1.0.0",   "VERSION is 1.0.0"
check InterplanetLtx.Constants.default_quantum() == 3, "DEFAULT_QUANTUM is 3"
check InterplanetLtx.Constants.default_api_base() == "https://interplanet.live/api/ltx.php", "DEFAULT_API_BASE correct"
check length(InterplanetLtx.Constants.default_segments()) == 7, "DEFAULT_SEGMENTS has 7 entries"
check hd(InterplanetLtx.Constants.default_segments())[:type] == "PLAN_CONFIRM", "first default segment is PLAN_CONFIRM"
check List.last(InterplanetLtx.Constants.default_segments())[:type] == "BUFFER", "last default segment is BUFFER"
check List.last(InterplanetLtx.Constants.default_segments())[:q] == 1, "BUFFER q=1"

# ── create_plan — basic ────────────────────────────────────────────────────────

plan = create_plan(title: "LTX Session", start: "2024-01-15T14:00:00Z")
check plan.v == 2,                              "create_plan v=2"
check plan.title == "LTX Session",              "create_plan title"
check plan.start == "2024-01-15T14:00:00Z",     "create_plan start"
check plan.quantum == 3,                        "create_plan quantum default 3"
check plan.mode == "LTX",                       "create_plan mode LTX"
check length(plan.nodes) == 2,                  "create_plan 2 nodes"
check length(plan.segments) == 7,              "create_plan 7 segments"

# ── create_plan — nodes ────────────────────────────────────────────────────────

host = hd(plan.nodes)
remote = Enum.at(plan.nodes, 1)
check host.id == "N0",              "host node id N0"
check host.name == "Earth HQ",      "host node name Earth HQ"
check host.role == "HOST",          "host node role HOST"
check host.delay == 0,              "host node delay 0"
check host.location == "earth",     "host node location earth"
check remote.id == "N1",            "remote node id N1"
check remote.name == "Mars Hab-01", "remote node name Mars Hab-01"
check remote.role == "PARTICIPANT", "remote node role PARTICIPANT"
check remote.delay == 0,            "remote node delay 0 (default)"
check remote.location == "mars",    "remote node location mars"

# ── create_plan — custom options ───────────────────────────────────────────────

plan2 = create_plan(title: "Mars Mission", start: "2024-06-01T10:00:00Z",
                    host_name: "Houston", remote_name: "Olympus Base",
                    delay: 800, remote_location: "mars", quantum: 5, mode: "ASYNC")
check plan2.quantum == 5,                   "create_plan custom quantum"
check plan2.mode == "ASYNC",                "create_plan custom mode"
check hd(plan2.nodes).name == "Houston",    "create_plan custom host_name"
check Enum.at(plan2.nodes, 1).name == "Olympus Base", "create_plan custom remote_name"
check Enum.at(plan2.nodes, 1).delay == 800, "create_plan custom delay"

# ── create_plan — default start is non-empty string ───────────────────────────

plan_now = create_plan()
check is_binary(plan_now.start) and byte_size(plan_now.start) > 0, "create_plan default start is non-empty"
check String.ends_with?(plan_now.start, "Z"), "create_plan default start ends with Z"

# ── compute_segments ──────────────────────────────────────────────────────────

segs = compute_segments(plan)
check length(segs) == 7,               "compute_segments 7 segs"
check hd(segs).type == "PLAN_CONFIRM", "first seg type PLAN_CONFIRM"
check hd(segs).q == 2,                 "first seg q=2"
check hd(segs).dur_min == 6,           "first seg dur_min 6"
check Enum.at(segs, 1).type == "TX",   "second seg type TX"
check Enum.at(segs, 2).type == "RX",   "third seg type RX"
check Enum.at(segs, 3).type == "CAUCUS", "fourth seg type CAUCUS"
check List.last(segs).type == "BUFFER", "last seg type BUFFER"
check List.last(segs).q == 1,          "last seg q=1"
check List.last(segs).dur_min == 3,    "last seg dur_min 3"

# Verify start_ms and end_ms match the ISO start
start_epoch_ms = 1_705_327_200_000  # 2024-01-15T14:00:00Z
check hd(segs).start_ms == start_epoch_ms, "first seg start_ms matches plan start"
check hd(segs).end_ms == start_epoch_ms + 2 * 3 * 60 * 1000, "first seg end_ms = start + 6 min"
check Enum.at(segs, 1).start_ms == hd(segs).end_ms, "segs are contiguous"

# ── total_min ─────────────────────────────────────────────────────────────────

check total_min(plan) == 39,  "total_min default plan = 39"
check total_min(plan2) == 65, "total_min quantum=5 plan = 65"

# ── make_plan_id ──────────────────────────────────────────────────────────────

# Golden value: LTX-20240115-EARTHHQ-MARS-v2-cc8a7fc0 (nodes-before-segments canonical order)
pid = make_plan_id(plan)
check pid == "LTX-20240115-EARTHHQ-MARS-v2-cc8a7fc0", "make_plan_id golden value"
check String.starts_with?(pid, "LTX-"), "plan_id starts with LTX-"
check String.contains?(pid, "-v2-"),    "plan_id contains -v2-"
check String.length(pid) > 20,          "plan_id length > 20"

# Second plan golden value
pid2 = make_plan_id(plan2)
check String.starts_with?(pid2, "LTX-20240601-"), "plan2 id has correct date"
check String.contains?(pid2, "HOUSTON"), "plan2 id contains HOUSTON"
check String.contains?(pid2, "-v2-"),    "plan2 id contains -v2-"

# ── encode_hash / decode_hash ─────────────────────────────────────────────────

hash = encode_hash(plan)
check String.starts_with?(hash, "#l="), "encode_hash starts with #l="
check byte_size(hash) > 10,             "encode_hash non-empty payload"

# The golden base64 from JS:
golden_b64 = "eyJ2IjoyLCJ0aXRsZSI6IkxUWCBTZXNzaW9uIiwic3RhcnQiOiIyMDI0LTAxLTE1VDE0OjAwOjAwWiIsInF1YW50dW0iOjMsIm1vZGUiOiJMVFgiLCJub2RlcyI6W3siaWQiOiJOMCIsIm5hbWUiOiJFYXJ0aCBIUSIsInJvbGUiOiJIT1NUIiwiZGVsYXkiOjAsImxvY2F0aW9uIjoiZWFydGgifSx7ImlkIjoiTjEiLCJuYW1lIjoiTWFycyBIYWItMDEiLCJyb2xlIjoiUEFSVElDSVBBTlQiLCJkZWxheSI6MCwibG9jYXRpb24iOiJtYXJzIn1dLCJzZWdtZW50cyI6W3sidHlwZSI6IlBMQU5fQ09ORklSTSIsInEiOjJ9LHsidHlwZSI6IlRYIiwicSI6Mn0seyJ0eXBlIjoiUlgiLCJxIjoyfSx7InR5cGUiOiJDQVVDVVMiLCJxIjoyfSx7InR5cGUiOiJUWCIsInEiOjJ9LHsidHlwZSI6IlJYIiwicSI6Mn0seyJ0eXBlIjoiQlVGRkVSIiwicSI6MX1dfQ"
check hash == "#l=#{golden_b64}", "encode_hash matches JS golden base64"

# decode_hash round trip
decoded = decode_hash(hash)
check decoded != nil,                           "decode_hash returns non-nil"
check decoded.v == 2,                           "decoded plan v=2"
check decoded.title == "LTX Session",           "decoded plan title"
check decoded.start == "2024-01-15T14:00:00Z",  "decoded plan start"
check decoded.quantum == 3,                     "decoded plan quantum"
check decoded.mode == "LTX",                    "decoded plan mode"
check length(decoded.nodes) == 2,               "decoded plan 2 nodes"
check length(decoded.segments) == 7,            "decoded plan 7 segments"
check hd(decoded.nodes).id == "N0",             "decoded first node id N0"
check hd(decoded.nodes).name == "Earth HQ",     "decoded first node name"
check hd(decoded.nodes).role == "HOST",         "decoded first node role HOST"
check hd(decoded.segments).type == "PLAN_CONFIRM", "decoded first seg PLAN_CONFIRM"

# decode_hash accepts raw token (no "#l=" prefix)
decoded_raw = decode_hash(golden_b64)
check decoded_raw != nil, "decode_hash accepts raw b64 token"
check decoded_raw.title == "LTX Session", "decoded raw token title"

# decode_hash returns nil for invalid input
check decode_hash("notvalidbase64!!") == nil, "decode_hash nil on invalid"
check decode_hash(nil) == nil,                "decode_hash nil on nil"

# ── build_node_urls ───────────────────────────────────────────────────────────

urls = build_node_urls(plan, "https://interplanet.live/ltx.html")
check length(urls) == 2,                                                          "build_node_urls 2 urls"
check hd(urls).node_id == "N0",                                                   "first url nodeId N0"
check hd(urls).role == "HOST",                                                    "first url role HOST"
check hd(urls).name == "Earth HQ",                                                "first url name"
check String.contains?(hd(urls).url, "?node=N0"),                                 "first url has ?node=N0"
check String.contains?(hd(urls).url, "#l="),                                      "first url has hash"
check String.contains?(Enum.at(urls, 1).url, "?node=N1"),                         "second url has ?node=N1"
check String.starts_with?(hd(urls).url, "https://interplanet.live/ltx.html"),     "url starts with base"
check Enum.at(urls, 1).role == "PARTICIPANT",                                      "second url role PARTICIPANT"

# ── upgrade_config ────────────────────────────────────────────────────────────

v1_cfg = %{
  "v" => 1,
  "txName" => "Earth HQ",
  "rxName" => "Mars Hab-01",
  "delay" => 500,
  "start" => "2024-01-15T14:00:00Z",
  "quantum" => 3,
  "mode" => "LTX",
  "segments" => InterplanetLtx.Constants.default_segments()
}
upgraded = upgrade_config(v1_cfg)
check upgraded.v == 2,                                  "upgrade_config v1->v2"
check length(upgraded.nodes) == 2,                      "upgrade_config 2 nodes"
check hd(upgraded.nodes).name == "Earth HQ",            "upgrade_config host name"
check Enum.at(upgraded.nodes, 1).delay == 500,          "upgrade_config remote delay"
check Enum.at(upgraded.nodes, 1).location == "mars",    "upgrade_config mars location"
check Enum.at(upgraded.nodes, 1).role == "PARTICIPANT", "upgrade_config remote role"

# upgrade_config v2 passthrough
check upgrade_config(plan).v == 2,                 "upgrade_config v2 plan passthrough"
check upgrade_config(plan).title == "LTX Session", "upgrade_config v2 preserves title"

# ── generate_ics ──────────────────────────────────────────────────────────────

ics = generate_ics(plan)
check String.contains?(ics, "BEGIN:VCALENDAR"),   "ics has BEGIN:VCALENDAR"
check String.contains?(ics, "END:VCALENDAR"),     "ics has END:VCALENDAR"
check String.contains?(ics, "BEGIN:VEVENT"),      "ics has BEGIN:VEVENT"
check String.contains?(ics, "END:VEVENT"),        "ics has END:VEVENT"
check String.contains?(ics, "DTSTART:20240115T140000Z"), "ics has correct DTSTART"
check String.contains?(ics, "SUMMARY:LTX Session"), "ics has SUMMARY"
check String.contains?(ics, "LTX-PLANID:"),       "ics has LTX-PLANID"
check String.contains?(ics, "LTX-QUANTUM:PT3M"),  "ics has LTX-QUANTUM"
check String.contains?(ics, "LTX-NODE:"),         "ics has LTX-NODE"
check String.contains?(ics, "LTX-DELAY;"),        "ics has LTX-DELAY"
check String.contains?(ics, "LTX-READINESS:"),    "ics has LTX-READINESS"
check String.contains?(ics, "LTX-LOCALTIME:"),    "ics has LTX-LOCALTIME (mars node)"
check String.contains?(ics, "\r\n"),              "ics uses CRLF line endings"
check String.contains?(ics, "VERSION:2.0"),        "ics has VERSION:2.0"
check String.contains?(ics, "PRODID:-//InterPlanet//LTX v1.1//EN"), "ics has PRODID"
check String.contains?(ics, "@interplanet.live"), "ics UID has interplanet.live"
check String.contains?(ics, "PLAN_CONFIRM,TX,RX,CAUCUS,TX,RX,BUFFER"), "ics has segment template"

# ── format_hms ────────────────────────────────────────────────────────────────

check format_hms(0) == "00:00",       "format_hms 0 -> 00:00"
check format_hms(65) == "01:05",      "format_hms 65 -> 01:05"
check format_hms(3600) == "01:00:00", "format_hms 3600 -> 01:00:00"
check format_hms(3661) == "01:01:01", "format_hms 3661 -> 01:01:01"
check format_hms(-5) == "00:00",      "format_hms negative -> 00:00"
check format_hms(59) == "00:59",      "format_hms 59 -> 00:59"
check format_hms(600) == "10:00",     "format_hms 600 -> 10:00"
check format_hms(7200) == "02:00:00", "format_hms 7200 -> 02:00:00"
check format_hms(86399) == "23:59:59", "format_hms 86399 -> 23:59:59"

# ── format_utc ────────────────────────────────────────────────────────────────

check format_utc(0) == "00:00:00 UTC",           "format_utc 0 -> 00:00:00 UTC"
check format_utc(1_705_323_600_000) == "13:00:00 UTC", "format_utc 1705323600000 -> 13:00:00 UTC"
check String.ends_with?(format_utc(1_705_327_200_000), "UTC"), "format_utc ends with UTC"
check format_utc(1_705_327_200_000) == "14:00:00 UTC", "format_utc 2024-01-15T14:00:00Z"

# ── Plan ID hash determinism ───────────────────────────────────────────────────

plan_a = create_plan(title: "LTX Session", start: "2024-01-15T14:00:00Z")
plan_b = create_plan(title: "LTX Session", start: "2024-01-15T14:00:00Z")
check make_plan_id(plan_a) == make_plan_id(plan_b), "plan_id is deterministic"

# Different title => different hash
plan_c = create_plan(title: "Other Session", start: "2024-01-15T14:00:00Z")
check make_plan_id(plan_a) != make_plan_id(plan_c), "different title => different plan_id"

# ── encode/decode round trip with plan2 ───────────────────────────────────────

hash2 = encode_hash(plan2)
decoded2 = decode_hash(hash2)
check decoded2 != nil,                                "plan2 encode->decode non-nil"
check decoded2.title == "Mars Mission",               "plan2 round-trip title"
check Enum.at(decoded2.nodes, 1).delay == 800,        "plan2 round-trip delay"
check decoded2.quantum == 5,                          "plan2 round-trip quantum"

# ── escape_ics_text (Story 26.3) ──────────────────────────────────────────────

check escape_ics_text("") == "",               "escape_ics_text empty"
check escape_ics_text("hello") == "hello",    "escape_ics_text no specials"
check escape_ics_text("a;b") == "a\\;b",      "escape_ics_text semicolon"
check escape_ics_text("a,b") == "a\\,b",      "escape_ics_text comma"
check escape_ics_text("a\\b") == "a\\\\b",    "escape_ics_text backslash"
check escape_ics_text("a\nb") == "a\\nb",     "escape_ics_text newline"

ics_escaped = generate_ics(create_plan(title: "Hello, World; Test", start: "2024-01-15T14:00:00Z"))
check String.contains?(ics_escaped, "SUMMARY:Hello\\, World\\; Test"), "generateIcs SUMMARY escaped"

# ── session_states / DEGRADED (Story 26.4) ────────────────────────────────────

check length(InterplanetLtx.Constants.session_states()) == 5, "session_states has 5 entries"
check Enum.member?(InterplanetLtx.Constants.session_states(), "DEGRADED"), "session_states contains DEGRADED"
check Enum.at(InterplanetLtx.Constants.session_states(), 0) == "INIT", "session_states[0] is INIT"
check Enum.at(InterplanetLtx.Constants.session_states(), 3) == "DEGRADED", "session_states[3] is DEGRADED"
check Enum.at(InterplanetLtx.Constants.session_states(), 4) == "COMPLETE", "session_states[4] is COMPLETE"

# ── plan_lock_timeout_ms (Story 26.4) ─────────────────────────────────────────

check InterplanetLtx.Constants.default_plan_lock_timeout_factor() == 2, "default_plan_lock_timeout_factor is 2"
check plan_lock_timeout_ms(100) == 200000,  "plan_lock_timeout_ms(100) == 200000"
check plan_lock_timeout_ms(0) == 0,         "plan_lock_timeout_ms(0) == 0"
check plan_lock_timeout_ms(60) == 120000,   "plan_lock_timeout_ms(60) == 120000"

# ── check_delay_violation (Story 26.4) ────────────────────────────────────────

check InterplanetLtx.Constants.delay_violation_warn_s() == 120,      "delay_violation_warn_s is 120"
check InterplanetLtx.Constants.delay_violation_degraded_s() == 300,  "delay_violation_degraded_s is 300"
check check_delay_violation(100, 100) == "ok",          "check_delay_violation ok (same)"
check check_delay_violation(100, 210) == "ok",          "check_delay_violation ok within 120"
check check_delay_violation(100, 221) == "violation",   "check_delay_violation violation"
check check_delay_violation(100, 401) == "degraded",    "check_delay_violation degraded"
check check_delay_violation(0, 120) == "ok",            "check_delay_violation boundary 120 ok"
check check_delay_violation(0, 301) == "degraded",      "check_delay_violation boundary 301 degraded"

# ── compute_segments quantum guard (Story 26.4) ───────────────────────────────

bad_plan = %{plan | quantum: 0}
check compute_segments(bad_plan) == {:error, "quantum must be >= 1, got 0"}, "compute_segments quantum=0 error"

bad_plan2 = %{plan | quantum: -1}
check match?({:error, _}, compute_segments(bad_plan2)), "compute_segments quantum=-1 error"

# ── Summary ───────────────────────────────────────────────────────────────────

passed = Process.get(:passed, 0)
failed = Process.get(:failed, 0)
IO.puts("\n#{passed} passed  #{failed} failed")
if failed > 0, do: System.halt(1)
