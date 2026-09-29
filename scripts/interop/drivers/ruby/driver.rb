# frozen_string_literal: true

# Interop driver for ruby/ltx (see scripts/interop/run.js).
$LOAD_PATH.unshift File.join(ENV.fetch('ROOT'), 'ruby/ltx/lib')
require 'interplanet_ltx'
require 'json'

L = InterplanetLtx
in_dir, out_dir = ARGV

plan = L.create_plan(title: 'Réunion Mars 🚀', start: '2026-03-15T14:00:00.000Z', delay_sec: 840)
plan.quantum = 3
plan.mode = 'LTX-ASYNC'
plan.nodes = [
  L::LtxNode.new(id: 'N0', name: 'Earth HQ', role: 'HOST', delay: 0, location: 'earth'),
  L::LtxNode.new(id: 'N1', name: 'Mars Hab-01', role: 'PARTICIPANT', delay: 840, location: 'mars'),
  L::LtxNode.new(id: 'N2', name: 'L-1 Gateway', role: 'PARTICIPANT', delay: 2, location: 'moon'),
]
seg = L::LtxSegmentTemplate
plan.segments = [
  seg.new(type: 'PLAN_CONFIRM', q: 2),
  seg.new(type: 'TX', q: 3, speaker: 'N0', label: 'Ouverture: état de la mission'),
  seg.new(type: 'RX', q: 3),
  seg.new(type: 'TX', q: 2, speaker: 'N1', label: 'Réponse 🔴'),
  seg.new(type: 'BUFFER', q: 1),
]
puts 'NOTE no typed v3 upgrade'

wire = L.send(:_b64url_decode, L.encode_hash(plan).sub('#l=', ''))
File.write(File.join(out_dir, 'wire-v2.json'), wire)
puts "ID_V2 #{L.make_plan_id(plan)}"

%w[2 3].each do |v|
  parsed = JSON.parse(File.read(File.join(in_dir, "js-v#{v}.json"), encoding: 'UTF-8'))
  puts "JS_V#{v} #{L.make_plan_id(parsed)}"
end
