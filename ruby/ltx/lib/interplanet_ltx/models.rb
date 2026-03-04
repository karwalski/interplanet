# frozen_string_literal: true

# models.rb — LTX value types (Struct-based)
# Story 33.5 — Ruby LTX gem

module InterplanetLtx
  # A participant node in an LTX session.
  LtxNode = Struct.new(:id, :name, :role, :delay, :location, keyword_init: true)

  # A segment type + quantum count template entry.
  LtxSegmentTemplate = Struct.new(:type, :q, keyword_init: true)

  # A computed, timed segment with UTC epoch milliseconds.
  LtxSegment = Struct.new(:type, :q, :start_ms, :end_ms, :dur_min, keyword_init: true)

  # A per-node perspective URL.
  LtxNodeUrl = Struct.new(:node_id, :name, :role, :url, keyword_init: true)

  # An LTX session plan configuration (v2 schema).
  LtxPlan = Struct.new(:v, :title, :start, :quantum, :mode, :nodes, :segments, keyword_init: true)
end
