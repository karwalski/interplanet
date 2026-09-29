'use strict';
/**
 * topics.js: Tests for the EXPERIMENTAL ltx-topics.js extension.
 * Story IP-T3 (#16). Design: docs/LTX-TOPICS-RFC.md (Draft).
 * No external test framework. Run with: node tests/topics.js
 */

const fs = require('fs');
const path = require('path');
const ltx = require('../ltx-sdk');
const topics = require('../ltx-topics');

let passed = 0;
let failed = 0;

function check(name, cond) {
  if (cond) { passed++; }
  else { failed++; console.log('FAIL:', name); }
}

function throws(fn) {
  try { fn(); return false; } catch (_) { return true; }
}

const canon = ltx.canonicalJSON;

// ── Fixtures: three nodes with real Ed25519 NIKs ──────────────────────────

const SID = 'LTX-20261001-EARTHHQ-MARS-v3-topics';
const keys = ['Earth HQ', 'Mars Hab-01', 'Luna Relay'].map(label => ltx.generateNIK({ nodeLabel: label }));
const keyCache = new Map(keys.map(k => [k.nik.nodeId, k.nik]));
const [A, B, C] = keys.map(k => ({ nodeId: k.nik.nodeId, priv: k.privateKeyB64 }));

function opts(node, seq, timestamp) {
  return { sessionId: SID, nodeId: node.nodeId, seq, timestamp, privateKeyB64: node.priv };
}

const T = n => `2026-10-01T12:${String(n).padStart(2, '0')}:00.000Z`;

// Node A creates two topics.
const tWater = topics.createTopic({ topicId: 'T-water', title: 'Water recycler', participants: [A.nodeId, B.nodeId] }, opts(A, 1, T(0)));
const tEva   = topics.createTopic({ topicId: 'T-eva', title: 'EVA schedule' }, opts(A, 2, T(1)));

// Node B posts in both topics and ships them as one batch (candidate C).
const b1 = topics.createContribution({ topicId: 'T-water', body: 'Filter pressure dropping.' }, opts(B, 1, T(2)));
const b2 = topics.createContribution({ topicId: 'T-eva', body: 'Proposing EVA on sol 12.' }, opts(B, 2, T(2)));
const batchB = topics.createBatch([b1, b2], { sessionId: SID, nodeId: B.nodeId, createdAt: T(2), privateKeyB64: B.priv });

// Concurrent replies to b1 from A and C at the same timestamp.
const a3 = topics.createContribution({ topicId: 'T-water', body: 'Swap the cartridge.', replyTo: b1.content.contributionId }, opts(A, 3, T(5)));
const c1 = topics.createContribution({ topicId: 'T-water', body: 'Check the pump first.', replyTo: b1.content.contributionId }, opts(C, 1, T(5)));

// Reply to a reply.
const b3 = topics.createContribution({ topicId: 'T-water', body: 'Cartridge swapped.', replyTo: a3.content.contributionId }, opts(B, 3, T(7)));

// Concurrent close by A and B at version 2, then reopen by C at version 3,
// then close again by A at version 4.
const aClose = topics.updateTopic({ topicId: 'T-eva', version: 2, status: 'closed' }, opts(A, 4, T(8)));
const bClose = topics.updateTopic({ topicId: 'T-eva', version: 2, status: 'closed', title: 'EVA schedule (agreed)' }, opts(B, 4, T(8)));
const cReopen = topics.updateTopic({ topicId: 'T-eva', version: 3, status: 'open' }, opts(C, 2, T(9)));
const aClose2 = topics.updateTopic({ topicId: 'T-water', version: 2, status: 'closed' }, opts(A, 5, T(10)));

// A contribution after the close is still accepted (no gating).
const c3 = topics.createContribution({ topicId: 'T-water', body: 'Late note: pump bearings worn.' }, opts(C, 3, T(11)));

const logA = [tWater, tEva, a3, aClose, aClose2];
const logB = [batchB, b3, bClose];
const logC = [c1, cReopen, c3];
const ALL = [].concat(logA, logB, logC);

function stateOf(entries) {
  const s = topics.reduceTopics(entries);
  return canon({ s, threads: { w: topics.buildThreads(s, 'T-water'), e: topics.buildThreads(s, 'T-eva') } });
}

