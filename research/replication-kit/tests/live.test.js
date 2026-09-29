'use strict';
/**
 * live.test.js: a short live session through the relay CLI, as a researcher
 * runs it (README "Running a session"), at --time-scale 0.001 so the 10-minute
 * D10-P1 delay is 600 ms. Starts the session, checks scenario injections, a
 * delayed crew-to-ground message, an answer, SIGINT shutdown and the scorer
 * CLI on the written log. Refs #38.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const net = require('net');
const { spawn, spawnSync } = require('child_process');

const KIT = path.join(__dirname, '..');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function freePort() {
  return new Promise((resolve) => {
    const s = net.createServer();
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); });
  });
}

module.exports = async function run() {
  let passed = 0, failed = 0;
  const check = async (name, fn) => {
    try { await fn(); passed++; console.log('  PASS ' + name); }
    catch (e) { failed++; console.log('  FAIL ' + name + ': ' + e.message); }
  };
  console.log('\n── Live session: relay CLI + scorer CLI ─────');

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ip-kit-live-'));
  const log = path.join(tmp, 'T99-D10-P1.jsonl');
  const port = await freePort();
  const base = `http://127.0.0.1:${port}`;
  const relay = spawn(process.execPath, [path.join(KIT, 'relay/relay.js'), '--condition', 'D10-P1',
    '--team', 'T99', '--time-scale', '0.001', '--port', String(port), '--log', log],
    { stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  relay.stdout.on('data', (d) => { stdout += d; });
  const exited = new Promise((r) => relay.on('exit', (code, sig) => r({ code, sig })));
  const post = (p, body) => fetch(base + p, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}) }).then((r) => r.json());
  const inbox = (who) => fetch(`${base}/inbox?participant=${who}`).then((r) => r.json()).then((j) => j.messages);

  try {
    for (let i = 0; i < 50 && !stdout.includes('Participant client'); i++) await sleep(100);
    await check('relay CLI starts and serves the client and config', async () => {
      const html = await (await fetch(base + '/')).text();
      assert.ok(/<html/i.test(html));
      const cfg = await (await fetch(base + '/config')).json();
      assert.deepStrictEqual(Object.keys(cfg.roles).sort(), ['crew1', 'crew2', 'fc']);
      assert.strictEqual(cfg.protocol, true);
      assert.strictEqual(cfg.started, false);
      assert.strictEqual(cfg.delay, undefined, 'delay not exposed to participants');
    });
    await check('sending before /start is refused', async () => {
      const r = await post('/send', { from: 'crew1', to: 'ground', text: 'early' });
      assert.ok(/not started/.test(r.error));
    });
    await check('/start delivers briefings and the F1 injections', async () => {
      assert.deepStrictEqual(await post('/start'), { started: true });
      await sleep(400);   // F1 injections at 2 min x 0.001 = 120 ms
      const fc = await inbox('fc');
      assert.ok(fc.some((m) => m.from === 'sim' && /REFERENCE F1/.test(m.text)), 'ground reference');
      const crew = await inbox('crew1');
      assert.ok(crew.some((m) => /CAUTION F1/.test(m.text)), 'crew caution');
    });
    await check('a crew message reaches ground only after the one-way delay', async () => {
      const q = await post('/send', { from: 'crew1', to: 'ground', text: 'F1 fan current low, delta-P low' });
      assert.strictEqual(q.queued[0].to, 'fc');
      await sleep(150);
      assert.ok(!(await inbox('fc')).some((m) => m.from === 'crew1'), 'not yet delivered');
      await sleep(700);
      assert.ok((await inbox('fc')).some((m) => m.from === 'crew1'), 'delivered after 600 ms');
    });
    await check('a message to a same-site crew member arrives at once', async () => {
      await post('/send', { from: 'crew1', to: 'crew2', text: 'checking fan' });
      await sleep(50);
      assert.ok((await inbox('crew2')).some((m) => m.from === 'crew1'));
    });
    await check('answers are recorded; unknown senders are refused', async () => {
      assert.ok(typeof (await post('/answer', { from: 'crew1', faultId: 'F1', itemId: 'diagnosis', answer: 'fan motor degradation' })).recorded === 'number');
      assert.ok(/unknown sender/.test((await post('/answer', { from: 'eve', faultId: 'F1', itemId: 'x', answer: 'y' })).error));
    });
  } finally {
    relay.kill('SIGINT');
  }
  const ex = await exited;
  await check('SIGINT closes the session and the log', async () => {
    assert.strictEqual(ex.code, 0);
    const events = fs.readFileSync(log, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
    assert.strictEqual(events[events.length - 1].event, 'session_end');
    assert.ok(events.some((e) => e.event === 'answer'));
  });
  await check('scorer CLI scores the live log', async () => {
    const out = path.join(tmp, 'result.json');
    const r = spawnSync(process.execPath, [path.join(KIT, 'scoring/score.js'), '--log', log,
      '--scenario', path.join(KIT, 'scenarios/co2-removal.json'), '--out', out], { encoding: 'utf8' });
    assert.strictEqual(r.status, 0, r.stderr);
    const res = JSON.parse(fs.readFileSync(out, 'utf8'));
    assert.strictEqual(res.teamId, 'T99');
    assert.strictEqual(res.conditionId, 'D10-P1');
    assert.ok(JSON.stringify(res).includes('F1'));
  });
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`\nlive session: ${passed} passed  ${failed} failed`);
  return { passed, failed };
};

if (require.main === module) module.exports().then((r) => process.exit(r.failed ? 1 : 0));
