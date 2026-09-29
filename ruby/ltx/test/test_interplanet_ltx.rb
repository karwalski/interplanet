#!/usr/bin/env ruby
# frozen_string_literal: true
# test_interplanet_ltx.rb — Unit tests for Ruby LTX gem
# Story 33.5 · Ruby 2.6+ · No external dependencies
# Run with: ruby -Ilib test/test_interplanet_ltx.rb  (or: make test)

$LOAD_PATH.unshift File.join(__dir__, '../lib')
require 'interplanet_ltx'

# Module-level alias for brevity; include for constants
ILX = InterplanetLtx
include ILX

@passed = 0
@failed = 0

def check(name, cond)
  if cond
    @passed += 1
  else
    @failed += 1
    puts "FAIL: #{name}"
  end
end

def section(name)
  puts "\n-- #{name} --"
end

# Convenience wrappers so callers don't need ILX. prefix everywhere
def create_plan(**kw);    ILX.create_plan(**kw);    end
def upgrade_config(cfg);  ILX.upgrade_config(cfg);  end
def compute_segments(p);  ILX.compute_segments(p);  end
def total_min(p);         ILX.total_min(p);         end
def make_plan_id(p);      ILX.make_plan_id(p);      end
def encode_hash(p);       ILX.encode_hash(p);       end
def decode_hash(h);       ILX.decode_hash(h);       end
def build_node_urls(p,u); ILX.build_node_urls(p,u); end
def generate_ics(p);      ILX.generate_ics(p);      end
def format_hms(s);        ILX.format_hms(s);        end
def format_utc(ms);       ILX.format_utc(ms);       end

# ── Constants ──────────────────────────────────────────────────────────────
section 'Constants'
check 'VERSION not empty',              !VERSION.empty?
check 'VERSION is 1.0.0',              VERSION == '1.0.0'
check 'DEFAULT_QUANTUM == 5',          DEFAULT_QUANTUM == 5
check 'DEFAULT_SEG_COUNT == 7',        DEFAULT_SEG_COUNT == 7
check 'DEFAULT_API_BASE has https',    DEFAULT_API_BASE.start_with?('https://')
check 'DEFAULT_SEGMENTS[0] PLAN_CONFIRM', DEFAULT_SEGMENTS[0][:type] == 'PLAN_CONFIRM'
check 'DEFAULT_SEGMENTS[1] TX',        DEFAULT_SEGMENTS[1][:type] == 'TX'
check 'DEFAULT_SEGMENTS[2] RX',        DEFAULT_SEGMENTS[2][:type] == 'RX'
check 'DEFAULT_SEGMENTS[6] BUFFER',    DEFAULT_SEGMENTS[6][:type] == 'BUFFER'
check 'DEFAULT_SEGMENTS[0] q == 2',    DEFAULT_SEGMENTS[0][:q] == 2
check 'DEFAULT_SEGMENTS[6] q == 1',    DEFAULT_SEGMENTS[6][:q] == 1

# ── create_plan ────────────────────────────────────────────────────────────
section 'create_plan'
plan = create_plan(start: '2026-03-15T14:00:00Z')
check 'v == 2',                        plan.v == 2
check 'title == LTX Session',          plan.title == 'LTX Session'
check 'start preserved',               plan.start == '2026-03-15T14:00:00Z'
check 'quantum == 5',                  plan.quantum == 5
check 'mode == LTX',                   plan.mode == 'LTX'
check 'node_count == 2',              plan.nodes.length == 2
check 'nodes[0].id == N0',             plan.nodes[0].id == 'N0'
check 'nodes[0].role == HOST',         plan.nodes[0].role == 'HOST'
check 'nodes[0].location == earth',    plan.nodes[0].location == 'earth'
check 'nodes[0].delay == 0',           plan.nodes[0].delay == 0
check 'nodes[1].id == N1',             plan.nodes[1].id == 'N1'
check 'nodes[1].role == PARTICIPANT',  plan.nodes[1].role == 'PARTICIPANT'
check 'nodes[1].location == mars',     plan.nodes[1].location == 'mars'
check 'seg_count == 7',               plan.segments.length == 7

plan2 = create_plan(title: 'Q3 Review', start: '2026-06-01T10:00:00Z', delay_sec: 860)
check 'custom title',                  plan2.title == 'Q3 Review'
check 'custom delay',                  plan2.nodes[1].delay == 860