const reference = topics.mergeTopicLogs([logA, logB, logC], keyCache);
const refState = stateOf(reference.entries);
const refReduced = topics.reduceTopics(reference.entries);

// ── Entry builders ────────────────────────────────────────────────────────

console.log('\n── Topics: entry builders ─────────────────────');
check('topic entry type',                   tWater.type === 'topic');
check('topic entryId prefix TOP-',          tWater.entryId === `TOP-${A.nodeId}-1`);
check('contribution entryId prefix CTB-',   b1.entryId === `CTB-${B.nodeId}-1`);
check('contributionId defaults to entryId', b1.content.contributionId === b1.entryId);
check('contribution signature verifies',    ltx.verifyRegisterEntry(b1, keyCache).valid === true);
check('topic_update signature verifies',    ltx.verifyRegisterEntry(aClose, keyCache).valid === true);
check('updateTopic rejects version 1',      throws(() => topics.updateTopic({ topicId: 'T-eva', version: 1 }, opts(A, 9, T(0)))));
check('updateTopic rejects bad status',     throws(() => topics.updateTopic({ topicId: 'T-eva', version: 2, status: 'locked' }, opts(A, 9, T(0)))));
check('createTopic rejects bad topicId',    throws(() => topics.createTopic({ topicId: 'bad id!', title: 'x' }, opts(A, 9, T(0)))));
check('contribution body must be non-empty', throws(() => topics.createContribution({ topicId: 'T-eva', body: '' }, opts(A, 9, T(0)))));

// ── Batches ───────────────────────────────────────────────────────────────

console.log('\n── Topics: batch envelope ─────────────────────');
const vb = topics.verifyBatch(batchB, keyCache);
check('batch verifies',                     vb.valid === true);
check('batch yields both entries',          vb.entries.length === 2 && vb.rejected.length === 0);
check('batch type topic_batch',             batchB.type === 'topic_batch' && batchB.v === 0);
check('batch rejects foreign entries',      throws(() => topics.createBatch([b1, a3], { sessionId: SID, nodeId: B.nodeId, createdAt: T(2), privateKeyB64: B.priv })));
const tamperedBatch = Object.assign({}, batchB, { createdAt: T(59) });
const vt = topics.verifyBatch(tamperedBatch, keyCache);
check('tampered batch sig invalid',         vt.valid === false && vt.reason === 'batch_signature_invalid');
check('tampered batch entries still valid', vt.entries.length === 2);
const mt = topics.mergeTopicLogs([[tamperedBatch], [tWater, tEva]], keyCache);
check('tampered batch reported',            mt.invalidBatches.length === 1);
check('entries of tampered batch merged',   mt.entries.length === 4);
const forged = Object.assign({}, b1, { content: Object.assign({}, b1.content, { body: 'forged' }) });
const mf = topics.mergeTopicLogs([[forged]], keyCache);
check('forged entry rejected',              mf.entries.length === 0 && mf.rejected[0].reason === 'signature_invalid');

// ── Reduce: topics, concurrent replies, close/reopen ──────────────────────

console.log('\n── Topics: reduce ─────────────────────────────');
check('merge keeps all 12 entries',         reference.entries.length === 12 && reference.rejected.length === 0);
check('merge order matches orderEntries',   canon(reference.entries) === canon(ltx.orderEntries(reference.entries)));
check('two topics',                         Object.keys(refReduced.byId).length === 2);
check('six contributions',                  Object.keys(refReduced.contributions).length === 6);

const lowEditor = A.nodeId < B.nodeId ? A : B;
const v2Winner = lowEditor === A ? aClose : bClose;
check('concurrent close: lowest nodeId wins at v2', refReduced.superseded.includes(lowEditor === A ? bClose.entryId : aClose.entryId));
check('v3 reopen beats both v2 closes',      refReduced.byId['T-eva'].status === 'open' && refReduced.byId['T-eva'].version === 3);
check('reopen supersedes v2 winner',         refReduced.superseded.includes(v2Winner.entryId));
check('reopen editor is C',                  refReduced.byId['T-eva'].editor === C.nodeId);
check('title from winning v2 kept iff B won', refReduced.byId['T-eva'].title === (lowEditor === B ? 'EVA schedule (agreed)' : 'EVA schedule'));
check('T-water closed at v2',                refReduced.byId['T-water'].status === 'closed');
check('contribution after close accepted',   !!refReduced.contributions[c3.content.contributionId]);
check('contribution after close flagged',    refReduced.contributions[c3.content.contributionId].afterClose === true);
check('earlier contribution not flagged',    refReduced.contributions[b1.content.contributionId].afterClose === false);
check('participants kept',                   canon(refReduced.byId['T-water'].participants) === canon([A.nodeId, B.nodeId]));

