'use strict';
/**
 * test_http.js: end-to-end HTTP tests for the PHP services, each run under
 * PHP's built-in web server:
 *   api/time.php      planet, distance, windows (values against planet-time.js)
 *   api/ltx.php       session POST/GET, ics, feedback (SQLite getDB stub)
 *   cli ltx send      against the local api/ltx.php
 *   demo/mcp-server.php  every tool against planet-time.js, JSON-RPC edges
 *   demo/relay-server.php  register, send, receive, delete, token checks
 *
 * Run: node api/tests/test_http.js   (needs php with pdo_sqlite and sqlite3)
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { REPO, startSite, startPhp } = require('../../scripts/sweep/web/lib/site.js');
const PT = require(path.join(REPO, 'demo/planet-time.js'));
const LTX = require(path.join(REPO, 'javascript/ltx/ltx-sdk.js'));

let passed = 0, failed = 0;
async function check(name, fn) {
  try { await fn(); passed++; console.log('PASS ' + name); }
  catch (e) { failed++; console.log('FAIL ' + name + ': ' + (e && e.message)); }
}
const near = (a, b, eps, what) => assert.ok(Math.abs(a - b) <= eps, `${what}: ${a} vs ${b}`);

async function req(url, opts) {
  const r = await fetch(url, opts);
  const text = await r.text();
  let json = null;
  try { json = JSON.parse(text); } catch (_) {}
  return { status: r.status, headers: r.headers, text, json };
}
const postJson = (url, body, headers) => req(url, {
  method: 'POST', headers: Object.assign({ 'Content-Type': 'application/json' }, headers || {}),
  body: typeof body === 'string' ? body : JSON.stringify(body),
});

const BODIES = ['mercury', 'venus', 'earth', 'mars', 'jupiter', 'saturn', 'uranus', 'neptune', 'moon'];
const DATES = ['2026-09-29T12:00:00Z', '2025-01-15T03:17:00Z', '2030-06-01T20:45:00Z'];

async function testTime(base) {
  const T = base + '/api/time.php';
  await check('time.php planet: local time, work status, sol and light minutes equal planet-time.js', async () => {
    const bad = [];
    for (const body of BODIES) for (const at of DATES) for (const tz of [0, 3.5, -5.5]) {
      const r = await req(`${T}?action=planet&body=${body}&at=${at}&tz_offset=${tz}`);
      assert.strictEqual(r.status, 200, `${body} ${at} ${tz}: HTTP ${r.status}`);
      const d = new Date(at), e = PT.getPlanetTime(body, d, tz);
      const want = { local_time: e.timeString, is_work_hour: e.isWorkHour, is_work_period: e.isWorkPeriod };
      for (const k of Object.keys(want)) if (r.json[k] !== want[k]) bad.push(`${body} ${at} tz${tz} ${k}: ${r.json[k]} != ${want[k]}`);
      if (body === 'mars' && r.json.sol !== e.dayNumber) bad.push(`mars ${at} tz${tz} sol ${r.json.sol} != ${e.dayNumber}`);
      if (body !== 'earth' && body !== 'moon') {
        const lm = Math.round(PT.lightTravelSeconds('earth', body, d) / 60 * 100) / 100;
        if (Math.abs(r.json.light_minutes - lm) > 0.011) bad.push(`${body} ${at} light_minutes ${r.json.light_minutes} != ${lm}`);
      }
    }
    assert.deepStrictEqual(bad, []);
  });
  await check('time.php distance equals bodyDistance for sampled pairs', async () => {
    for (const [a, b] of [['earth', 'mars'], ['earth', 'jupiter'], ['venus', 'neptune'], ['mars', 'moon']]) {
      for (const at of DATES) {
        const r = await req(`${T}?action=distance&from=${a}&to=${b}&at=${at}`);
        const au = PT.bodyDistance(a, b, new Date(at));
        near(r.json.distance_au, au, 6e-5, `${a}-${b} ${at} AU`);
        near(r.json.light_seconds, au * PT.AU_SECONDS, 0.06, `${a}-${b} ${at} light s`);
        const c = r.json.conjunction_in_days;
        if (b === 'moon') assert.strictEqual(c, 0, 'no conjunction for the Moon');
        else assert.ok(c > 0 && c <= 800, `${a}-${b} conjunction_in_days ${c} in (0, 800]`);
      }
    }
  });
  await check('time.php conjunction_in_days finds the next Earth-Mars distance peak', async () => {
    const at = '2026-09-29T12:00:00Z';
    const r = await req(`${T}?action=distance&from=earth&to=mars&at=${at}`);
    const t0 = Date.parse(at), dist = (days) => PT.bodyDistance('earth', 'mars', new Date(t0 + days * 864e5));
    const c = r.json.conjunction_in_days;
    assert.ok(c > 30, `peak is not imminent: ${c}`);
    assert.ok(dist(c) > dist(c - 5) && dist(c) > dist(c + 5), `distance peaks at day ${c}`);
  });
  await check('time.php windows: every window is inside work hours in New York and on Mars', async () => {
    const r = await postJson(`${T}?action=windows`, {
      locations: [{ type: 'earth', tz: 'America/New_York' }, { type: 'planet', planet: 'mars' }],
      from_utc: '2026-09-29T00:00:00Z', horizon_days: 14,
    });
    assert.strictEqual(r.status, 200);
    assert.ok(r.json.windows_found > 0, 'found windows');
    const nyHour = (ms) => Number(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', hourCycle: 'h23' }).format(new Date(ms)));
    for (const w of r.json.windows) {
      const s = Date.parse(w.start_utc), e = Date.parse(w.end_utc);
      assert.ok(w.duration_minutes >= 60);
      for (let t = s; t < e; t += 15 * 60000) {
        assert.ok(PT.getPlanetTime('mars', new Date(t)).isWorkHour, `mars work at ${new Date(t).toISOString()}`);
        const h = nyHour(t);
        assert.ok(h >= 9 && h < 17, `NY work at ${new Date(t).toISOString()} (${h})`);
      }
    }
  });
  await check('time.php bad input is a 4xx JSON error, never a 500', async () => {
    const cases = [
      ['GET', '?action=planet'], ['GET', '?action=planet&body=pluto'], ['GET', '?action=planet&body[]=mars'],
      ['GET', '?action=planet&body=mars&at=garbage'], ['GET', '?action=distance&from=earth'],
      ['GET', '?action=distance&from=earth&to=pluto'], ['GET', '?action=nope'], ['GET', '?action[]=x'],
      ['GET', '?action=windows'], ['POST', '?action=windows', ''], ['POST', '?action=windows', '{"locations":["x"]}'],
      ['POST', '?action=windows', '{"locations":[{"tz":"Nowhere/X"}]}'],
      ['POST', '?action=windows', '{"locations":[{"type":"planet","planet":"pluto"}]}'],
      ['POST', '?action=windows', '{"locations":[{"tz":"UTC"}],"from_utc":["x"]}'],
      ['POST', '?action=windows', '{"locations":[{"tz":"UTC"}],"horizon_days":400}'],
    ];
    for (const [m, q, body] of cases) {
      const r = await req(T + q, m === 'POST' ? { method: 'POST', body } : {});
      assert.ok(r.status >= 400 && r.status < 500, `${m} ${q} ${body || ''}: HTTP ${r.status}`);
      assert.ok(r.json && typeof r.json.error === 'string', `${q}: JSON error body`);
    }
  });
}

const PLAN = {
  v: 2, title: 'Sweep, test; with\nnewline', start: '2026-10-01T10:00:00Z', quantum: 5, mode: 'LTX-ASYNC',
  segments: [{ type: 'PLAN_CONFIRM', q: 2 }, { type: 'TX', q: 2 }, { type: 'RX', q: 2 }, { type: 'BUFFER', q: 1 }],
  nodes: [
    { id: 'N0', name: 'Earth HQ', role: 'HOST', delay: 0, location: 'earth' },
    { id: 'N1', name: 'Mars Base Alpha With A Very Long Name', role: 'PARTICIPANT', delay: 1240, location: 'mars' },
  ],
};

function icsLinesOk(ics) {
  assert.ok(ics.endsWith('\r\n'), 'ends with CRLF');
  const lines = ics.split('\r\n').slice(0, -1);
  for (const l of lines) {
    assert.ok(!l.includes('\n') && !l.includes('\r'), 'no bare LF/CR in a line');
    assert.ok(Buffer.byteLength(l) <= 75, `line over 75 octets: ${l}`);
  }
  return ics.replace(/\r\n /g, '');   // unfolded
}

async function testLtx(base) {
  const L = base + '/api/ltx.php';
  const planId = LTX.makePlanId(PLAN);
  await check('ltx.php POST session: planId equals makePlanId, stored, segments and total', async () => {
    const r = await postJson(L + '?action=session', PLAN);
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.json.plan_id, planId);
    assert.strictEqual(r.json.stored, true);
    assert.strictEqual(r.json.total_min, 35);
    assert.strictEqual(r.json.mode, 'LTX-ASYNC');
    assert.deepStrictEqual(r.json.segments.map(s => s.start_utc),
      ['2026-10-01T10:00:00Z', '2026-10-01T10:10:00Z', '2026-10-01T10:20:00Z', '2026-10-01T10:30:00Z']);
    const again = await postJson(L + '?action=session', PLAN);
    assert.strictEqual(again.json.plan_id, planId, 'idempotent');
  });
  await check('ltx.php GET session returns the plan as stored and counts views', async () => {
    const r1 = await req(L + '?action=session&plan_id=' + encodeURIComponent(planId));
    assert.strictEqual(r1.status, 200);
    assert.deepStrictEqual(r1.json.plan, PLAN);
    assert.strictEqual(LTX.makePlanId(r1.json.plan), planId, 'stored plan hashes back to plan_id');
    const r2 = await req(L + '?action=session&plan_id=' + encodeURIComponent(planId));
    assert.strictEqual(r2.json.views, r1.json.views + 1);
  });
  await check('ltx.php ics (no body): valid folded iCalendar with escaped TEXT', async () => {
    const r = await req(L + '?action=ics&plan_id=' + encodeURIComponent(planId), { method: 'POST' });
    assert.strictEqual(r.status, 200);
    assert.ok(/^text\/calendar/.test(r.headers.get('content-type')));
    assert.ok(/attachment; filename="ltx-2026-10-01\.ics"/.test(r.headers.get('content-disposition')));
    const ics = icsLinesOk(r.text);
    assert.ok(ics.includes('\r\nUID:' + planId + '@interplanet.live\r\n'));
    assert.ok(ics.includes('\r\nSUMMARY:Sweep\\, test\\; with\\nnewline\r\n'), 'SUMMARY escaped');
    assert.ok(ics.includes('\r\nDTSTART:20261001T100000Z\r\nDTEND:20261001T103500Z\r\n'));
    assert.ok(ics.includes('\r\nLTX-NODE:ID=EARTH-HQ;ROLE=HOST\r\n'), 'node id as in the SDKs');
    assert.ok(ics.includes('\r\nLTX-LOCALTIME:NODE=MARS-BASE-ALPHA-WITH-A-VERY-LONG-NAME;SCHEME=LMST;PARAMS=LONGITUDE:0E\r\n'));
  });
  await check('ltx.php ics with a start override', async () => {
    const r = await postJson(L + '?action=ics&plan_id=' + encodeURIComponent(planId), { start: '2026-11-02T08:00:00Z' });
    assert.ok(icsLinesOk(r.text).includes('\r\nDTSTART:20261102T080000Z\r\nDTEND:20261102T083500Z\r\n'));
  });
  await check('ltx.php feedback stores a row', async () => {
    const r = await postJson(L + '?action=feedback', { plan_id: planId, outcome: 'completed', satisfaction: 9,
      mode: 'LTX-ASYNC', actual_start: '2026-10-01T10:00:00Z', actual_end: '2026-10-01T10:40:00Z',
      nodes: [{ name: 'Earth HQ', location: 'earth', delay_s: 0 }] });
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.json.ok, true);
    assert.ok(r.json.feedback_id >= 1);
  });
  await check('ltx.php errors: 4xx JSON, never a 500', async () => {
    const id = encodeURIComponent(planId);
    const cases = [
      ['GET', '?action=session&plan_id=LTX-20990101-NONE-X-v2-00000000', undefined, 404],
      ['GET', '?action=session&plan_id=bad', undefined, 400], ['GET', '?action=session', undefined, 400],
      ['GET', '?action=session&plan_id[]=x', undefined, 400],
      ['POST', '?action=session', '', 400], ['POST', '?action=session', 'garbage', 400],
      ['POST', '?action=session', '{"segments":[{"type":"TX"}],"start":"nope"}', 400],
      ['POST', '?action=session', '{"segments":[{"type":"TX"}],"start":["a"]}', 400],
      ['POST', '?action=ics&plan_id=' + id, '{"start":"bad"}', 400],
      ['POST', '?action=ics&plan_id=' + id, '{"start":["bad"]}', 400],
      ['POST', '?action=ics&plan_id=LTX-20990101-NONE-X-v2-00000000', '', 404],
      ['GET', '?action=ics&plan_id=' + id, undefined, 405], ['GET', '?action=feedback', undefined, 405],
      ['GET', '?action=bogus', undefined, 404], ['GET', '?action[]=x', undefined, 404],
    ];
    for (const [m, q, body, want] of cases) {
      const r = await req(L + q, m === 'POST' ? { method: 'POST', body } : {});
      assert.strictEqual(r.status, want, `${m} ${q} ${body || ''}: HTTP ${r.status} ${r.text.slice(0, 120)}`);
      assert.ok(r.json && typeof r.json.error === 'string', `${q}: JSON error body`);
    }
  });
  await check('ltx.php OPTIONS preflight is 204 with CORS headers', async () => {
    const r = await req(L + '?action=session', { method: 'OPTIONS' });
    assert.strictEqual(r.status, 204);
    assert.strictEqual(r.headers.get('access-control-allow-origin'), '*');
  });
  await check('cli "ltx send --api" stores the plan in the local api/ltx.php', async () => {
    const nodes = ['Earth HQ:host:earth', 'Mars Base:participant:mars:1240'];
    const cli = path.join(REPO, 'cli/bin/interplanet.js');
    const args = ['--start', '2026-10-01T10:00:00Z', '--title', 'CLI send', '--mode', 'async'];
    const sent = spawnSync(process.execPath, [cli, 'ltx', 'send', ...nodes, ...args, '--api', L], { encoding: 'utf8' });
    assert.strictEqual(sent.status, 0, sent.stderr);
    const out = JSON.parse(sent.stdout);
    const plan = JSON.parse(spawnSync(process.execPath, [cli, 'ltx', 'plan', ...nodes, ...args], { encoding: 'utf8' }).stdout);
    assert.strictEqual(out.stored, true);
    assert.strictEqual(out.plan_id, LTX.makePlanId(plan));
    const got = await req(L + '?action=session&plan_id=' + encodeURIComponent(out.plan_id));
    assert.deepStrictEqual(got.json.plan, plan);
  });
}

async function rpc(url, body) {
  return postJson(url, body);
}

async function testMcpPhp(base) {
  const U = base + '/mcp-server.php';
  const T = Date.UTC(2026, 8, 29, 12, 0, 0), d = new Date(T);
  const tool = async (name, args) => {
    const r = await rpc(U, { jsonrpc: '2.0', id: 7, method: 'tools/call', params: { name, arguments: args } });
    assert.strictEqual(r.status, 200);
    return r.json.result;
  };
  const data = async (name, args) => {
    const res = await tool(name, args);
    assert.ok(!res.isError, name + ': ' + res.content[0].text);
    return JSON.parse(res.content[0].text);
  };
  await check('mcp-server.php initialize, tools/list (six tools), ping', async () => {
    const init = await rpc(U, { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} });
    assert.strictEqual(init.json.result.serverInfo.name, 'interplanet-mcp-php');
    const list = await rpc(U, { jsonrpc: '2.0', id: 2, method: 'tools/list' });
    assert.strictEqual(list.json.result.tools.length, 6);
    const ping = await rpc(U, { jsonrpc: '2.0', id: 3, method: 'ping' });
    assert.deepStrictEqual(ping.json.result, {});
  });
  await check('mcp-server.php get_planet_time equals planet-time.js (all bodies)', async () => {
    for (const b of BODIES) {
      const r = await data('get_planet_time', { planet: b, utc_ms: T, tz_offset_h: 1 });
      const e = PT.getPlanetTime(b, d, 1);
      assert.strictEqual(r.time_str_full, e.timeStringFull, b);
      assert.strictEqual(r.is_work_hour, e.isWorkHour, b);
      assert.strictEqual(r.day_number, e.dayNumber, b);
    }
  });
  await check('mcp-server.php get_light_travel, get_mtc, get_planet_distance', async () => {
    const lt = await data('get_light_travel', { from: 'earth', to: 'mars', utc_ms: T });
    near(lt.seconds, PT.lightTravelSeconds('earth', 'mars', d), 0.01, 'seconds');
    const mtc = await data('get_mtc', { utc_ms: T });
    const e = PT.getMTC(d);
    assert.deepStrictEqual([mtc.sol, mtc.hour, mtc.minute, mtc.second], [e.sol, e.hour, e.minute, e.second]);
    const dist = await data('get_planet_distance', { from: 'earth', to: 'jupiter', utc_ms: T });
    near(dist.au, PT.bodyDistance('earth', 'jupiter', d), 1e-6, 'au');
  });
  await check('mcp-server.php find_meeting_windows and check_line_of_sight', async () => {
    const w = await data('find_meeting_windows', { planet_a: 'earth', planet_b: 'mars', from_ms: T, days: 7 });
    const e = PT.findMeetingWindows('earth', 'mars', 7, d);
    assert.deepStrictEqual(w.map(x => [x.start_ms, x.end_ms]), e.map(x => [x.startMs, x.endMs]));
    const los = await data('check_line_of_sight', { from: 'earth', to: 'mars', utc_ms: T });
    const le = PT.checkLineOfSight('earth', 'mars', d);
    assert.strictEqual(los.clear, le.clear);
    near(los.closest_sun_au, le.closestSunAU, 1e-6, 'closest_sun_au');
  });
  await check('mcp-server.php errors: tool errors, -32601, -32600, -32700, notification, GET', async () => {
    assert.strictEqual((await tool('get_planet_time', { planet: 'pluto', utc_ms: T })).isError, true);
    assert.strictEqual((await tool('get_planet_time', { planet: ['mars'], utc_ms: T })).isError, true);
    assert.strictEqual((await tool('get_mtc', {})).isError, true);
    const unknownTool = await rpc(U, { jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'nope' } });
    assert.strictEqual(unknownTool.json.error.code, -32601);
    assert.strictEqual((await rpc(U, { jsonrpc: '2.0', id: 5, method: 'nope' })).json.error.code, -32601);
    assert.strictEqual((await rpc(U, 'null')).json.error.code, -32600);
    assert.strictEqual((await rpc(U, '{bad')).json.error.code, -32700);
    const note = await rpc(U, { jsonrpc: '2.0', method: 'notifications/initialized' });
    assert.strictEqual(note.status, 202);
    assert.strictEqual(note.text, '');
    assert.strictEqual((await req(U)).status, 405);
  });
}

async function testRelayPhp(base) {
  const R = base + '/relay-server.php';
  const plan = Object.assign({}, PLAN, { title: 'relay sweep ' + Date.now() });
  const bearer = (t) => ({ Authorization: 'Bearer ' + t });
  await check('relay-server.php health, register, send, receive, delete with token checks', async () => {
    const h = await req(R + '/relay/health');
    assert.strictEqual(h.json.status, 'ok');
    const reg = await postJson(R + '/relay/session', plan);
    assert.strictEqual(reg.status, 200);
    assert.strictEqual(reg.json.sessionId, LTX.makePlanId(plan));
    assert.strictEqual(reg.json.delay_ms, 1240000);
    const tok = reg.json.tls_fingerprint, id = encodeURIComponent(reg.json.sessionId);
    assert.strictEqual((await postJson(R + '/relay/session', plan)).status, 409, 're-register without token');
    assert.strictEqual((await postJson(R + '/relay/session', plan, bearer('wrong'))).status, 409);
    const re = await postJson(R + '/relay/session', plan, bearer(tok));
    assert.strictEqual(re.status, 200);
    assert.strictEqual(re.json.tls_fingerprint, tok, 'owner keeps its token');
    const frame = { nodeId: 'N0', data: { hello: 'mars' }, timestamp_ms: Date.now() - 1240001 };
    assert.strictEqual((await postJson(R + `/relay/${id}/send`, frame)).status, 401);
    assert.strictEqual((await postJson(R + `/relay/${id}/send`, { nodeId: 'N9', data: 1 }, bearer(tok))).status, 400);
    assert.strictEqual((await postJson(R + `/relay/${id}/send`, frame, bearer(tok))).status, 200);
    assert.strictEqual((await postJson(R + `/relay/${id}/send`, { nodeId: 'N0', data: 'later' }, bearer(tok))).status, 200);
    const recv = await req(R + `/relay/${id}/receive?node=N1`, { headers: bearer(tok) });
    assert.deepStrictEqual(recv.json.frames.map(f => f.data), [{ hello: 'mars' }], 'only the delivered frame');
    assert.strictEqual((await req(R + `/relay/${id}/receive?node[]=N1`, { headers: bearer(tok) })).status, 400);
    assert.strictEqual((await req(R + `/relay/${id}/receive?node=N0`, { headers: bearer(tok) })).json.frames.length, 0, 'sender gets none');
    assert.strictEqual((await req(R + `/relay/session/${id}`, { method: 'DELETE' })).status, 401);
    assert.strictEqual((await req(R + `/relay/session/${id}`, { method: 'DELETE', headers: bearer(tok) })).status, 200);
    assert.strictEqual((await req(R + `/relay/session/${id}`, { method: 'DELETE', headers: bearer(tok) })).status, 404);
    assert.strictEqual((await req(R + '/relay/nope')).status, 404);
  });
}

(async () => {
  const site = await startSite();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ip-relay-'));
  const demo = await startPhp(path.join(REPO, 'demo'), { TMPDIR: tmp });
  try {
    await testTime(site.base);
    await testLtx(site.base);
    await testMcpPhp(demo.base);
    await testRelayPhp(demo.base);
  } finally {
    site.stop();
    demo.stop();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