# ── upgrade_config ──────────────────────────────────────────────────────────
section 'upgrade_config'
cfg = { title: 'Upgraded', start: '2026-04-01T09:00:00Z', quantum: 5 }
up  = upgrade_config(cfg)
check 'upgraded title',                up.title == 'Upgraded'
check 'upgraded start',                up.start == '2026-04-01T09:00:00Z'
check 'upgraded quantum',              up.quantum == 5
check 'upgraded has default nodes',    up.nodes.length == 2
check 'upgraded has default segments', up.segments.length == 7

cfg2 = { nodes: [
  { id: 'X0', name: 'Base Alpha', role: 'HOST',        delay: 0,    location: 'earth' },
  { id: 'X1', name: 'Base Beta',  role: 'PARTICIPANT', delay: 1200, location: 'mars'  },
] }
up2 = upgrade_config(cfg2)
check 'custom nodes[0] id',           up2.nodes[0].id == 'X0'
check 'custom nodes[1] delay',        up2.nodes[1].delay == 1200

# ── compute_segments ────────────────────────────────────────────────────────
section 'compute_segments'
segs = compute_segments(plan)
check 'seg_count == 7',               segs.length == 7
check 'segs[0].type PLAN_CONFIRM',     segs[0].type == 'PLAN_CONFIRM'
check 'segs[6].type BUFFER',           segs[6].type == 'BUFFER'
check 'segs[0].q == 2',               segs[0].q == 2
check 'segs[0].start_ms > 0',         segs[0].start_ms > 0
check 'segs[0].end_ms > start_ms',     segs[0].end_ms > segs[0].start_ms
check 'segs[0].dur_min == 10',        segs[0].dur_min == 10
check 'segs[6].dur_min == 5',         segs[6].dur_min == 5
(0...segs.length - 1).each do |i|
  check "segs[#{i}] contiguous",      segs[i].end_ms == segs[i + 1].start_ms
end

# ── total_min ────────────────────────────────────────────────────────────────
section 'total_min'
total = total_min(plan)
check 'total_min == 65',              total == 65
seg_sum = segs.sum(&:dur_min)
check 'total_min matches seg sum',     seg_sum == total

# ── make_plan_id ─────────────────────────────────────────────────────────────
section 'make_plan_id'
pid = make_plan_id(plan)
check 'plan_id not empty',            !pid.empty?
check 'plan_id starts LTX-',          pid.start_with?('LTX-')
check 'plan_id has date 20260315',     pid.include?('20260315')
check 'plan_id has -v2-',             pid.include?('-v2-')
check 'plan_id deterministic',         make_plan_id(plan) == pid
check 'plan_id length > 20',          pid.length > 20

# ── encode_hash / decode_hash ─────────────────────────────────────────────────
section 'encode_hash / decode_hash'
hash = encode_hash(plan)
check 'hash starts #l=',              hash.start_with?('#l=')
check 'hash non-empty payload',       hash.length > 10
check 'hash url-safe (no +)',         !hash.include?('+')
check 'hash url-safe (no /)',         !hash.include?('/')
check 'hash no = padding',            !hash[3..].include?('=')

decoded = decode_hash(hash)
check 'decode_hash returns plan',      !decoded.nil?
check 'decoded v == 2',               decoded&.v == 2
check 'decoded title matches',        decoded&.title == plan.title
check 'decoded quantum matches',      decoded&.quantum == plan.quantum
check 'decoded node_count == 2',      decoded&.nodes&.length == 2
check 'decoded seg_count == 7',       decoded&.segments&.length == 7

# Strip # prefix
decoded2 = decode_hash(hash[1..])
check 'decode without # works',       !decoded2.nil?

# Invalid
bad = decode_hash('!@#$%')
check 'invalid hash returns nil',      bad.nil?

