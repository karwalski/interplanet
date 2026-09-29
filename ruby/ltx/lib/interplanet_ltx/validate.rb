# frozen_string_literal: true

# validate.rb — Plan validation
# LTX-SPECIFICATION.md §4 (wire format, spec/ltx-schema.json), §3.5 (reserved
# streams) and §7 (reserved branching). Mirrors validatePlan() in
# javascript/ltx/ltx-sdk.js and typescript/ltx/src/validate.ts.

require 'time'

module InterplanetLtx
  SEG_TYPES = %w[PLAN_CONFIRM TX RX CAUCUS BUFFER MERGE].freeze
  # Every segment type the reference SDKs handle (core §3.4 + auxiliary).
  PLAN_SEGMENT_TYPES = (SEG_TYPES + %w[SPEAK REST PAD OPEN RELAY]).freeze
  PLAN_MODES = %w[LTX LTX-LIVE LTX-RELAY LTX-ASYNC].freeze
  # Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3).
  V3_ONLY_FIELDS = %w[delays planVersion prevPlanHash questions actions streams].freeze
  # Reserved branching identifiers (§7): MUST be absent from plans and segments.
  RESERVED_BRANCH_PLAN_FIELDS = %w[branches branching].freeze
  RESERVED_BRANCH_SEGMENT_FIELDS = %w[branch].freeze
  # Reserved streams identifiers (§3.5): plan streams[] empty, no segment stream.
  RESERVED_STREAM_SEGMENT_FIELDS = %w[stream].freeze

  # Validate a v2 or v3 plan Hash (as parsed from JSON; string or symbol keys)
  # against the wire format and the reserved-field rules (§3.5 streams,
  # §7 branching). v1 configs must be upgraded first. Pure; never raises.
  #
  # Error codes: not_an_object, invalid_version, missing_field, invalid_field,
  # invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
  # duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
  # invalid_delays, reserved_streams, reserved_branching.
  #
  # @param plan [Hash]
  # @return [Hash] { valid: Boolean, errors: Array<Hash{code:, path:, message:}> }
  def self.validate_plan(plan)
    errors = []
    err = ->(code, path, message) { errors << { code: code, path: path, message: message } }
    unless plan.is_a?(Hash)
      err.call('not_an_object', '', 'plan must be an object')
      return { valid: false, errors: errors }
    end
    plan = _deep_string_keys(plan)
    version = plan['v']
    version = nil unless _num?(version) && [2, 3].include?(version)
    err.call('invalid_version', 'v', 'v must be 2 or 3') if version.nil?
    %w[title start quantum mode nodes segments].each do |f|
      err.call('missing_field', f, "#{f} is required") unless plan.key?(f)
    end
    if plan.key?('title') && !plan['title'].is_a?(String)
      err.call('invalid_field', 'title', 'title must be a string')
    end
    if plan.key?('start') && !_valid_start?(plan['start'])
      err.call('invalid_field', 'start', 'start must be an ISO 8601 UTC timestamp')
    end
    q = plan['quantum']
    if plan.key?('quantum') && !(_integer?(q) && q >= 1 && q <= 60)
      err.call('invalid_quantum', 'quantum', 'quantum must be an integer 1..60 minutes (§3.2)')
    end
    if plan.key?('mode') && !PLAN_MODES.include?(plan['mode'])
      err.call('invalid_mode', 'mode', "mode must be one of #{PLAN_MODES.join(', ')}")
    end

    ids = {}
    if plan.key?('nodes')
      nodes = plan['nodes']
      if !nodes.is_a?(Array) || nodes.empty?
        err.call('invalid_nodes', 'nodes', 'nodes must be a non-empty array')
      else
        hosts = 0
        nodes.each_with_index do |n, i|
          unless n.is_a?(Hash) && n['id'].is_a?(String) && !n['id'].empty? && !n['id'].include?('|') &&
                 n['name'].is_a?(String) && %w[HOST PARTICIPANT OBSERVER].include?(n['role']) &&
                 _num?(n['delay']) && n['delay'] >= 0
            err.call('invalid_nodes', "nodes[#{i}]",
                     'node needs id (no "|"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0')
            next
          end
          err.call('duplicate_node_id', "nodes[#{i}].id", "duplicate node id #{n['id']}") if ids.key?(n['id'])
          ids[n['id']] = true
          hosts += 1 if n['role'] == 'HOST'
        end
        h = nodes[0]
        unless hosts == 1 && h.is_a?(Hash) && h['role'] == 'HOST' && _num?(h['delay']) && h['delay'].zero?
          err.call('invalid_host', 'nodes[0]', 'exactly one HOST, first in nodes[], with delay 0 (§3.1)')
        end
      end
    end

    if plan.key?('segments')
      segments = plan['segments']
      if !segments.is_a?(Array)
        err.call('invalid_segment', 'segments', 'segments must be an array')
      else
        segments.each_with_index do |s, i|
          unless s.is_a?(Hash) && PLAN_SEGMENT_TYPES.include?(s['type']) && _integer?(s['q']) && s['q'] >= 1
            err.call('invalid_segment', "segments[#{i}]", 'segment needs a known type and integer q >= 1')
            next
          end
          if s.key?('speaker') && !ids.key?(s['speaker'])
            sp = s['speaker'].nil? ? 'null' : s['speaker']
            err.call('unknown_speaker', "segments[#{i}].speaker", "speaker #{sp} is not a node id")
          end
        end
      end
    end

    if version == 2
      V3_ONLY_FIELDS.each do |f|
        err.call('v3_field_in_v2', f, "#{f} is a v3 field and MUST NOT appear in a v2 plan (§4.3)") if plan.key?(f)
      end
    elsif version == 3
      if plan.key?('delays')
        d = plan['delays']
        if !d.is_a?(Hash)
          err.call('invalid_delays', 'delays', 'delays must be an object')
        else
          d.each do |k, val|
            parts = k.to_s.split('|', -1)
            next if parts.length == 2 && (parts[0] <=> parts[1]) == -1 &&
                    (ids.empty? || (ids.key?(parts[0]) && ids.key?(parts[1]))) &&
                    _num?(val) && val >= 0

            err.call('invalid_delays', "delays.#{k}",
                     'key must be two known node ids joined by "|" in sorted order; value >= 0 (§3.7.2)')
          end
        end
      end
      pv = plan['planVersion']
      if plan.key?('planVersion') && !(_integer?(pv) && pv >= 1)
        err.call('invalid_field', 'planVersion', 'planVersion must be an integer >= 1')
      end
      ph = plan['prevPlanHash']
      if plan.key?('prevPlanHash') && !(ph.is_a?(String) && ph.match?(/\A[0-9a-f]{64}\z/))
        err.call('invalid_field', 'prevPlanHash', 'prevPlanHash must be 64 lowercase hex characters')
      end
      %w[questions actions].each do |f|
        err.call('invalid_field', f, "#{f} must be an array") if plan.key?(f) && !plan[f].is_a?(Array)
      end
    end

    errors.concat(_reserved_field_errors(plan))
    { valid: errors.empty?, errors: errors }
  end

  # Reserved-field violations only (§3.5 streams, §7 branching).
  def self._reserved_field_errors(plan)
    errors = []
    return errors unless plan.is_a?(Hash)

    if plan.key?('streams') && !(plan['streams'].is_a?(Array) && plan['streams'].empty?)
      errors << { code: 'reserved_streams', path: 'streams',
                  message: 'streams[] is reserved (§3.5) and MUST be absent or empty' }
    end
    RESERVED_BRANCH_PLAN_FIELDS.each do |f|
      next unless plan.key?(f)

      errors << { code: 'reserved_branching', path: f,
                  message: "#{f} is reserved for branching (§7, not yet implemented) and MUST be absent" }
    end
    segments = plan['segments'].is_a?(Array) ? plan['segments'] : []
    segments.each_with_index do |s, i|
      next unless s.is_a?(Hash)

      RESERVED_STREAM_SEGMENT_FIELDS.each do |f|
        next unless s.key?(f)

        errors << { code: 'reserved_streams', path: "segments[#{i}].#{f}",
                    message: "segment #{f} is reserved (§3.5) and MUST be absent" }
      end
      RESERVED_BRANCH_SEGMENT_FIELDS.each do |f|
        next unless s.key?(f)

        errors << { code: 'reserved_branching', path: "segments[#{i}].#{f}",
                    message: "segment #{f} is reserved for branching (§7) and MUST be absent" }
      end
    end
    errors
  end
  private_class_method :_reserved_field_errors

  def self._num?(v)
    v.is_a?(Numeric) && (!v.is_a?(Float) || !v.nan?)
  end
  private_class_method :_num?

  # JavaScript Number.isInteger
  def self._integer?(v)
    v.is_a?(Integer) || (v.is_a?(Float) && v.finite? && v == v.floor)
  end
  private_class_method :_integer?

  def self._valid_start?(v)
    return false unless v.is_a?(String)

    Time.iso8601(v)
    true
  rescue ArgumentError
    false
  end
  private_class_method :_valid_start?

  def self._deep_string_keys(obj)
    case obj
    when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = _deep_string_keys(v) }
    when Array then obj.map { |v| _deep_string_keys(v) }
    else obj
    end
  end
  private_class_method :_deep_string_keys
end