const threads = topics.buildThreads(refReduced, 'T-water');
check('two roots in T-water (b1, c3)',       threads.length === 2);
check('root is b1',                          threads[0].contributionId === b1.entryId);
check('concurrent replies both kept',        threads[0].replies.length === 2);
const expectFirst = A.nodeId < C.nodeId ? a3.entryId : c1.entryId;
check('concurrent siblings in total order',  threads[0].replies[0].contributionId === expectFirst);
const a3Node = threads[0].replies.find(r => r.contributionId === a3.entryId);
check('nested reply attached',               a3Node.replies.length === 1 && a3Node.replies[0].contributionId === b3.entryId);
check('buildThreads accepts raw entries',    canon(topics.buildThreads(ALL.filter(e => e.type !== 'topic_batch').concat(batchB.entries), 'T-water')) === canon(threads));

// ── Duplicate, out-of-order, late ─────────────────────────────────────────

console.log('\n── Topics: duplicate / out-of-order / late ────');
const dup = topics.mergeTopicLogs([logA, logA, logB, logB, logC, [b1, b1, c3]], keyCache);
check('duplicates collapse',                 dup.entries.length === 12 && dup.equivocations.length === 0);
check('duplicates give identical state',     stateOf(dup.entries) === refState);

// Deterministic shuffle (LCG) so the test is reproducible.
function shuffled(arr, seed) {
  const out = arr.slice();
  let s = seed >>> 0;
  for (let i = out.length - 1; i > 0; i--) {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    const j = s % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}
let allOrdersMatch = true;
for (let seed = 1; seed <= 25; seed++) {
  const m = topics.mergeTopicLogs(shuffled(ALL, seed).map(x => [x]), keyCache);
  if (stateOf(m.entries) !== refState) allOrdersMatch = false;
}
check('25 random delivery orders converge',  allOrdersMatch);

// Late: A's seq 1 arrives after A's seq 5 was already merged.
let late = topics.mergeTopicLogs([[aClose2, a3]], keyCache).entries;
late = topics.mergeTopicLogs([late, [tWater]], keyCache).entries;
check('late lower-seq entry merged not dropped', late.some(e => e.entryId === tWater.entryId));
const tracker = ltx.createSequenceTracker('topics-test');
tracker.recordSeq(A.nodeId, 5);
// Since IP-L4 the transport tracker accepts a late seq inside its reorder
// window but still rejects anything older than the window, so merge must not use it.
const lateSeq = tracker.recordSeq(A.nodeId, 1);
check('transport recordSeq flags in-window late seq', lateSeq.accepted === true && lateSeq.late === true);
const strict = ltx.createSequenceTracker('topics-test-strict', undefined, { reorderWindow: 0 });
strict.recordSeq(A.nodeId, 5);
check('transport recordSeq with no window drops it (why merge must not use it)', strict.recordSeq(A.nodeId, 1).accepted === false);

// Orphan: contribution before its topic.
const orphanOnly = topics.reduceTopics([b2]);
check('contribution before topic is orphan', orphanOnly.orphans.includes(b2.entryId));
check('orphan attaches when topic arrives',  !!topics.reduceTopics([b2, tEva]).contributions[b2.entryId]);

// Missing parent resolves when the parent arrives.
const noParent = topics.reduceTopics([tWater, a3]);
check('reply without parent is unresolved',  noParent.contributions[a3.entryId].parentUnresolved === true);
check('unresolved reply shown as root',      topics.buildThreads(noParent, 'T-water')[0].contributionId === a3.entryId);
const withParent = topics.reduceTopics([tWater, a3, b1]);
check('parent arrival resolves reply',       !withParent.contributions[a3.entryId].parentUnresolved);

// Reply whose parent comes LATER in total order stays unresolved (no cycles).
const fwd = topics.createContribution({ topicId: 'T-water', body: 'fwd ref', replyTo: 'CTB-future' }, opts(C, 7, T(1)));
const fut = topics.createContribution({ topicId: 'T-water', body: 'future', contributionId: 'CTB-future', replyTo: fwd.entryId }, opts(C, 8, T(3)));
const cyc = topics.reduceTopics([tWater, fwd, fut]);
check('forward reference stays unresolved',  cyc.contributions[fwd.entryId].parentUnresolved === true);
check('cycle broken deterministically',      !cyc.contributions['CTB-future'].parentUnresolved);

// Equivocation: two different entries with the same (nodeId, seq).
const eq1 = topics.createContribution({ topicId: 'T-eva', body: 'version one' }, opts(C, 20, T(20)));
const eq2 = topics.createContribution({ topicId: 'T-eva', body: 'version two' }, opts(C, 20, T(20)));
const e12 = topics.mergeTopicLogs([[eq1], [eq2]], keyCache);
const e21 = topics.mergeTopicLogs([[eq2], [eq1]], keyCache);
check('equivocation reported',               e12.equivocations.length === 1);
check('equivocation choice independent of order', canon(e12.entries) === canon(e21.entries));

// ── Partitioned delivery on three nodes ───────────────────────────────────

console.log('\n── Topics: partitioned delivery, 3 nodes ──────');
// Each node's view evolves through incremental merges. Phase 1: A and C can
// talk, B is partitioned (conjunction). Phase 2: link heals, B receives in a
// different order and with duplicates, and sends its batch.
function mergeInto(view, delivery) { return topics.mergeTopicLogs([view, delivery], keyCache).entries; }

let viewA = mergeInto([], logA);
let viewB = mergeInto([], logB);
let viewC = mergeInto([], logC);
viewA = mergeInto(viewA, logC);            // A <- C
viewC = mergeInto(viewC, logA);            // C <- A
check('during partition A and C agree',      stateOf(viewA) === stateOf(viewC));
check('during partition B differs',          stateOf(viewB) !== stateOf(viewA));
const partialC = topics.reduceTopics(viewC);
check('during partition replies to b1 are unresolved on C', partialC.contributions[c1.entryId].parentUnresolved === true);
// Heal.
viewB = mergeInto(viewB, shuffled(logA.concat(logC), 7));
viewB = mergeInto(viewB, [tWater, c3]);   // duplicates
viewA = mergeInto(viewA, [batchB]);
viewA = mergeInto(viewA, [b3, bClose]);
viewC = mergeInto(viewC, [bClose, b3]);
viewC = mergeInto(viewC, [batchB, batchB]);
check('after heal A == B',                   stateOf(viewA) === stateOf(viewB));
check('after heal B == C',                   stateOf(viewB) === stateOf(viewC));
check('after heal equals reference',         stateOf(viewA) === refState);
check('after heal logs identical',           canon(viewA) === canon(viewB) && canon(viewB) === canon(viewC));
check('after heal reply resolves on C',      !topics.reduceTopics(viewC).contributions[c1.entryId].parentUnresolved);

// ── Plans: v2 frozen, no silent upgrade, streams untouched ────────────────

console.log('\n── Topics: plan compatibility ─────────────────');
const v2 = ltx.createPlan({ title: 'Topics Test', start: '2026-10-01T12:00:00.000Z' });
const v2Json = JSON.stringify(v2);
const V2_GOLDEN = 'LTX-20261001-EARTHHQ-MARS-v2-56536fa7';
const V3_GOLDEN = 'LTX-20261001-EARTHHQ-MARS-v3-6ffe8c07';
check('v2 planId golden before',             ltx.makePlanId(v2) === V2_GOLDEN);
check('attachTopicsToPlan refuses v2',       throws(() => topics.attachTopicsToPlan(v2, [{ id: 'T1', title: 'x' }])));
const v2View = topics.renderPlanWithoutTopics(v2);
check('render view of v2 is a copy',         v2View !== v2);
topics.reduceTopics(ALL);
topics.mergeTopicLogs([logA], keyCache);
check('v2 plan object unchanged',            JSON.stringify(v2) === v2Json);
check('v2 planId golden after',              ltx.makePlanId(v2) === V2_GOLDEN);
check('v2 plan still v2',                    v2.v === 2 && v2.topics === undefined && v2.caps === undefined);
check('hasTopicsCapability(v2) false',       topics.hasTopicsCapability(v2) === false);

const v3 = ltx.upgradePlanToV3(v2);
const v3Json = JSON.stringify(v3);
check('v3 planId golden (no topics)',        ltx.makePlanId(v3) === V3_GOLDEN);
const v3t = topics.attachTopicsToPlan(v3, [
  { id: 'T-water', title: 'Water recycler' },
  { id: 'T-eva', title: 'EVA schedule', status: 'open' },
], { 1: ['T-water'], 4: ['T-eva', 'T-water'] });
check('attach returns a new plan',           v3t !== v3 && JSON.stringify(v3) === v3Json);
check('v3 planId of original unchanged',     ltx.makePlanId(v3) === V3_GOLDEN);
check('v3 with topics has new planId',       ltx.makePlanId(v3t) !== V3_GOLDEN && /-v3-/.test(ltx.makePlanId(v3t)));
check('caps includes topics/0',              topics.hasTopicsCapability(v3t) && canon(v3t.caps) === canon(['topics/0']));
check('topicRefs on segment 1',              canon(v3t.segments[1].topicRefs) === canon(['T-water']));
check('segments without refs untouched',     v3t.segments[0] === v3.segments[0]);
check('streams absent stays absent',         !('streams' in v3t));
const v3e = Object.assign({}, v3, { streams: [] });
const v3et = topics.attachTopicsToPlan(v3e, [{ id: 'T1', title: 'x' }]);
check('streams [] stays [] and same ref',    Array.isArray(v3et.streams) && v3et.streams.length === 0 && v3et.streams === v3e.streams);
check('non-empty streams refused',           throws(() => topics.attachTopicsToPlan(Object.assign({}, v3, { streams: [{ id: 'S1' }] }), [])));
check('topicRefs to unknown topic refused',  throws(() => topics.attachTopicsToPlan(v3, [{ id: 'T1', title: 'x' }], { 0: ['T9'] })));
check('recommendedTopics advisory ids',      canon(topics.recommendedTopics(v3t, 4)) === canon(['T-eva', 'T-water']));
check('recommendedTopics none for v2',       topics.recommendedTopics(v2, 1).length === 0);

const v3tJson = JSON.stringify(v3t);
const v3tId = ltx.makePlanId(v3t);
const view = topics.renderPlanWithoutTopics(v3t);
check('no-capability view drops topics',     view.topics === undefined && view.caps === undefined && view.segments[1].topicRefs === undefined);
check('no-capability view keeps segments',   view.segments.length === v3t.segments.length);
check('no-capability view never rewrites plan', JSON.stringify(v3t) === v3tJson && ltx.makePlanId(v3t) === v3tId);

const reducedKeys = JSON.stringify(topics.reduceTopics(ALL));
check('reduced state never mentions streams', !/"streams"/.test(reducedKeys));

// ── Static guards for the RFC §12 boundaries ──────────────────────────────

console.log('\n── Topics: scope guards ───────────────────────');
const src = fs.readFileSync(path.join(__dirname, '..', 'ltx-topics.js'), 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
check('no timers in ltx-topics.js',          !/setTimeout|setInterval|requestAnimationFrame/.test(src));
check('no delay/light-time inputs',          !/\.delay\b|\bdelays\b|lightTravel|pairDelay|computeSegments/.test(src));
check('never writes streams',                !/streams\s*[:=]|\.streams\s*=/.test(src));
check('module marked EXPERIMENTAL',          topics.EXPERIMENTAL === true);

// ── Summary ────────────────────────────────────────────────────────────────

console.log('\n══════════════════════════════════════════');
console.log(`${passed} passed  ${failed} failed`);

module.exports = { passed: () => passed, failed: () => failed };
if (require.main === module && failed > 0) process.exit(1);