# ── build_node_urls ────────────────────────────────────────────────────────
section 'build_node_urls'
urls = build_node_urls(plan, 'https://interplanet.live/ltx.html')
check 'url_count == 2',              urls.length == 2
check 'urls[0].node_id == N0',       urls[0].node_id == 'N0'
check 'urls[0].role == HOST',        urls[0].role == 'HOST'
check 'urls[0].url has ?node=N0',    urls[0].url.include?('?node=N0')
check 'urls[0].url has #l=',         urls[0].url.include?('#l=')
check 'urls[0].url has base',        urls[0].url.start_with?('https://interplanet.live')
check 'urls[1].node_id == N1',       urls[1].node_id == 'N1'
check 'urls[1].role == PARTICIPANT', urls[1].role == 'PARTICIPANT'

# ── generate_ics ───────────────────────────────────────────────────────────
section 'generate_ics'
ics = generate_ics(plan)
check 'ICS starts VCALENDAR',        ics.start_with?('BEGIN:VCALENDAR')
check 'ICS has END:VCALENDAR',       ics.include?('END:VCALENDAR')
check 'ICS has BEGIN:VEVENT',        ics.include?('BEGIN:VEVENT')
check 'ICS has END:VEVENT',          ics.include?('END:VEVENT')
check 'ICS has VERSION:2.0',         ics.include?('VERSION:2.0')
check 'ICS has DTSTART',             ics.include?('DTSTART:')
check 'ICS has DTEND',               ics.include?('DTEND:')
check 'ICS has SUMMARY',             ics.include?('SUMMARY:')
check 'ICS has LTX:1',              ics.include?('LTX:1')
check 'ICS has LTX-PLANID',         ics.include?('LTX-PLANID:')
check 'ICS has LTX-QUANTUM:PT5M',   ics.include?('LTX-QUANTUM:PT5M')
check 'ICS has LTX-NODE',           ics.include?('LTX-NODE:')
check 'ICS has CRLF',               ics.include?("\r\n")

# ── format_hms / format_utc ────────────────────────────────────────────────
section 'format_hms / format_utc'
check 'format_hms(0) == 00:00',        format_hms(0)    == '00:00'
check 'format_hms(30) == 00:30',       format_hms(30)   == '00:30'
check 'format_hms(59) == 00:59',       format_hms(59)   == '00:59'
check 'format_hms(60) == 01:00',       format_hms(60)   == '01:00'
check 'format_hms(3600) == 01:00:00',  format_hms(3600) == '01:00:00'
check 'format_hms(3661) == 01:01:01',  format_hms(3661) == '01:01:01'
check 'format_hms(7322) == 02:02:02',  format_hms(7322) == '02:02:02'
check 'format_hms(-1) == 00:00',       format_hms(-1)   == '00:00'

# 2026-03-01T14:30:45Z = epoch 1772375445000
utc = format_utc(1_772_375_445_000)
check 'format_utc has time part',      utc.start_with?('14:30:45')
check 'format_utc ends UTC',           utc.end_with?('UTC')
check 'format_utc(0) == 00:00:00 UTC', format_utc(0) == '00:00:00 UTC'

# ── Conformance: golden planId vectors (spec/golden/plan-ids.json) ─────────
section 'Conformance: golden planId vectors'
golden = JSON.parse(File.read(File.join(__dir__, '../../../spec/golden/plan-ids.json')))
gv_by_name = golden['vectors'].each_with_object({}) { |gv, h| h[gv['name']] = gv }
check 'golden vectors present (>= 9)',    golden['vectors'].size >= 9
golden['vectors'].each do |gv|
  got = make_plan_id(gv['plan'])
  check "golden #{gv['name']} planId (got #{got})", got == gv['planId']
  check "golden #{gv['name']} planHash", ILX.plan_hash(gv['plan']) == gv['planHash'] if gv['planHash']
end
check 'golden anchor v2 default',         gv_by_name['v2-createPlan-default']['planId'] == 'LTX-20260315-EARTHHQ-MARS-v2-2596ffe8'
check 'golden v2 key-order sensitive',    gv_by_name['v2-createPlan-default']['planId'] != gv_by_name['v2-key-order-sensitive']['planId']
check 'golden v3 order-insensitive',      gv_by_name['v3-upgrade-delays']['planId'] == gv_by_name['v3-key-order-insensitive']['planId']
check 'golden v3 amendment chain hash',   gv_by_name['v3-amendment']['plan']['prevPlanHash'] == gv_by_name['v3-upgrade-delays']['planHash']
fc_float = JSON.parse(JSON.generate(gv_by_name['v2-freeze-check']['plan']))
fc_float['nodes'][1]['delay'] = fc_float['nodes'][1]['delay'].to_f
check 'v2 hash formats 840.0 as 840',     make_plan_id(fc_float) == gv_by_name['v2-freeze-check']['planId']
check 'JsJson.number matches JS',         [840.0, 0.1, 1e21, 1e-7, 1.5e-7, 1e16, -2.5, 0.000001].map { |x| JsJson.number(x) } ==
                                          %w[840 0.1 1e+21 1e-7 1.5e-7 10000000000000000 -2.5 0.000001]

