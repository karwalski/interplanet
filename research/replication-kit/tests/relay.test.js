'use strict';
/**
 * relay.test.js — Tests for the delay-injecting relay (IP-R2, Refs #19)
 * Uses short real delays (tens of milliseconds). Run: node tests/relay.test.js
 */

const http = require('http');
const path = require('path');
const relayLib = require('../relay/relay');

let passed = 0;
let failed = 0;
function check(name, cond) {
  if (cond) { passed++; }
  else { failed++; console.log('FAIL:', name); }
}
const wait = ms => new Promise(r => setTimeout(r, ms));

function request(port, method, p, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : '';
    const req = http.request({ host: '127.0.0.1', port, method, path: p,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } }, res => {
      let s = '';
      res.on('data', c => { s += c; });
      res.on('end', () => resolve({ status: res.statusCode, body: s ? JSON.parse(s) : null }));
    });
    req.on('error', reject);
    req.end(data);
  });
}

async function main() {
  // ── Pure delay logic ──
  console.log('\n── Relay: pure delay logic ──────────────────');
  const R = relayLib.DEFAULT_ROLES;
  check('same site has no delay', relayLib.linkDelayMs('crew1', 'crew2', R, 600000) === 0);
  check('cross site has one-way delay', relayLib.linkDelayMs('crew1', 'fc', R, 600000) === 600000);
  check('unknown role throws', (() => { try { relayLib.linkDelayMs('x', 'fc', R, 1); return false; } catch (e) { return true; } })());

  let d = relayLib.computeDelivery(1000, 300000, [], 'hold');
  check('plain delay', d.deliverMs === 301000 && d.heldMs === 0 && !d.dropped);
  const win = [{ startMs: 100, endMs: 200 }];
  d = relayLib.computeDelivery(50, 100, win, 'hold');
  check('arrival in outage is held to end', d.deliverMs === 200 && d.heldMs === 50);
  d = relayLib.computeDelivery(0, 100, win, 'hold');
  check('arrival exactly at outage start is held', d.deliverMs === 200);
  d = relayLib.computeDelivery(100, 100, win, 'hold');
  check('arrival at outage end is not held', d.deliverMs === 200 && d.heldMs === 0);
  d = relayLib.computeDelivery(50, 100, win, 'drop');
  check('drop mode loses message', d.dropped && d.deliverMs === null);
  d = relayLib.computeDelivery(0, 20, win, 'drop');
  check('drop mode keeps message outside outage', !d.dropped && d.deliverMs === 20);
  d = relayLib.computeDelivery(50, 100, [{ startMs: 200, endMs: 300 }, { startMs: 100, endMs: 200 }], 'hold');
  check('adjacent outages chain', d.deliverMs === 300 && d.heldMs === 150);

  const s = relayLib.conditionToSettings({ oneWayDelayMin: 20, protocol: true,
    interruptions: [{ startMin: 30, endMin: 50 }] }, 0.001);
  check('condition minutes scaled to ms', s.oneWayDelayMs === 1200 && s.interruptions[0].startMs === 1800
    && s.interruptions[0].endMs === 3000 && s.protocol && s.interruptionMode === 'hold');
  const conditions = require('../conditions.json');
  const ids = conditions.conditions.map(c => c.id);
  check('conditions cover 0/5/10/20 x protocol',
    [0, 5, 10, 20].every(m => [false, true].every(p =>
      conditions.conditions.some(c => c.oneWayDelayMin === m && c.protocol === p && !c.interruptions))));
  check('interrupted condition present', ids.includes('D10-P0-INT') && ids.includes('D10-P1-INT'));

  // ── Live relay with short delays ──
  console.log('\n── Relay: timed delivery ────────────────────');
  const events = [];
  const relay = relayLib.createRelay({
    oneWayDelayMs: 80, interruptions: [{ startMs: 150, endMs: 260 }], interruptionMode: 'hold',
    protocol: true, teamId: 'T-test', conditionId: 'test', log: ev => events.push(ev),
    injections: [{ id: 'i1', faultId: 'F1', atMs: 10, to: 'spacecraft', text: 'CAUTION F1' }],
  });
  const got = { crew1: [], crew2: [], fc: [] };
  for (const r of Object.keys(got)) relay.subscribe(r, m => got[r].push(Object.assign({ at: relay.elapsedMs() }, m)));
  check('send before start throws', (() => { try { relay.send('crew1', 'fc', 'x'); return false; } catch (e) { return true; } })());
  relay.start();
  check('start is idempotent', relay.start() === false);
  relay.send('crew1', 'fc', 'to ground');
  relay.send('crew1', 'crew2', 'to crewmate');
  check('crewmate message immediate', got.crew2.length === 1 && got.crew2[0].text === 'to crewmate');
  check('ground message not yet delivered', got.fc.length === 0);
  await wait(40);
  check('injection delivered to both crew', got.crew1.some(m => m.from === 'sim') && got.crew2.some(m => m.from === 'sim'));
  check('injection not delivered to ground', !got.fc.some(m => m.from === 'sim'));
  check('ground message still held at ~40ms', got.fc.length === 0);
  await wait(70);
  check('ground message delivered after delay', got.fc.length === 1 && got.fc[0].at >= 80);
  // Sent at ~110ms, would arrive ~190ms, inside outage [150, 260): held until 260.
  relay.send('fc', 'all', 'to crew during outage');
  await wait(120);
  check('outage message still held at ~230ms', got.crew1.filter(m => m.from === 'fc').length === 0);
  await wait(80);
  const c1 = got.crew1.filter(m => m.from === 'fc');
  check('outage message delivered after outage end', c1.length === 1 && c1[0].at >= 260);
  check('broadcast reached crew2 too', got.crew2.some(m => m.from === 'fc'));
  check('broadcast not echoed to sender', got.fc.every(m => m.from !== 'fc'));
  relay.answer('crew2', 'F1', 'diagnosis', 'fan motor degradation');
  relay.close();

  const kinds = events.map(e => e.event);
  check('log has session_start', kinds[0] === 'session_start');
  check('log has interruption events', kinds.includes('interruption_start') && kinds.includes('interruption_end'));
  check('log has inject', kinds.includes('inject'));
  check('log has answer', events.some(e => e.event === 'answer' && e.itemId === 'diagnosis'));
  check('log has session_end', kinds[kinds.length - 1] === 'session_end');
  const heldSends = events.filter(e => e.event === 'send' && e.heldMs > 0);
  check('held sends logged with heldMs', heldSends.length === 2);
  check('every event has team and condition', events.every(e => e.teamId === 'T-test' && e.conditionId === 'test'));
  check('every event is JSON-serialisable', events.every(e => JSON.parse(JSON.stringify(e)).event === e.event));

  // ── Drop mode ──
  const ev2 = [];
  const dropRelay = relayLib.createRelay({ oneWayDelayMs: 30, interruptions: [{ startMs: 0, endMs: 100 }],
    interruptionMode: 'drop', log: e => ev2.push(e) });
  const fcGot = [];
  dropRelay.subscribe('fc', m => fcGot.push(m));
  dropRelay.start();
  dropRelay.send('crew1', 'fc', 'lost');
  await wait(60);
  dropRelay.close();
  check('drop mode: nothing delivered', fcGot.length === 0);
  check('drop mode: drop logged', ev2.some(e => e.event === 'drop'));

  // ── HTTP + SSE ──
  console.log('\n── Relay: HTTP and SSE ──────────────────────');
  const logFile = path.join(require('os').tmpdir(), `relay-test-${process.pid}.jsonl`);
  const httpRelay = relayLib.createRelay({ oneWayDelayMs: 50, protocol: false, log: logFile,
    teamId: 'T-http', conditionId: 'http' });
  const server = relayLib.createServer(httpRelay);
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  const cfg = await request(port, 'GET', '/config');
  check('config hides delay', cfg.status === 200 && cfg.body.oneWayDelayMs === undefined && cfg.body.roles.fc);
  const early = await request(port, 'POST', '/send', { from: 'crew1', to: 'fc', text: 'x' });
  check('send before start is 400', early.status === 400);
  await request(port, 'POST', '/start');
  const sse = [];
  const sseReq = http.get({ host: '127.0.0.1', port, path: '/events?participant=fc' }, res => {
    res.setEncoding('utf8');
    res.on('data', c => { for (const m of c.matchAll(/data: (.*)\n\n/g)) sse.push(JSON.parse(m[1])); });
  });
  await wait(20);
  const sent = await request(port, 'POST', '/send', { from: 'crew2', to: 'fc', text: 'hello ground' });
  check('send returns queued copy', sent.status === 200 && sent.body.queued.length === 1);
  const bad = await request(port, 'POST', '/send', { from: 'crew2', to: 'nobody', text: 'x' });
  check('unknown recipient is 400', bad.status === 400);
  await wait(20);
  check('SSE has nothing before delay', sse.length === 0);
  await wait(60);
  check('SSE delivers after delay', sse.length === 1 && sse[0].text === 'hello ground');
  const inbox = await request(port, 'GET', '/inbox?participant=fc');
  check('inbox lists delivered message', inbox.body.messages.length === 1);
  const ans = await request(port, 'POST', '/answer', { from: 'fc', faultId: 'F1', itemId: 'procedure', answer: 'LS-7' });
  check('answer recorded', ans.status === 200);
  sseReq.destroy();
  httpRelay.close();
  await new Promise(r => server.close(r));
  const fileEvents = require('fs').readFileSync(logFile, 'utf8').trim().split('\n').map(l => JSON.parse(l));
  require('fs').unlinkSync(logFile);
  check('JSONL file written', fileEvents.length >= 5 && fileEvents[0].event === 'session_start');
  check('JSONL has client_connect', fileEvents.some(e => e.event === 'client_connect'));

  console.log('\n══════════════════════════════════════════');
  console.log(`relay: ${passed} passed  ${failed} failed`);
  return { passed, failed };
}

module.exports = main;
if (require.main === module) main().then(r => { if (r.failed) process.exit(1); });
