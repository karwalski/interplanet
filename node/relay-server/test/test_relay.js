'use strict';

/**
 * test_relay.js: relay session IDs are spec planIds (LTX-SPECIFICATION.md
 * sections 4.3 and 4.5). Feeds every golden vector in spec/golden/plan-ids.json
 * through makePlanId and through POST /relay/session, then exercises the
 * session routes with a planId holding non-ASCII node names.
 *
 * Run: node test/test_relay.js   (from node/relay-server)
 */

const path   = require('path');
const assert = require('assert');
const { server, makePlanId } = require('../server.js');

const REPO   = path.join(__dirname, '..', '..', '..');
const golden = require(path.join(REPO, 'spec', 'golden', 'plan-ids.json'));
const sdk    = require(path.join(REPO, 'javascript', 'ltx', 'ltx-sdk.js'));

let passed = 0, failed = 0;
function check(name, fn) {
  return Promise.resolve().then(fn).then(
    () => { passed++; console.log('PASS ' + name); },
    (e) => { failed++; console.log('FAIL ' + name + ': ' + e.message); }
  );
}

async function main() {
  // 1. makePlanId against the golden vectors (plans parsed from JSON text,
  //    as the server receives them).
  for (const v of golden.vectors) {
    await check('makePlanId ' + v.name, () => {
      const plan = JSON.parse(JSON.stringify(v.plan));
      assert.strictEqual(makePlanId(plan), v.planId);
    });
  }

  // 2. Same as the reference SDK for inputs outside the vectors.
  const extra = {
    v: 2, title: 'Ünïcödé 🚀', start: '2026-05-01T23:30:00-02:00', quantum: 3, mode: 'LTX-ASYNC',
    nodes: [
      { id: 'N0', name: 'Base Étoile', role: 'HOST', delay: 0, location: 'earth' },
      { id: 'N1', name: 'Ceres 🚀 Outpost', role: 'PARTICIPANT', delay: 1234.5, location: 'ceres' },
    ],
    segments: [{ type: 'TX', q: 1 }, { type: 'RX', q: 1 }],
  };
  const v1 = { title: 'Legacy', start: '2026-01-02T03:04:05Z', quantum: 5, mode: 'LTX',
    txName: 'Earth HQ', rxName: 'Moon Base', delay: 2, segments: [{ type: 'TX', q: 1 }] };
  await check('makePlanId matches ltx-sdk.js (non-ASCII, offset start)', () => {
    assert.strictEqual(makePlanId(JSON.parse(JSON.stringify(extra))), sdk.makePlanId(extra));
  });
  await check('makePlanId matches ltx-sdk.js (v1 plan upgrade)', () => {
    assert.strictEqual(makePlanId(JSON.parse(JSON.stringify(v1))), sdk.makePlanId(v1));
  });
  await check('makePlanId rejects an invalid start', () => {
    assert.throws(() => makePlanId({ v: 2, start: 'nope', nodes: [{ name: 'A' }] }));
  });

  // 3. HTTP: POST /relay/session returns the planId as sessionId.
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const base = 'http://127.0.0.1:' + server.address().port;
  const post = (p, body, token) => fetch(base + p, {
    method: 'POST',
    headers: Object.assign({ 'Content-Type': 'application/json' },
      token ? { Authorization: 'Bearer ' + token } : {}),
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });

  try {
    for (const v of golden.vectors) {
      await check('POST /relay/session ' + v.name, async () => {
        const r = await post('/relay/session', v.plan);
        const j = await r.json();
        assert.strictEqual(r.status, 200);
        assert.strictEqual(j.sessionId, v.planId);
        assert.strictEqual(j.planId, v.planId);
        const del = await fetch(base + '/relay/session/' + encodeURIComponent(j.sessionId),
          { method: 'DELETE', headers: { Authorization: 'Bearer ' + j.tls_fingerprint } });
        assert.strictEqual(del.status, 200);
      });
    }

    await check('POST /relay/session with invalid start is 400', async () => {
      const r = await post('/relay/session', { v: 2, start: 'nope', nodes: [{ id: 'N0', name: 'A' }] });
      assert.strictEqual(r.status, 400);
    });

    await check('send, receive and delete by a non-ASCII planId', async () => {
      const reg = await (await post('/relay/session', extra)).json();
      assert.strictEqual(reg.sessionId, sdk.makePlanId(extra));
      const id = encodeURIComponent(reg.sessionId);
      const sent = await post('/relay/' + id + '/send',
        { nodeId: 'N0', data: { hello: 'mars' }, timestamp_ms: Date.now() - reg.delay_ms - 1 },
        reg.tls_fingerprint);
      assert.strictEqual(sent.status, 200);
      const recv = await fetch(base + '/relay/' + id + '/receive?node=N1',
        { headers: { Authorization: 'Bearer ' + reg.tls_fingerprint } });
      const frames = (await recv.json()).frames;
      assert.strictEqual(frames.length, 1);
      assert.deepStrictEqual(frames[0].data, { hello: 'mars' });
      const noAuth = await fetch(base + '/relay/session/' + id, { method: 'DELETE' });
      assert.strictEqual(noAuth.status, 401);
      const del = await fetch(base + '/relay/session/' + id,
        { method: 'DELETE', headers: { Authorization: 'Bearer ' + reg.tls_fingerprint } });
      assert.strictEqual(del.status, 200);
      const gone = await fetch(base + '/relay/session/' + id,
        { method: 'DELETE', headers: { Authorization: 'Bearer ' + reg.tls_fingerprint } });
      assert.strictEqual(gone.status, 404);
    });

    await check('re-registering a live session needs its token (409 otherwise)', async () => {
      const reg = await (await post('/relay/session', extra)).json();
      const r1 = await post('/relay/session', extra);
      assert.strictEqual(r1.status, 409);
      const j1 = await r1.json();
      assert.strictEqual(j1.sessionId, reg.sessionId);
      assert.strictEqual(j1.tls_fingerprint, undefined);
      const r2 = await post('/relay/session', extra, 'not-the-token');
      assert.strictEqual(r2.status, 409);
      const r3 = await post('/relay/session', extra, reg.tls_fingerprint);
      assert.strictEqual(r3.status, 200);
      assert.strictEqual((await r3.json()).sessionId, reg.sessionId);
      const del = await fetch(base + '/relay/session/' + encodeURIComponent(reg.sessionId),
        { method: 'DELETE', headers: { Authorization: 'Bearer ' + reg.tls_fingerprint } });
      assert.strictEqual(del.status, 200);
    });

    await check('GET /relay/health', async () => {
      const h = await (await fetch(base + '/relay/health')).json();
      assert.strictEqual(h.status, 'ok');
      assert.strictEqual(typeof h.sessions, 'number');
    });
  } finally {
    server.close();
  }

  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed) process.exit(1);
}

main().catch(e => { console.error(e); process.exit(1); });