# ── Plan validation: reserved streams / branching (§3.5, §7) ─────────────
section 'Plan validation: reserved fields'
codes_of = ->(r) { r[:errors].map { |e| e[:code] } }
golden['vectors'].each do |gv|
  check "validate_plan accepts golden #{gv['name']}", ILX.validate_plan(gv['plan'])[:valid] == true
end
vp_base = gv_by_name['v3-upgrade-delays']['plan']
vp_v2   = gv_by_name['v2-freeze-check']['plan']
check 'validate_plan v3 empty streams ok',  ILX.validate_plan(vp_base.merge('streams' => []))[:valid] == true
vp_streams = ILX.validate_plan(vp_base.merge('streams' => [{ 'id' => 'S1' }]))
check 'validate_plan non-empty streams',    vp_streams[:valid] == false && codes_of.call(vp_streams).include?('reserved_streams')
check 'validate_plan streams error path',   vp_streams[:errors].find { |e| e[:code] == 'reserved_streams' }[:path] == 'streams'
check 'validate_plan streams non-array',    codes_of.call(ILX.validate_plan(vp_base.merge('streams' => 'S1'))).include?('reserved_streams')
check 'validate_plan segment stream',       codes_of.call(ILX.validate_plan(vp_base.merge('segments' => [{ 'type' => 'TX', 'q' => 1, 'stream' => 'S1' }]))).include?('reserved_streams')
check 'validate_plan branches',             codes_of.call(ILX.validate_plan(vp_base.merge('branches' => []))).include?('reserved_branching')
check 'validate_plan branching',            codes_of.call(ILX.validate_plan(vp_base.merge('branching' => { 'mode' => 'local' }))).include?('reserved_branching')
vp_seg_branch = ILX.validate_plan(vp_base.merge('segments' => [{ 'type' => 'CAUCUS', 'q' => 1, 'branch' => 'B1' }]))
check 'validate_plan segment branch',       codes_of.call(vp_seg_branch).include?('reserved_branching') &&
                                            vp_seg_branch[:errors][0][:path] == 'segments[0].branch'
check 'validate_plan v2 streams is v3 field', codes_of.call(ILX.validate_plan(vp_v2.merge('streams' => []))).include?('v3_field_in_v2')
check 'validate_plan v2 branching',         codes_of.call(ILX.validate_plan(vp_v2.merge('branching' => true))).include?('reserved_branching')
check 'validate_plan symbol keys',          codes_of.call(ILX.validate_plan(vp_v2.merge(branches: []))).include?('reserved_branching')
check 'validate_plan non-object',           codes_of.call(ILX.validate_plan(nil)).include?('not_an_object')
check 'validate_plan bad version',          codes_of.call(ILX.validate_plan(vp_v2.merge('v' => 7))).include?('invalid_version')
check 'validate_plan host not first',       codes_of.call(ILX.validate_plan(vp_v2.merge('nodes' => vp_v2['nodes'].reverse))).include?('invalid_host')
check 'validate_plan unsorted delays key',  codes_of.call(ILX.validate_plan(vp_base.merge('delays' => { 'N1|N0' => 860 }))).include?('invalid_delays')
check 'validate_plan unknown speaker',      codes_of.call(ILX.validate_plan(vp_v2.merge('segments' => [{ 'type' => 'TX', 'q' => 1, 'speaker' => 'N9' }]))).include?('unknown_speaker')
check 'validate_plan quantum out of range', codes_of.call(ILX.validate_plan(vp_v2.merge('quantum' => 0))).include?('invalid_quantum')

# ── Summary ──────────────────────────────────────────────────────────────
puts "\n=========================================="
puts "#{@passed} passed  #{@failed} failed"
exit @failed > 0 ? 1 : 0
