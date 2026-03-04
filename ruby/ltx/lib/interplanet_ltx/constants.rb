# frozen_string_literal: true

# constants.rb — LTX library constants
# Story 33.5 — Ruby LTX gem

module InterplanetLtx
  VERSION           = '1.0.0'
  DEFAULT_QUANTUM   = 3
  DEFAULT_SEG_COUNT = 7
  DEFAULT_API_BASE  = 'https://interplanet.live/api/ltx.php'

  DEFAULT_SEGMENTS = [
    { type: 'PLAN_CONFIRM', q: 2 },
    { type: 'TX',           q: 2 },
    { type: 'RX',           q: 2 },
    { type: 'CAUCUS',       q: 2 },
    { type: 'TX',           q: 2 },
    { type: 'RX',           q: 2 },
    { type: 'BUFFER',       q: 1 },
  ].map(&:freeze).freeze
end
