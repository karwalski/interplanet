defmodule InterplanetLtx do
  @moduledoc """
  LTX (Light-Time eXchange) Elixir library — Story 49.1.
  Pure Elixir port of ltx-sdk.js with no external dependencies.

  Usage:
    plan = InterplanetLtx.create_plan(title: "My Session", start: "2024-01-15T14:00:00Z")
    hash = InterplanetLtx.encode_hash(plan)
    segs = InterplanetLtx.compute_segments(plan)
  """

  import Bitwise

  alias InterplanetLtx.Constants
  alias InterplanetLtx.Models.LtxNode
  alias InterplanetLtx.Models.LtxSegmentTemplate
  alias InterplanetLtx.Models.LtxSegment
  alias InterplanetLtx.Models.LtxNodeUrl
  alias InterplanetLtx.Models.LtxPlan

  # ── Plan creation ──────────────────────────────────────────────────────────

  @doc """
  Create a new LTX session plan.

  Options:
    - title: Session title (default: "LTX Session")
    - start: ISO 8601 UTC start time (default: 5 min from now)
    - quantum: Minutes per quantum (default: 3)
    - mode: Protocol mode (default: "LTX")
    - nodes: Explicit node list (overrides host_name/remote_name)
    - host_name: Host node name (default: "Earth HQ")
    - host_location: Host location key (default: "earth")
    - remote_name: Participant node name (default: "Mars Hab-01")
    - remote_location: Participant location key (default: "mars")
    - delay: One-way signal delay in seconds (default: 0)
    - segments: Segment template list
  """
  def create_plan(opts \\ []) do
    nodes = Keyword.get(opts, :nodes) || [
      %LtxNode{
        id: "N0",
        name: Keyword.get(opts, :host_name, "Earth HQ"),
        role: "HOST",
        delay: 0,
        location: Keyword.get(opts, :host_location, "earth")
      },
      %LtxNode{
        id: "N1",
        name: Keyword.get(opts, :remote_name, "Mars Hab-01"),
        role: "PARTICIPANT",
        delay: Keyword.get(opts, :delay, 0),
        location: Keyword.get(opts, :remote_location, "mars")
      }
    ]

    raw_segs = Keyword.get(opts, :segments, Constants.default_segments())
    segments = Enum.map(raw_segs, &coerce_segment_template/1)

    start_str = case Keyword.get(opts, :start) do
      nil ->
        now_ms = :os.system_time(:millisecond)
        plus5_ms = now_ms + 5 * 60 * 1000
        # Round down to minute boundary
        rounded_ms = div(plus5_ms, 60_000) * 60_000
        ms_to_iso(rounded_ms)
      s -> s
    end

    %LtxPlan{
      v: 2,
      title: Keyword.get(opts, :title, "LTX Session"),
      start: start_str,
      quantum: Keyword.get(opts, :quantum, Constants.default_quantum()),
      mode: Keyword.get(opts, :mode, "LTX"),
      segments: segments,
      nodes: nodes
    }
  end

  @doc """
  Upgrade a v1 config map (txName/rxName/delay) to v2 schema (nodes[]).
  v2 configs with nodes are returned as LtxPlan.
  """
  def upgrade_config(%LtxPlan{} = plan), do: plan

  def upgrade_config(cfg) when is_map(cfg) do
    v = cfg[:v] || cfg["v"] || 1
    nodes_raw = cfg[:nodes] || cfg["nodes"]

    if v >= 2 and is_list(nodes_raw) and length(nodes_raw) > 0 do
      nodes = Enum.map(nodes_raw, &coerce_node/1)
      segs_raw = cfg[:segments] || cfg["segments"] || Constants.default_segments()
      segments = Enum.map(segs_raw, &coerce_segment_template/1)
      %LtxPlan{
        v: 2,
        title: to_string(cfg[:title] || cfg["title"] || "LTX Session"),
        start: to_string(cfg[:start] || cfg["start"] || ""),
        quantum: cfg[:quantum] || cfg["quantum"] || Constants.default_quantum(),
        mode: to_string(cfg[:mode] || cfg["mode"] || "LTX"),
        nodes: nodes,
        segments: segments
      }
    else
      # v1 — upgrade from txName/rxName
      rx_name = to_string(cfg[:rxName] || cfg["rxName"] || cfg[:rx_name] || cfg["rx_name"] || "Mars Hab-01")
      remote_loc = cond do
        String.contains?(String.downcase(rx_name), "mars") -> "mars"
        String.contains?(String.downcase(rx_name), "moon") -> "moon"
        true -> "earth"
      end
      delay_val = cfg[:delay] || cfg["delay"] || 0
      segs_raw = cfg[:segments] || cfg["segments"] || Constants.default_segments()
      segments = Enum.map(segs_raw, &coerce_segment_template/1)
      tx_name = to_string(cfg[:txName] || cfg["txName"] || cfg[:tx_name] || cfg["tx_name"] || "Earth HQ")
      %LtxPlan{
        v: 2,
        title: to_string(cfg[:title] || cfg["title"] || "LTX Session"),
        start: to_string(cfg[:start] || cfg["start"] || ""),
        quantum: cfg[:quantum] || cfg["quantum"] || Constants.default_quantum(),
        mode: to_string(cfg[:mode] || cfg["mode"] || "LTX"),
        nodes: [
          %LtxNode{id: "N0", name: tx_name, role: "HOST", delay: 0, location: "earth"},
          %LtxNode{id: "N1", name: rx_name, role: "PARTICIPANT", delay: delay_val, location: remote_loc}
        ],
        segments: segments
      }
    end
  end

  # ── Story 26.3: ICS text escaping ─────────────────────────────────────────

  @doc """
  Escape a string for RFC 5545 TEXT property values.
  Escapes backslash → \\\\, semicolon → \\;, comma → \\,, newline → \\n
  """
  def escape_ics_text(s) when is_binary(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\n", "\\n")
  end

  # ── Story 26.4: Protocol hardening ────────────────────────────────────────

  @doc """
  Compute the plan-lock timeout in milliseconds.
  timeout = delay_seconds * DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000
  """
  def plan_lock_timeout_ms(delay_seconds) do
    round(delay_seconds * Constants.default_plan_lock_timeout_factor() * 1000)
  end

  @doc """
  Check if the measured delay violates the declared delay threshold.
  Returns "ok", "violation", or "degraded".
  """
  def check_delay_violation(declared_delay_s, measured_delay_s) do
    diff = abs(measured_delay_s - declared_delay_s)
    cond do
      diff > Constants.delay_violation_degraded_s() -> "degraded"
      diff > Constants.delay_violation_warn_s() -> "violation"
      true -> "ok"
    end
  end

  # ── Segment computation ───────────────────────────────────────────────────

  @doc """
  Compute the timed segment array for a plan.
  Returns a list of LtxSegment structs.
  Returns {:error, reason} if quantum < 1.
  """
  def compute_segments(%LtxPlan{quantum: q}) when q < 1 do
    {:error, "quantum must be >= 1, got #{q}"}
  end

  def compute_segments(%LtxPlan{} = plan) do
    q_ms = plan.quantum * 60 * 1000
    t0 = parse_iso_ms(plan.start)
    {segs, _} = Enum.map_reduce(plan.segments, t0, fn tmpl, t ->
      dur_ms = tmpl.q * q_ms
      seg = %LtxSegment{
        type: tmpl.type,
        q: tmpl.q,
        start: t,
        end: t + dur_ms,
        dur_min: tmpl.q * plan.quantum,
        start_ms: t,
        end_ms: t + dur_ms
      }
      {seg, t + dur_ms}
    end)
    segs
  end

  def compute_segments(cfg) when is_map(cfg), do: compute_segments(upgrade_config(cfg))

  @doc """
  Total session duration in minutes.
  """
  def total_min(%LtxPlan{} = plan) do
    Enum.reduce(plan.segments, 0, fn s, acc -> acc + s.q * plan.quantum end)
  end

  def total_min(cfg) when is_map(cfg), do: total_min(upgrade_config(cfg))

  # ── Plan ID ───────────────────────────────────────────────────────────────

  @doc """
  Compute the deterministic plan ID string.
  Format: "LTX-YYYYMMDD-HOST-NODE-v2-XXXXXXXX"
  Matches ltx-sdk.js makePlanId exactly.
  """
  def make_plan_id(%LtxPlan{} = plan) do
    start_ms = parse_iso_ms(plan.start)
    date = ms_to_date_str(start_ms)

    host_str = case plan.nodes do
      [] -> "HOST"
      [first | _] ->
        first.name
        |> String.replace(~r/\s+/, "")
        |> String.upcase()
        |> String.slice(0, 8)
    end

    node_str = case plan.nodes do
      nodes when length(nodes) <= 1 -> "RX"
      [_ | rest] ->
        rest
        |> Enum.map(fn n ->
          n.name
          |> String.replace(~r/\s+/, "")
          |> String.upcase()
          |> String.slice(0, 4)
        end)
        |> Enum.join("-")
        |> String.slice(0, 16)
    end

    h = plan_hash_hex(plan)
    "LTX-#{date}-#{host_str}-#{node_str}-v2-#{h}"
  end

  def make_plan_id(cfg) when is_map(cfg), do: make_plan_id(upgrade_config(cfg))

  # ── URL hash encoding ─────────────────────────────────────────────────────

  @doc """
  Encode a plan to a URL-safe base64 hash fragment ("#l=...").
  """
  def encode_hash(%LtxPlan{} = plan) do
    "#l=" <> b64enc(plan_to_json(plan))
  end

  def encode_hash(cfg) when is_map(cfg), do: encode_hash(upgrade_config(cfg))

  @doc """
  Decode a plan from a URL hash fragment ("#l=...", "l=...", or raw base64).
  Returns LtxPlan or nil.
  """
  def decode_hash(nil), do: nil
  def decode_hash(hash) do
    token =
      hash
      |> String.replace(~r/^#/, "")
      |> String.replace(~r/^l=/, "")
    json = b64dec(token)
    if is_nil(json), do: nil, else: parse_plan_json(json)
  end

  # ── Node URLs ─────────────────────────────────────────────────────────────

  @doc """
  Build perspective URLs for all nodes in a plan.
  """
  def build_node_urls(%LtxPlan{} = plan, base_url) do
    hash_frag = "#l=" <> b64enc(plan_to_json(plan))
    base = base_url |> String.replace(~r/[?#].*$/, "")
    Enum.map(plan.nodes, fn node ->
      %LtxNodeUrl{
        node_id: node.id,
        name: node.name,
        role: node.role,
        url: "#{base}?node=#{URI.encode_www_form(node.id)}#{hash_frag}"
      }
    end)
  end

  def build_node_urls(cfg, base_url) when is_map(cfg) do
    build_node_urls(upgrade_config(cfg), base_url)
  end

  # ── ICS generation ────────────────────────────────────────────────────────

  @doc """
  Generate LTX-extended iCalendar (.ics) content for a plan.
  Uses CRLF line endings as per RFC 5545.
  """
  def generate_ics(%LtxPlan{} = plan) do
    segs = case compute_segments(plan) do
      {:error, _} -> []
      list when is_list(list) -> list
    end
    start_ms = parse_iso_ms(plan.start)
    end_ms = if segs != [], do: List.last(segs).end_ms, else: start_ms
    plan_id = make_plan_id(plan)

    dt_start = ms_to_ics_dt(start_ms)
    dt_end = ms_to_ics_dt(end_ms)
    dt_stamp = ms_to_ics_dt(:os.system_time(:millisecond))

    seg_tpl = plan.segments |> Enum.map(& &1.type) |> Enum.join(",")
    host_name = case plan.nodes do
      [h | _] -> h.name
      [] -> "Earth HQ"
    end

    participants = Enum.drop(plan.nodes, 1)
    part_names = if participants != [] do
      Enum.map_join(participants, ", ", & &1.name)
    else
      "remote nodes"
    end

    delay_desc = if participants != [] do
      Enum.map_join(participants, " · ", fn n ->
        "#{n.name}: #{div(n.delay, 60)} min one-way"
      end)
    else
      "no participant delay configured"
    end

    to_nid = fn n -> n.name |> String.upcase() |> String.replace(~r/\s+/, "-") end

    node_lines = Enum.map(plan.nodes, fn n ->
      "LTX-NODE:ID=#{to_nid.(n)};ROLE=#{n.role}"
    end)

    delay_lines = Enum.map(participants, fn n ->
      d = n.delay
      "LTX-DELAY;NODEID=#{to_nid.(n)}:ONEWAY-MIN=#{d};ONEWAY-MAX=#{d + 120};ONEWAY-ASSUMED=#{d}"
    end)

    local_time_lines =
      plan.nodes
      |> Enum.filter(fn n -> n.location == "mars" end)
      |> Enum.map(fn n ->
        "LTX-LOCALTIME:NODE=#{to_nid.(n)};SCHEME=LMST;PARAMS=LONGITUDE:0E"
      end)

    lines =
      [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//InterPlanet//LTX v1.1//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "BEGIN:VEVENT",
        "UID:#{plan_id}@interplanet.live",
        "DTSTAMP:#{dt_stamp}",
        "DTSTART:#{dt_start}",
        "DTEND:#{dt_end}",
        "SUMMARY:#{escape_ics_text(plan.title)}",
        "DESCRIPTION:LTX session \u2014 #{escape_ics_text(host_name)} with #{escape_ics_text(part_names)}\\n" <>
          "Signal delays: #{delay_desc}\\n" <>
          "Mode: #{plan.mode} \u00B7 Segment plan: #{seg_tpl}\\n" <>
          "Generated by InterPlanet (https://interplanet.live)",
        "LTX:1",
        "LTX-PLANID:#{plan_id}",
        "LTX-QUANTUM:PT#{plan.quantum}M",
        "LTX-SEGMENT-TEMPLATE:#{seg_tpl}",
        "LTX-MODE:#{plan.mode}"
      ] ++
      node_lines ++
      delay_lines ++
      ["LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY"] ++
      local_time_lines ++
      ["END:VEVENT", "END:VCALENDAR"]

    Enum.join(lines, "\r\n")
  end

  def generate_ics(cfg) when is_map(cfg), do: generate_ics(upgrade_config(cfg))

  # ── Formatting ────────────────────────────────────────────────────────────

  @doc """
  Format a duration in seconds as "MM:SS" (< 1 hour) or "HH:MM:SS".
  Negative values are clamped to 0.
  """
  def format_hms(seconds) when is_number(seconds) do
    sec = max(0, trunc(seconds))
    h = div(sec, 3600)
    m = div(rem(sec, 3600), 60)
    s = rem(sec, 60)
    if h > 0 do
      "#{pad2(h)}:#{pad2(m)}:#{pad2(s)}"
    else
      "#{pad2(m)}:#{pad2(s)}"
    end
  end

  @doc """
  Format UTC epoch milliseconds as "HH:MM:SS UTC".
  """
  def format_utc(epoch_ms) when is_integer(epoch_ms) do
    {hh, mm, ss} = ms_to_hms_tuple(epoch_ms)
    "#{pad2(hh)}:#{pad2(mm)}:#{pad2(ss)} UTC"
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  # Coerce a raw map or struct to LtxNode
  defp coerce_node(n) when is_struct(n, LtxNode), do: n
  defp coerce_node(n) when is_map(n) do
    %LtxNode{
      id: to_string(n[:id] || n["id"] || "N0"),
      name: to_string(n[:name] || n["name"] || "Unknown"),
      role: to_string(n[:role] || n["role"] || "HOST"),
      delay: n[:delay] || n["delay"] || 0,
      location: to_string(n[:location] || n["location"] || "earth")
    }
  end

  # Coerce a raw map or struct to LtxSegmentTemplate
  defp coerce_segment_template(s) when is_struct(s, LtxSegmentTemplate), do: s
  defp coerce_segment_template(s) when is_map(s) do
    %LtxSegmentTemplate{
      type: to_string(s[:type] || s["type"] || "TX"),
      q: s[:q] || s["q"] || 2
    }
  end

  # Parse ISO 8601 UTC string to epoch milliseconds
  defp parse_iso_ms(nil), do: 0
  defp parse_iso_ms(""), do: 0
  defp parse_iso_ms(iso_str) when is_binary(iso_str) do
    case DateTime.from_iso8601(iso_str) do
      {:ok, dt, _} -> DateTime.to_unix(dt, :millisecond)
      _ -> 0
    end
  end

  # Epoch ms to "YYYYMMDD" date string (UTC)
  defp ms_to_date_str(ms) do
    secs = div(ms, 1000)
    {{y, mo, d}, _} = :calendar.gregorian_seconds_to_datetime(secs + 62_167_219_200)
    "#{y}#{pad2(mo)}#{pad2(d)}"
  end

  # Epoch ms to ISO string "YYYY-MM-DDThh:mm:ssZ"
  defp ms_to_iso(ms) do
    secs = div(ms, 1000)
    {{y, mo, d}, {h, mi, s}} = :calendar.gregorian_seconds_to_datetime(secs + 62_167_219_200)
    "#{y}-#{pad2(mo)}-#{pad2(d)}T#{pad2(h)}:#{pad2(mi)}:#{pad2(s)}Z"
  end

  # Epoch ms to ICS datetime string "YYYYMMDDTHHMMSSz"
  defp ms_to_ics_dt(ms) do
    secs = div(ms, 1000)
    {{y, mo, d}, {h, mi, s}} = :calendar.gregorian_seconds_to_datetime(secs + 62_167_219_200)
    "#{y}#{pad2(mo)}#{pad2(d)}T#{pad2(h)}#{pad2(mi)}#{pad2(s)}Z"
  end

  # Epoch ms to {h, m, s} tuple (UTC)
  defp ms_to_hms_tuple(ms) do
    secs = div(ms, 1000)
    {_, {h, m, s}} = :calendar.gregorian_seconds_to_datetime(secs + 62_167_219_200)
    {h, m, s}
  end

  # Zero-pad integer to 2 digits
  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  # URL-safe base64 encode (no padding)
  defp b64enc(str) do
    str
    |> Base.encode64()
    |> String.replace("+", "-")
    |> String.replace("/", "_")
    |> String.trim_trailing("=")
  end

  # URL-safe base64 decode; returns nil on error
  defp b64dec(str) do
    pad = rem(4 - rem(String.length(str), 4), 4)
    padded = str <> String.duplicate("=", pad)
    standard = padded |> String.replace("-", "+") |> String.replace("_", "/")
    case Base.decode64(standard) do
      {:ok, decoded} -> decoded
      :error -> nil
    end
  end

  # Escape a value for inline JSON string
  defp json_str(s), do: ~s("#{String.replace(to_string(s), "\"", "\\\"")}")

  # Serialize plan to compact JSON — EXACT key order: v, title, start, quantum, mode, nodes, segments
  # (nodes before segments — matches canonical conformance vector key order)
  defp plan_to_json(%LtxPlan{} = plan) do
    nodes_json =
      plan.nodes
      |> Enum.map(fn n ->
        ~s({"id":#{json_str(n.id)},"name":#{json_str(n.name)},"role":#{json_str(n.role)},"delay":#{n.delay},"location":#{json_str(n.location)}})
      end)
      |> Enum.join(",")

    segs_json =
      plan.segments
      |> Enum.map(fn s ->
        ~s({"type":#{json_str(s.type)},"q":#{s.q}})
      end)
      |> Enum.join(",")

    ~s({"v":#{plan.v},"title":#{json_str(plan.title)},"start":#{json_str(plan.start)},"quantum":#{plan.quantum},"mode":#{json_str(plan.mode)},"nodes":[#{nodes_json}],"segments":[#{segs_json}]})
  end

  # Polynomial hash matching Math.imul(31, h) >>> 0 in ltx-sdk.js
  defp djb_hash(str) do
    str
    |> String.to_charlist()
    |> Enum.reduce(0, fn c, h ->
      band(h * 31 + c, 0xFFFFFFFF)
    end)
  end

  # Compute 8-char lowercase hex hash for plan ID
  defp plan_hash_hex(%LtxPlan{} = plan) do
    h = djb_hash(plan_to_json(plan))
    h |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(8, "0")
  end

  # Parse a plan from decoded JSON string using Erlang :json (OTP 27+) or fallback
  defp parse_plan_json(json_str) do
    data = try_json_decode(json_str)
    if is_map(data), do: build_plan_from_map(data), else: nil
  end

  # Try multiple JSON decode approaches
  defp try_json_decode(json_str) do
    # OTP 27+ has :json module
    try do
      :json.decode(json_str)
    rescue
      _ ->
        # Fallback: try manual parse
        try do
          parse_json_value(String.trim(json_str))
        rescue
          _ -> nil
        end
    catch
      _, _ ->
        try do
          parse_json_value(String.trim(json_str))
        rescue
          _ -> nil
        end
    end
  end

  # Minimal recursive descent JSON parser (no external deps)
  defp parse_json_value("{" <> rest) do
    {map, _} = parse_json_object(String.trim(rest), %{})
    map
  end
  defp parse_json_value("[" <> rest) do
    {arr, _} = parse_json_array(String.trim(rest), [])
    arr
  end
  defp parse_json_value("\"" <> rest) do
    {str, _} = scan_string(rest, [])
    str
  end
  defp parse_json_value("true" <> _), do: true
  defp parse_json_value("false" <> _), do: false
  defp parse_json_value("null" <> _), do: nil
  defp parse_json_value(str) do
    {num_str, _} = scan_number(str, [])
    case Integer.parse(num_str) do
      {i, ""} -> i
      _ ->
        case Float.parse(num_str) do
          {f, _} -> f
          :error -> nil
        end
    end
  end

  defp parse_json_object("}" <> rest, acc), do: {acc, rest}
  defp parse_json_object(str, acc) do
    str = String.trim_leading(str, ",") |> String.trim()
    if String.starts_with?(str, "}") do
      {"}" <> rest} = {str}
      {acc, rest}
    else
      "\"" <> rest = str
      {key, after_key} = scan_string(rest, [])
      after_key = String.trim(after_key) |> String.trim_leading(":") |> String.trim()
      {val, after_val} = scan_value_with_rest(after_key)
      after_val = String.trim(after_val) |> String.trim_leading(",") |> String.trim()
      parse_json_object(after_val, Map.put(acc, key, val))
    end
  end

  defp parse_json_array("]" <> rest, acc), do: {Enum.reverse(acc), rest}
  defp parse_json_array(str, acc) do
    str = String.trim_leading(str, ",") |> String.trim()
    if String.starts_with?(str, "]") do
      "]" <> rest = str
      {Enum.reverse(acc), rest}
    else
      {val, rest} = scan_value_with_rest(str)
      rest = String.trim(rest) |> String.trim_leading(",") |> String.trim()
      parse_json_array(rest, [val | acc])
    end
  end

  defp scan_value_with_rest("{" <> rest) do
    {map, after_map} = parse_json_object(String.trim(rest), %{})
    {map, after_map}
  end
  defp scan_value_with_rest("[" <> rest) do
    {arr, after_arr} = parse_json_array(String.trim(rest), [])
    {arr, after_arr}
  end
  defp scan_value_with_rest("\"" <> rest) do
    scan_string(rest, [])
  end
  defp scan_value_with_rest("true" <> rest), do: {true, rest}
  defp scan_value_with_rest("false" <> rest), do: {false, rest}
  defp scan_value_with_rest("null" <> rest), do: {nil, rest}
  defp scan_value_with_rest(str) do
    {num_chars, rest} = scan_number(str, [])
    val = case Integer.parse(num_chars) do
      {i, ""} -> i
      _ ->
        case Float.parse(num_chars) do
          {f, _} -> f
          :error -> nil
        end
    end
    {val, rest}
  end

  defp scan_string("", acc), do: {IO.chardata_to_string(Enum.reverse(acc)), ""}
  defp scan_string("\"" <> rest, acc), do: {IO.chardata_to_string(Enum.reverse(acc)), rest}
  defp scan_string("\\" <> rest, acc) do
    case rest do
      "\"" <> r -> scan_string(r, ["\"" | acc])
      "\\" <> r -> scan_string(r, ["\\" | acc])
      "/" <> r -> scan_string(r, ["/" | acc])
      "b" <> r -> scan_string(r, ["\b" | acc])
      "f" <> r -> scan_string(r, ["\f" | acc])
      "n" <> r -> scan_string(r, ["\n" | acc])
      "r" <> r -> scan_string(r, ["\r" | acc])
      "t" <> r -> scan_string(r, ["\t" | acc])
      "u" <> <<a, b, c, d, r::binary>> ->
        code = String.to_integer(<<a, b, c, d>>, 16)
        scan_string(r, [<<code::utf8>> | acc])
      _ -> scan_string(rest, ["\\" | acc])
    end
  end
  defp scan_string(<<c::utf8, rest::binary>>, acc) do
    scan_string(rest, [<<c::utf8>> | acc])
  end

  defp scan_number("", acc), do: {IO.chardata_to_string(Enum.reverse(acc)), ""}
  defp scan_number(<<c::utf8, rest::binary>>, acc) when c in ?0..?9 or c == ?- or c == ?. or c == ?e or c == ?E or c == ?+ do
    scan_number(rest, [<<c::utf8>> | acc])
  end
  defp scan_number(rest, acc), do: {IO.chardata_to_string(Enum.reverse(acc)), rest}

  # Build LtxPlan from a decoded JSON map (string keys)
  defp build_plan_from_map(data) when is_map(data) do
    nodes_raw = data["nodes"] || []
    segs_raw = data["segments"] || []

    nodes = Enum.map(nodes_raw, fn n ->
      %LtxNode{
        id: to_string(n["id"] || "N0"),
        name: to_string(n["name"] || "Unknown"),
        role: to_string(n["role"] || "HOST"),
        delay: n["delay"] || 0,
        location: to_string(n["location"] || "earth")
      }
    end)

    segments = Enum.map(segs_raw, fn s ->
      %LtxSegmentTemplate{
        type: to_string(s["type"] || "TX"),
        q: s["q"] || 2
      }
    end)

    if segments == [], do: nil, else:
    %LtxPlan{
      v: data["v"] || 2,
      title: to_string(data["title"] || "LTX Session"),
      start: to_string(data["start"] || ""),
      quantum: data["quantum"] || Constants.default_quantum(),
      mode: to_string(data["mode"] || "LTX"),
      nodes: nodes,
      segments: segments
    }
  end
  defp build_plan_from_map(_), do: nil
end
