'use strict';

/**
 * test_mcp.js: the MCP server over stdio (JSON-RPC lines). Calls every tool
 * and checks the values against planet-time.js, plus the protocol edges
 * (ping, notifications, unknown tool/method, invalid requests, tool errors).
 * The server exposes planet-time tools only; it computes no LTX planIds.
 *
 * Run: node test/test_mcp.js   (from node/mcp-server)
 */

const path = require('path');
const assert = require('assert');
const { spawn } = require('child_process');
const PT = require('../../../javascript/planet-time/planet-time.js');

const T = Date.UTC(2026, 8, 29, 12, 0, 0);   // 2026-09-29T12:00:00Z
const call = (id, name, args) => ({ jsonrpc: '2.0', id, method: 'tools/call', params: { name, arguments: args } });

const requests = [
  { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} },
  { jsonrpc: '2.0', method: 'notifications/initialized' },
  { jsonrpc: '2.0', id: 2, method: 'tools/list' },
  call(3, 'get_planet_time', { planet: 'mars', utc_ms: T }),
  call(4, 'get_planet_time', { planet: 'Jupiter', utc_ms: T, tz_offset_h: 2 }),
  call(5, 'get_light_travel', { from: 'earth', to: 'mars', utc_ms: T }),
  call(6, 'get_mtc', { utc_ms: T }),
  call(7, 'get_planet_distance', { from: 'earth', to: 'saturn', utc_ms: T }),
  call(8, 'find_meeting_windows', { planet_a: 'earth', planet_b: 'mars', from_ms: T, days: 7 }),
  call(9, 'check_line_of_sight', { from: 'earth', to: 'mars', utc_ms: T }),
  call(10, 'get_planet_time', { planet: 'pluto', utc_ms: T }),
  call(11, 'get_mtc', {}),
  call(12, 'no_such_tool', {}),
  { jsonrpc: '2.0', id: 13, method: 'no/such/method' },
  { jsonrpc: '2.0', id: 14, method: 'ping' },
  { jsonrpc: '2.0', method: 'some/notification' },
  call(15, 'find_meeting_windows', { planet_a: 'earth', planet_b: 'mars', from_ms: T, days: -3 }),
];
const rawLines = ['null', '{not json'];

const child = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], { stdio: ['pipe', 'pipe', 'inherit'] });
let out = '';
child.stdout.on('data', d => { out += d; });
child.on('close', (code) => {
  const msgs = out.split('\n').filter(Boolean).map(l => JSON.parse(l));
  const byId = {};
  for (const m of msgs) if (m.id != null) byId[m.id] = m;
  const nullIdErrors = msgs.filter(m => m.id === null);
  const data = (id) => JSON.parse(byId[id].result.content[0].text);
  let failed = 0, passed = 0;
  const check = (name, fn) => {
    try { fn(); passed++; console.log('PASS ' + name); }
    catch (e) { failed++; console.log('FAIL ' + name + ': ' + e.message); }
  };
  const near = (a, b, eps, what) => assert.ok(Math.abs(a - b) <= eps, `${what}: ${a} vs ${b}`);
  const d = new Date(T);

  check('server survives bad input and exits 0 on stdin close', () => assert.strictEqual(code, 0));
  check('initialize', () => assert.strictEqual(byId[1].result.serverInfo.name, 'interplanet-mcp'));
  check('tools/list has all six tools', () => {
    const names = byId[2].result.tools.map(t => t.name).sort();
    assert.deepStrictEqual(names, ['check_line_of_sight', 'find_meeting_windows', 'get_light_travel',
      'get_mtc', 'get_planet_distance', 'get_planet_time']);
  });
  check('get_planet_time mars equals getPlanetTime', () => {
    const r = data(3), e = PT.getPlanetTime('mars', d);
    assert.strictEqual(r.planet, 'Mars');
    assert.strictEqual(r.time_str_full, e.timeStringFull);
    assert.strictEqual(r.is_work_hour, e.isWorkHour);
    assert.strictEqual(r.day_number, e.dayNumber);
    assert.deepStrictEqual(r.sol_info, e.solInfo);
  });
  check('get_planet_time Jupiter tz +2 (case-insensitive name)', () => {
    const r = data(4), e = PT.getPlanetTime('jupiter', d, 2);
    assert.strictEqual(r.time_str_full, e.timeStringFull);
    assert.strictEqual(r.is_work_period, e.isWorkPeriod);
  });
  check('get_light_travel earth-mars', () => {
    const r = data(5);
    near(r.seconds, PT.lightTravelSeconds('earth', 'mars', d), 1e-6, 'seconds');
    assert.strictEqual(r.formatted, PT.formatLightTime(r.seconds));
  });
  check('get_mtc equals getMTC', () => {
    const r = data(6), e = PT.getMTC(d);
    assert.deepStrictEqual([r.sol, r.hour, r.minute, r.second], [e.sol, e.hour, e.minute, e.second]);
    assert.strictEqual(r.time_str, e.mtcString);
  });
  check('get_planet_distance earth-saturn', () => {
    const r = data(7);
    near(r.au, PT.bodyDistance('earth', 'saturn', d), 1e-9, 'au');
    near(r.km, r.au * 149597870.7, 1e-3, 'km');
  });
  check('find_meeting_windows earth-mars 7 days equals findMeetingWindows', () => {
    const r = data(8), e = PT.findMeetingWindows('earth', 'mars', 7, d);
    assert.strictEqual(r.length, e.length);
    r.forEach((w, i) => {
      assert.strictEqual(w.start_ms, e[i].startMs);
      assert.strictEqual(w.end_iso, new Date(e[i].endMs).toISOString());
    });
  });
  check('check_line_of_sight earth-mars carries closest_sun_au', () => {
    const r = data(9), e = PT.checkLineOfSight('earth', 'mars', d);
    assert.strictEqual(r.clear, e.clear);
    near(r.closest_sun_au, e.closestSunAU, 1e-12, 'closest_sun_au');
    near(r.elong_deg, e.elongDeg, 1e-12, 'elong_deg');
  });
  check('unknown planet is a tool error', () => {
    assert.strictEqual(byId[10].result.isError, true);
    assert.ok(/Unknown planet/.test(byId[10].result.content[0].text));
  });
  check('missing utc_ms is a tool error', () => assert.strictEqual(byId[11].result.isError, true));
  check('unknown tool is -32601', () => assert.strictEqual(byId[12].error.code, -32601));
  check('unknown method is -32601', () => assert.strictEqual(byId[13].error.code, -32601));
  check('ping returns an empty result', () => assert.deepStrictEqual(byId[14].result, {}));
  check('negative days clamp to one day', () => assert.ok(Array.isArray(data(15))));
  check('notifications get no response; null and bad JSON get one error each', () => {
    assert.strictEqual(nullIdErrors.length, 2);
    assert.deepStrictEqual(nullIdErrors.map(m => m.error.code).sort(), [-32600, -32700]);
    const answered = msgs.length - nullIdErrors.length;
    assert.strictEqual(answered, requests.filter(r => r.id !== undefined).length);
  });
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
});
child.stdin.end(rawLines.concat(requests.map(r => JSON.stringify(r))).join('\n') + '\n');
