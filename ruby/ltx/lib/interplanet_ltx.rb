# frozen_string_literal: true

# interplanet_ltx.rb — LTX (Light-Time eXchange) Ruby library
# Story 33.5 — Ruby 2.6+ · No external dependencies
#
# Pure port of ltx-sdk.js (js/ltx-sdk.js).
#
# Usage:
#   require 'interplanet_ltx'
#   plan = InterplanetLtx.create_plan(title: 'Q3 Review', start: '2026-03-15T14:00:00Z', delay_sec: 860)
#   hash = InterplanetLtx.encode_hash(plan)

require 'base64'
require 'json'
require 'net/http'
require 'time'
require 'uri'

require_relative 'interplanet_ltx/constants'
require_relative 'interplanet_ltx/models'

module InterplanetLtx

  # ── Plan creation ────────────────────────────────────────────────────────

  # Create a plan with default Earth HQ → Mars Hab-01 nodes and segments.
  #
  # @param title     [String, nil]  Session title (nil → "LTX Session")
  # @param start     [String]       ISO-8601 UTC start time
  # @param delay_sec [Integer]      One-way light-travel delay in seconds
  # @return [LtxPlan]
  def self.create_plan(title: nil, start: '', delay_sec: 0)
    LtxPlan.new(
      v:        2,
      title:    title || 'LTX Session',
      start:    start,
      quantum:  DEFAULT_QUANTUM,
      mode:     'LTX',
      nodes:    [
        LtxNode.new(id: 'N0', name: 'Earth HQ',    role: 'HOST',        delay: 0,         location: 'earth'),
        LtxNode.new(id: 'N1', name: 'Mars Hab-01', role: 'PARTICIPANT', delay: delay_sec, location: 'mars'),
      ],
      segments: DEFAULT_SEGMENTS.map { |s| LtxSegmentTemplate.new(type: s[:type], q: s[:q]) },
    )
  end

  # Merge a partial config hash into a full LtxPlan with defaults filled in.
  #
  # @param config [Hash]  Partial or full plan configuration
  # @return [LtxPlan]
  def self.upgrade_config(config)
    plan = create_plan(
      title:     config[:title]    || config['title'],
      start:     config[:start]    || config['start']    || '',
      delay_sec: 0,
    )
    plan.quantum = (config[:quantum] || config['quantum'] || DEFAULT_QUANTUM).to_i
    plan.mode    = config[:mode]    || config['mode']    || 'LTX'

    raw_nodes = config[:nodes] || config['nodes']
    if raw_nodes.is_a?(Array)
      plan.nodes = raw_nodes.map do |n|
        n = n.transform_keys(&:to_sym) if n.keys.first.is_a?(String) rescue n
        LtxNode.new(
          id:       (n[:id]       || 'N0').to_s,
          name:     (n[:name]     || 'Unknown').to_s,
          role:     (n[:role]     || 'HOST').to_s,
          delay:    (n[:delay]    || 0).to_i,
          location: (n[:location] || 'earth').to_s,
        )
      end
    end

    raw_segs = config[:segments] || config['segments']
    if raw_segs.is_a?(Array)
      plan.segments = raw_segs.map do |s|
        s = s.transform_keys(&:to_sym) if s.keys.first.is_a?(String) rescue s
        LtxSegmentTemplate.new(type: (s[:type] || 'TX').to_s, q: (s[:q] || 2).to_i)
      end
    end

    plan
  end

  # ── Segment computation ──────────────────────────────────────────────────

  # Compute the timed segment array for a plan.
  #
  # @param plan [LtxPlan]
  # @return [Array<LtxSegment>]
  def self.compute_segments(plan)
    q_ms = plan.quantum * 60 * 1000
    t    = _parse_iso_ms(plan.start)
    plan.segments.map do |tmpl|
      dur = tmpl.q * q_ms
      seg = LtxSegment.new(
        type:     tmpl.type,
        q:        tmpl.q,
        start_ms: t,
        end_ms:   t + dur,
        dur_min:  tmpl.q * plan.quantum,
      )
      t += dur
      seg
    end
  end

  # Total session duration in minutes.
  #
  # @param plan [LtxPlan]
  # @return [Integer]
  def self.total_min(plan)
    plan.segments.sum { |s| s.q * plan.quantum }
  end

  # ── Plan ID ──────────────────────────────────────────────────────────────

  # Compute the deterministic plan ID string.
  # Format: "LTX-YYYYMMDD-HOST-NODE-v2-XXXXXXXX"
  #
  # @param plan [LtxPlan]
  # @return [String]
  def self.make_plan_id(plan)
    start_ms = _parse_iso_ms(plan.start)
    date     = Time.at(start_ms / 1000.0).utc.strftime('%Y%m%d')

    # Host string: remove spaces, uppercase, max 8 chars
    host_str = 'HOST'
    unless plan.nodes.empty?
      host_str = plan.nodes[0].name.gsub(/\s+/, '').upcase[0, 8]
    end

    # Node string: first 4 non-space chars of each remote node name
    node_str = 'RX'
    if plan.nodes.size > 1
      parts = plan.nodes[1..].map do |n|
        n.name.gsub(/\s+/, '').upcase[0, 4]
      end
      node_str = parts.join('-')
    end

    # Polynomial hash matching Math.imul(31, h) in ltx-sdk.js
    h = _plan_hash_hex(plan)

    "LTX-#{date}-#{host_str}-#{node_str}-v2-#{h}"
  end

  # ── Encoding ─────────────────────────────────────────────────────────────

  # Encode a plan to a URL-safe base64 hash fragment ("#l=…").
  #
  # @param plan [LtxPlan]
  # @return [String]  e.g. "#l=eyJ2IjoyL..."
  def self.encode_hash(plan)
    payload = _b64url_encode(_plan_to_json(plan))
    "#l=#{payload}"
  end

  # Decode a plan from a URL hash fragment ("#l=…", "l=…", or raw base64).
  #
  # @param hash [String]
  # @return [LtxPlan, nil]  nil on failure
  def self.decode_hash(hash)
    return nil unless hash

    token = hash.sub(/\A#/, '').sub(/\Al=/, '')
    json_str = _b64url_decode(token)
    return nil unless json_str

    data = JSON.parse(json_str, symbolize_names: true)
    return nil unless data.is_a?(Hash)

    nodes = (data[:nodes] || []).map do |n|
      LtxNode.new(
        id:       (n[:id]       || '').to_s,
        name:     (n[:name]     || '').to_s,
        role:     (n[:role]     || 'HOST').to_s,
        delay:    (n[:delay]    || 0).to_i,
        location: (n[:location] || 'earth').to_s,
      )
    end

    segments = (data[:segments] || []).map do |s|
      LtxSegmentTemplate.new(type: (s[:type] || 'TX').to_s, q: (s[:q] || 2).to_i)
    end

    return nil if segments.empty?

    LtxPlan.new(
      v:        (data[:v]       || 2).to_i,
      title:    (data[:title]   || 'LTX Session').to_s,
      start:    (data[:start]   || '').to_s,
      quantum:  (data[:quantum] || DEFAULT_QUANTUM).to_i,
      mode:     (data[:mode]    || 'LTX').to_s,
      nodes:    nodes,
      segments: segments,
    )
  rescue
    nil
  end

  # ── Node URLs ────────────────────────────────────────────────────────────

  # Build perspective URLs for all nodes in a plan.
  #
  # @param plan     [LtxPlan]
  # @param base_url [String]  Base page URL (e.g. "https://interplanet.live/ltx.html")
  # @return [Array<LtxNodeUrl>]
  def self.build_node_urls(plan, base_url)
    hash      = encode_hash(plan)
    hash_part = hash.delete_prefix('#')
    base      = base_url.gsub(/[?#].*\z/, '')

    plan.nodes.map do |node|
      LtxNodeUrl.new(
        node_id: node.id,
        name:    node.name,
        role:    node.role,
        url:     "#{base}?node=#{node.id}##{hash_part}",
      )
    end
  end

  # ── ICS generation ───────────────────────────────────────────────────────

  # Generate LTX-extended iCalendar (.ics) content for a plan.
  #
  # @param plan [LtxPlan]
  # @return [String]  iCalendar content with CRLF line endings
  def self.generate_ics(plan)
    segs     = compute_segments(plan)
    start_ms = _parse_iso_ms(plan.start)
    end_ms   = segs.last ? segs.last.end_ms : start_ms
    plan_id  = make_plan_id(plan)

    fmt      = ->(ms) { Time.at(ms / 1000.0).utc.strftime('%Y%m%dT%H%M%SZ') }
    dt_start = fmt.call(start_ms)
    dt_end   = fmt.call(end_ms)
    dt_stamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')

    seg_tpl   = plan.segments.map(&:type).join(',')
    host_name = plan.nodes.first&.name || 'Earth HQ'

    part_names = plan.nodes[1..]&.map(&:name)&.join(', ') || 'remote nodes'
    delay_desc = plan.nodes[1..]&.map { |n|
      "#{n.name}: #{n.delay / 60} min one-way"
    }&.join(' . ') || 'no participant delay configured'

    to_nid = ->(n) { n.name.upcase.gsub(/[\s\t]+/, '-') }

    lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//InterPlanet//LTX v1.1//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'BEGIN:VEVENT',
      "UID:#{plan_id}@interplanet.live",
      "DTSTAMP:#{dt_stamp}",
      "DTSTART:#{dt_start}",
      "DTEND:#{dt_end}",
      "SUMMARY:#{plan.title}",
      "DESCRIPTION:LTX session -- #{host_name} with #{part_names}\\nSignal delays: #{delay_desc}\\nMode: #{plan.mode} . Segment plan: #{seg_tpl}\\nGenerated by InterPlanet (https://interplanet.live)",
      'LTX:1',
      "LTX-PLANID:#{plan_id}",
      "LTX-QUANTUM:PT#{plan.quantum}M",
      "LTX-SEGMENT-TEMPLATE:#{seg_tpl}",
      "LTX-MODE:#{plan.mode}",
    ]

    plan.nodes.each { |n| lines << "LTX-NODE:ID=#{to_nid.(n)};ROLE=#{n.role}" }

    plan.nodes[1..].each do |n|
      d = n.delay
      lines << "LTX-DELAY;NODEID=#{to_nid.(n)}:ONEWAY-MIN=#{d};ONEWAY-MAX=#{d + 120};ONEWAY-ASSUMED=#{d}"
    end

    lines << 'LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY'

    plan.nodes.select { |n| n.location == 'mars' }.each do |n|
      lines << "LTX-LOCALTIME:NODE=#{to_nid.(n)};SCHEME=LMST;PARAMS=LONGITUDE:0E"
    end

    lines << 'END:VEVENT'
    lines << 'END:VCALENDAR'

    lines.join("\r\n") + "\r\n"
  end

  # ── Formatting ───────────────────────────────────────────────────────────

  # Format a duration in seconds as "MM:SS" (< 1 hour) or "HH:MM:SS".
  #
  # @param seconds [Integer]  Negative values clamped to 0
  # @return [String]
  def self.format_hms(seconds)
    seconds = 0 if seconds < 0
    h = seconds / 3600
    m = (seconds % 3600) / 60
    s = seconds % 60
    h > 0 ? format('%02d:%02d:%02d', h, m, s) : format('%02d:%02d', m, s)
  end

  # Format UTC epoch milliseconds as "HH:MM:SS UTC".
  #
  # @param epoch_ms [Integer]  Epoch milliseconds
  # @return [String]
  def self.format_utc(epoch_ms)
    t = Time.at(epoch_ms / 1000.0).utc
    format('%02d:%02d:%02d UTC', t.hour, t.min, t.sec)
  end

  # ── REST client ──────────────────────────────────────────────────────────

  # POST the plan to the LTX session store.
  #
  # @return [Hash]  Decoded JSON response (empty hash on error)
  def self.store_session(plan, api_base: nil)
    url  = "#{(api_base || DEFAULT_API_BASE).chomp('/')}/session"
    body = JSON.generate({ plan: JSON.parse(_plan_to_json(plan)) })
    _http_post(url, body) || {}
  rescue
    {}
  end

  # GET a session plan by plan ID.
  #
  # @return [LtxPlan, nil]
  def self.get_session(plan_id, api_base: nil)
    url  = "#{(api_base || DEFAULT_API_BASE).chomp('/')}/session/#{URI.encode_www_form_component(plan_id)}"
    json = _http_get(url)
    return nil unless json
    data = JSON.parse(json, symbolize_names: true)
    plan_data = data[:plan] || data
    decode_hash(encode_hash(LtxPlan.new(**plan_data))) rescue nil
  rescue
    nil
  end

  # Download ICS for a session by plan ID and optional node ID.
  #
  # @return [String]  ICS content (empty on error)
  def self.download_ics(plan_id, node_id: nil, api_base: nil)
    base = (api_base || DEFAULT_API_BASE).chomp('/')
    url  = "#{base}/ics/#{URI.encode_www_form_component(plan_id)}"
    url += "?node=#{URI.encode_www_form_component(node_id)}" if node_id
    _http_get(url) || ''
  rescue
    ''
  end

  # Submit feedback for a session.
  #
  # @param payload [Hash]  Feedback payload
  # @return [Hash]  Decoded JSON response (empty hash on error)
  def self.submit_feedback(plan_id, payload, api_base: nil)
    url  = "#{(api_base || DEFAULT_API_BASE).chomp('/')}/feedback/#{URI.encode_www_form_component(plan_id)}"
    _http_post(url, JSON.generate(payload)) || {}
  rescue
    {}
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  # Parse an ISO-8601 UTC string to epoch milliseconds.
  def self._parse_iso_ms(iso)
    return 0 if iso.nil? || iso.empty?
    (Time.parse(iso).utc.to_r * 1000).to_i
  rescue
    0
  end
  private_class_method :_parse_iso_ms

  # Serialise a plan to compact JSON (matches JS JSON.stringify key order).
  def self._plan_to_json(plan)
    {
      v:        plan.v,
      title:    plan.title,
      start:    plan.start,
      quantum:  plan.quantum,
      mode:     plan.mode,
      nodes:    plan.nodes.map { |n| { id: n.id, name: n.name, role: n.role, delay: n.delay, location: n.location } },
      segments: plan.segments.map { |s| { type: s.type, q: s.q } },
    }.to_json
  end
  private_class_method :_plan_to_json

  # Compute the polynomial hash hex string (matches ltx-sdk.js makePlanId).
  def self._plan_hash_hex(plan)
    h = 0
    _plan_to_json(plan).each_byte { |b| h = (h * 31 + b) & 0xFFFFFFFF }
    format('%08x', h)
  end
  private_class_method :_plan_hash_hex

  # URL-safe base64 encode (no padding, `-` and `_` substitutions).
  def self._b64url_encode(str)
    Base64.strict_encode64(str).tr('+/', '-_').delete('=')
  end
  private_class_method :_b64url_encode

  # URL-safe base64 decode. Returns nil on error.
  def self._b64url_decode(str)
    padded  = str.tr('-_', '+/')
    padded += '=' * ((4 - padded.length % 4) % 4)
    Base64.strict_decode64(padded)
  rescue
    nil
  end
  private_class_method :_b64url_decode

  # POST JSON body; returns parsed Hash or nil on error.
  def self._http_post(url, body)
    uri = URI(url)
    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    req.body = body
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                          open_timeout: 10, read_timeout: 10) { |h| h.request(req) }
    JSON.parse(res.body, symbolize_names: false)
  rescue
    nil
  end
  private_class_method :_http_post

  # GET URL; returns body string or nil on error.
  def self._http_get(url)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                    open_timeout: 10, read_timeout: 10) do |h|
      h.get(uri.request_uri).body
    end
  rescue
    nil
  end
  private_class_method :_http_get
end
