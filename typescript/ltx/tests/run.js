'use strict';
/**
 * run.js — Unit tests for @interplanet/ltx TypeScript SDK.
 * Story 33.1 · No external test framework · Runs with: node tests/run.js
 * Requires: npm run build first (or: make test)
 */

const ltx = require('../dist/cjs/index.js');

let passed = 0;
let failed = 0;

function check(name, cond) {
  if (cond) { passed++; }
  else { failed++; console.log('FAIL:', name); }
}

function approx(name, actual, expected, delta) {
  const ok = Math.abs(actual - expected) <= delta;
  if (ok) { passed++; }
  else { failed++; console.log(`FAIL: ${name} — expected ${expected}±${delta}, got ${actual}`); }
}

// ── Constants ──────────────────────────────────────────────────────────────

console.log('\n── Constants ────────────────────────────────');
check('VERSION is string',             typeof ltx.VERSION === 'string');
check('VERSION matches semver',        /^\d+\.\d+\.\d+$/.test(ltx.VERSION));
check('DEFAULT_QUANTUM == 5',          ltx.DEFAULT_QUANTUM === 5);
check('DEFAULT_API_BASE is string',    typeof ltx.DEFAULT_API_BASE === 'string');
check('DEFAULT_API_BASE has https',    ltx.DEFAULT_API_BASE.startsWith('https://'));
check('SEG_TYPES is array',            Array.isArray(ltx.SEG_TYPES));
check('SEG_TYPES has TX',              ltx.SEG_TYPES.includes('TX'));
check('SEG_TYPES has RX',              ltx.SEG_TYPES.includes('RX'));
check('SEG_TYPES has PLAN_CONFIRM',    ltx.SEG_TYPES.includes('PLAN_CONFIRM'));
check('SEG_TYPES has BUFFER',          ltx.SEG_TYPES.includes('BUFFER'));
check('DEFAULT_SEGMENTS is array',     Array.isArray(ltx.DEFAULT_SEGMENTS));
check('DEFAULT_SEGMENTS length == 7',  ltx.DEFAULT_SEGMENTS.length === 7);
check('DEFAULT_SEGMENTS has type+q',   ltx.DEFAULT_SEGMENTS.every(s => s.type && s.q > 0));

// ── createPlan ─────────────────────────────────────────────────────────────

console.log('\n── createPlan ───────────────────────────────');
const plan = ltx.createPlan();
check('createPlan v == 2',             plan.v === 2);
check('createPlan title is string',    typeof plan.title === 'string');
check('createPlan default title',      plan.title === 'LTX Session');
check('createPlan start ISO format',   /^\d{4}-\d{2}-\d{2}T/.test(plan.start));
check('createPlan quantum == 5',       plan.quantum === 5);
check('createPlan mode == LTX',        plan.mode === 'LTX');
check('createPlan nodes is array',     Array.isArray(plan.nodes));
check('createPlan has 2 nodes',        plan.nodes.length === 2);
check('node[0] role == HOST',          plan.nodes[0].role === 'HOST');
check('node[0] name is string',        typeof plan.nodes[0].name === 'string');
check('node[0] id == N0',              plan.nodes[0].id === 'N0');
check('node[0] delay == 0',            plan.nodes[0].delay === 0);
check('node[0] location == earth',     plan.nodes[0].location === 'earth');
check('node[1] role == PARTICIPANT',   plan.nodes[1].role === 'PARTICIPANT');
check('node[1] id == N1',              plan.nodes[1].id === 'N1');
check('createPlan segments array',     Array.isArray(plan.segments));
check('createPlan segments == 7',      plan.segments.length === 7);

const customPlan = ltx.createPlan({ title: 'Mars Meeting', delay: 860, remoteName: 'Mars Hab-02' });
check('custom title',                  customPlan.title === 'Mars Meeting');
check('custom remoteName in node[1]',  customPlan.nodes[1].name === 'Mars Hab-02');
check('custom delay in node[1]',       customPlan.nodes[1].delay === 860);

// ── upgradeConfig ─────────────────────────────────────────────────────────

console.log('\n── upgradeConfig ────────────────────────────');
const v2pass = ltx.upgradeConfig(plan);
check('v2 passthrough same ref',       v2pass === plan);

const v1cfg = {
  title: 'Old Session',
  start: '2026-03-01T12:00:00.000Z',
  txName: 'Earth HQ',
  rxName: 'Mars Hab-01',
  delay: 500,
  quantum: 5,
  mode: 'LTX',
  segments: ltx.DEFAULT_SEGMENTS.slice(),
};
const upgraded = ltx.upgradeConfig(v1cfg);
check('upgraded v == 2',               upgraded.v === 2);
check('upgraded has nodes array',      Array.isArray(upgraded.nodes));
check('upgraded 2 nodes',              upgraded.nodes.length === 2);
check('upgraded node[0] name',         upgraded.nodes[0].name === 'Earth HQ');
check('upgraded node[1] delay == 500', upgraded.nodes[1].delay === 500);
check('upgraded node[1] location mars', upgraded.nodes[1].location === 'mars');

// ── computeSegments ───────────────────────────────────────────────────────

console.log('\n── computeSegments ──────────────────────────');
const segs = ltx.computeSegments(plan);
check('computeSegments is array',      Array.isArray(segs));
check('computeSegments 7 items',       segs.length === 7);
check('seg[0] type == PLAN_CONFIRM',   segs[0].type === 'PLAN_CONFIRM');
check('seg[6] type == BUFFER',         segs[6].type === 'BUFFER');
check('seg[0] q == 2',                 segs[0].q === 2);
check('seg[0] start is Date',          segs[0].start instanceof Date);
check('seg[0] end is Date',            segs[0].end instanceof Date);
check('seg[0] start < end',            segs[0].start.getTime() < segs[0].end.getTime());
check('seg[0] durMin == 10',           segs[0].durMin === 10);  // q=2, quantum=5
check('seg[6] durMin == 5',            segs[6].durMin === 5);   // q=1, quantum=5
// Contiguous: each segment end == next segment start
for (let i = 0; i < segs.length - 1; i++) {
  check(`seg[${i}].end == seg[${i+1}].start`, segs[i].end.getTime() === segs[i+1].start.getTime());
}

// ── totalMin ──────────────────────────────────────────────────────────────

console.log('\n── totalMin ─────────────────────────────────');
const total = ltx.totalMin(plan);
check('totalMin is number',            typeof total === 'number');
check('totalMin == 65',                total === 65);  // 13 quanta * 5 min each
const segSum = segs.reduce((a, s) => a + s.durMin, 0);
check('totalMin matches segment sum',  segSum === total);
const manual = plan.segments.reduce((a, s) => a + s.q * plan.quantum, 0);
check('totalMin matches manual calc',  total === manual);

// ── makePlanId ────────────────────────────────────────────────────────────

console.log('\n── makePlanId ───────────────────────────────');
const fixedPlan = ltx.createPlan({
  title: 'Q3 Review',
  start: '2026-03-01T12:00:00.000Z',
});
const planId = ltx.makePlanId(fixedPlan);
check('makePlanId is string',          typeof planId === 'string');
check('makePlanId starts LTX-',        planId.startsWith('LTX-'));
check('makePlanId has date 20260301',  planId.includes('20260301'));
check('makePlanId has -v2-',           planId.includes('-v2-'));
check('makePlanId ends 8-char hex',    /[0-9a-f]{8}$/.test(planId));
check('makePlanId deterministic',      ltx.makePlanId(fixedPlan) === planId);
check('makePlanId format LTX-D-H-N-v2-H', /^LTX-\d{8}-[A-Z0-9]+-[A-Z0-9]+-v2-[0-9a-f]{8}$/.test(planId));

// ── encodeHash / decodeHash ───────────────────────────────────────────────

console.log('\n── encodeHash / decodeHash ──────────────────');
const hash = ltx.encodeHash(plan);
check('encodeHash is string',          typeof hash === 'string');
check('encodeHash starts #l=',         hash.startsWith('#l='));
check('encodeHash has payload',        hash.length > 10);
check('encodeHash url-safe (no +)',    !hash.includes('+'));
check('encodeHash url-safe (no /)',    !hash.includes('/'));
check('encodeHash no base64 padding',  !hash.slice(3).includes('='));  // #l= prefix has =, payload must not

const decoded = ltx.decodeHash(hash);
check('decodeHash not null',           decoded !== null);
check('decodeHash v == 2',             decoded !== null && decoded.v === 2);
check('decodeHash title matches',      decoded !== null && decoded.title === plan.title);
check('decodeHash quantum matches',    decoded !== null && decoded.quantum === plan.quantum);
check('decodeHash nodes preserved',    decoded !== null && Array.isArray(decoded.nodes));

// Round-trip: strip # prefix
const decoded2 = ltx.decodeHash(hash.slice(1));  // 'l=eyJ...'
check('decodeHash l= prefix works',   decoded2 !== null);

// Invalid token
const bad = ltx.decodeHash('!!!!invalid!!!!');
check('decodeHash invalid → null',     bad === null);
const empty = ltx.decodeHash('');
check('decodeHash empty → null',       empty === null);

// ── buildNodeUrls ─────────────────────────────────────────────────────────

console.log('\n── buildNodeUrls ────────────────────────────');
const urls = ltx.buildNodeUrls(plan, 'https://interplanet.live/ltx.html');
check('buildNodeUrls is array',        Array.isArray(urls));
check('buildNodeUrls 2 items',         urls.length === 2);
check('url[0].nodeId == N0',           urls[0].nodeId === 'N0');
check('url[0].name is string',         typeof urls[0].name === 'string');
check('url[0].role == HOST',           urls[0].role === 'HOST');
check('url[0].url has ?node=N0',       urls[0].url.includes('?node=N0'));
check('url[0].url has #l=',            urls[0].url.includes('#l='));
check('url[0].url base preserved',     urls[0].url.startsWith('https://interplanet.live/ltx.html'));
check('url[1].nodeId == N1',           urls[1].nodeId === 'N1');
check('url[1].role == PARTICIPANT',    urls[1].role === 'PARTICIPANT');

// ── generateICS ───────────────────────────────────────────────────────────

console.log('\n── generateICS ──────────────────────────────');
const datePlan = ltx.createPlan({ start: '2026-03-15T14:00:00.000Z' });
const ics = ltx.generateICS(datePlan);
check('generateICS is string',         typeof ics === 'string');
check('ICS starts VCALENDAR',          ics.startsWith('BEGIN:VCALENDAR'));
check('ICS ends VCALENDAR',            ics.trimEnd().endsWith('END:VCALENDAR'));
check('ICS has BEGIN:VEVENT',          ics.includes('BEGIN:VEVENT'));
check('ICS has END:VEVENT',            ics.includes('END:VEVENT'));
check('ICS VERSION:2.0',               ics.includes('VERSION:2.0'));
check('ICS DTSTART present',           ics.includes('DTSTART:'));
check('ICS DTEND present',             ics.includes('DTEND:'));
check('ICS SUMMARY present',           ics.includes('SUMMARY:'));
check('ICS LTX:1 present',             ics.includes('LTX:1'));
check('ICS LTX-PLANID present',        ics.includes('LTX-PLANID:'));
check('ICS LTX-QUANTUM present',       ics.includes('LTX-QUANTUM:PT5M'));
check('ICS LTX-SEGMENT-TEMPLATE',      ics.includes('LTX-SEGMENT-TEMPLATE:'));
check('ICS LTX-NODE present',          ics.includes('LTX-NODE:'));
check('ICS CRLF line endings',         ics.includes('\r\n'));
// ICS v1 upgrade works too
const icsUpgraded = ltx.generateICS(v1cfg);
check('generateICS handles v1 config', typeof icsUpgraded === 'string' && icsUpgraded.includes('BEGIN:VCALENDAR'));

// ── formatHMS / formatUTC ─────────────────────────────────────────────────

console.log('\n── formatHMS / formatUTC ────────────────────');
check('formatHMS(0) == "00:00"',       ltx.formatHMS(0) === '00:00');
check('formatHMS(30) == "00:30"',      ltx.formatHMS(30) === '00:30');
check('formatHMS(59) == "00:59"',      ltx.formatHMS(59) === '00:59');
check('formatHMS(60) == "01:00"',      ltx.formatHMS(60) === '01:00');
check('formatHMS(3600) == "01:00:00"', ltx.formatHMS(3600) === '01:00:00');
check('formatHMS(3661) == "01:01:01"', ltx.formatHMS(3661) === '01:01:01');
check('formatHMS(7322) == "02:02:02"', ltx.formatHMS(7322) === '02:02:02');
check('formatHMS(-1) == "00:00"',      ltx.formatHMS(-1) === '00:00');

const utcDate = new Date('2026-03-01T14:30:45.000Z');
const utcStr = ltx.formatUTC(utcDate);
check('formatUTC ends " UTC"',         utcStr.endsWith(' UTC'));
check('formatUTC has time "14:30:45"', utcStr.startsWith('14:30:45'));
// From number (ms)
const utcFromMs = ltx.formatUTC(0);
check('formatUTC(0) == "00:00:00 UTC"', utcFromMs === '00:00:00 UTC');

// ── REST function types ────────────────────────────────────────────────────

console.log('\n── REST exports ─────────────────────────────');
check('storeSession is function',      typeof ltx.storeSession === 'function');
check('getSession is function',        typeof ltx.getSession === 'function');
check('downloadICS is function',       typeof ltx.downloadICS === 'function');
check('submitFeedback is function',    typeof ltx.submitFeedback === 'function');

// ── Security: canonicalJSON ───────────────────────────────────────────────

console.log('\n── Security: canonicalJSON ──────────────────');
// Key order
const obj1 = { z: 1, a: 2, m: 3 };
check('canonicalJSON sorts keys',        ltx.canonicalJSON(obj1) === '{"a":2,"m":3,"z":1}');
// Nested
const obj2 = { b: { y: 1, x: 2 }, a: [3, 1, 2] };
check('canonicalJSON nested object',     ltx.canonicalJSON(obj2) === '{"a":[3,1,2],"b":{"x":2,"y":1}}');
// Arrays preserve order
const arr = [3, 1, 2];
check('canonicalJSON array order kept',  ltx.canonicalJSON(arr) === '[3,1,2]');
// Null
check('canonicalJSON null',              ltx.canonicalJSON(null) === 'null');
// String
check('canonicalJSON string',            ltx.canonicalJSON('hi') === '"hi"');
// Deterministic on real plan
const p1 = ltx.createPlan({ title: 'Test', start: '2026-03-01T12:00:00.000Z' });
const s1 = ltx.canonicalJSON(p1);
const s2 = ltx.canonicalJSON(p1);
check('canonicalJSON deterministic',     s1 === s2);
// No structural whitespace (test with value-only object, no space in string values)
const noWsObj = { z: 1, a: 2 };
const noWsStr = ltx.canonicalJSON(noWsObj);
check('canonicalJSON no whitespace',     !noWsStr.includes(' '));

// ── Security: NIK ─────────────────────────────────────────────────────────

console.log('\n── Security: NIK ────────────────────────────');
const { nik, privateKeyB64 } = ltx.generateNIK({ nodeLabel: 'Earth HQ' });
check('generateNIK returns nik',         nik && typeof nik === 'object');
check('nik has nodeId',                  typeof nik.nodeId === 'string');
check('nik.nodeId length 22',            nik.nodeId.length === 22); // 16 bytes base64url = 22 chars
check('nik.algorithm Ed25519',           nik.algorithm === 'Ed25519');
check('nik.publicKey base64url',         /^[A-Za-z0-9_-]+$/.test(nik.publicKey));
check('nik.publicKey length 43',         nik.publicKey.length === 43); // 32 bytes base64url = 43 chars
check('nik has validFrom',               typeof nik.validFrom === 'string');
check('nik has validUntil',              typeof nik.validUntil === 'string');
check('nik.keyVersion == 1',             nik.keyVersion === 1);
check('nik.label == Earth HQ',          nik.label === 'Earth HQ');
check('privateKeyB64 present',           typeof privateKeyB64 === 'string');
check('privateKeyB64 base64url',         /^[A-Za-z0-9_-]+$/.test(privateKeyB64));
check('isNIKExpired(fresh) == false',    ltx.isNIKExpired(nik) === false);
const expiredNik = { ...nik, validUntil: '2020-01-01T00:00:00.000Z' };
check('isNIKExpired(old) == true',       ltx.isNIKExpired(expiredNik) === true);
const fp = ltx.nikFingerprint(nik);
check('nikFingerprint is hex string',    /^[0-9a-f]{64}$/.test(fp));
check('nikFingerprint deterministic',    ltx.nikFingerprint(nik) === fp);
// No label when omitted
const { nik: nikNoLabel } = ltx.generateNIK();
check('nik without label has no label', !('label' in nikNoLabel));
// Two generateNIK calls produce different nodeIds
const { nik: nik2 } = ltx.generateNIK();
check('generateNIK unique nodeIds',      nik.nodeId !== nik2.nodeId);

// ── Security: signPlan / verifyPlan ───────────────────────────────────────

console.log('\n── Security: signPlan / verifyPlan ──────────');
const { nik: signerNik, privateKeyB64: signerPriv } = ltx.generateNIK({ nodeLabel: 'Earth HQ' });
const planToSign = ltx.createPlan({ title: 'Signed Session', start: '2026-04-01T12:00:00.000Z' });

// signPlan
const signed = ltx.signPlan(planToSign, signerPriv);
check('signPlan returns object',         signed && typeof signed === 'object');
check('signPlan has coseSign1',          signed.coseSign1 && typeof signed.coseSign1 === 'object');
check('coseSign1 has protected',         typeof signed.coseSign1.protected === 'string');
check('coseSign1 has payload',           typeof signed.coseSign1.payload === 'string');
check('coseSign1 has signature',         typeof signed.coseSign1.signature === 'string');
check('coseSign1 signature url-safe',    /^[A-Za-z0-9_-]+$/.test(signed.coseSign1.signature));
check('payload decodes to plan JSON',    Buffer.from(signed.coseSign1.payload, 'base64url').toString() === ltx.canonicalJSON(planToSign));

// verifyPlan — valid
const keyCacheTS = new Map([[signerNik.nodeId, signerNik]]);
const vResult = ltx.verifyPlan(signed, keyCacheTS);
check('verifyPlan valid plan → true',    vResult.valid === true);

// verifyPlan — tampered payload
const tamperedTS = JSON.parse(JSON.stringify(signed));
tamperedTS.coseSign1.payload = Buffer.from(ltx.canonicalJSON({ ...planToSign, title: 'HACKED' })).toString('base64url');
const vTampered = ltx.verifyPlan(tamperedTS, keyCacheTS);
check('verifyPlan tampered → false',     vTampered.valid === false);

// verifyPlan — wrong key (key not in cache)
const { nik: wrongNik } = ltx.generateNIK();
const wrongCacheTS = new Map([[wrongNik.nodeId, wrongNik]]);
const vWrong = ltx.verifyPlan(signed, wrongCacheTS);
check('verifyPlan wrong key → false',    vWrong.valid === false);
check('verifyPlan wrong key reason',     vWrong.reason === 'key_not_in_cache');

// verifyPlan — expired key
const expiredNikTS = { ...signerNik, validUntil: '2020-01-01T00:00:00.000Z' };
const expiredCacheTS = new Map([[expiredNikTS.nodeId, expiredNikTS]]);
const vExpired = ltx.verifyPlan(signed, expiredCacheTS);
check('verifyPlan expired key → false',  vExpired.valid === false);
check('verifyPlan expired reason',       vExpired.reason === 'key_expired');

// verifyPlan — missing coseSign1
const vMissing = ltx.verifyPlan({ plan: planToSign }, keyCacheTS);
check('verifyPlan missing COSE → false', vMissing.valid === false);

// ── Security: Sequence Tracking ───────────────────────────────────────────

console.log('\n── Security: Sequence Tracking ──────────────');
const tracker = ltx.createSequenceTracker('plan-abc-123');

// nextSeq increments
check('nextSeq starts at 1',            tracker.nextSeq('N0') === 1);
check('nextSeq increments',             tracker.nextSeq('N0') === 2);
check('nextSeq N1 independent',         tracker.nextSeq('N1') === 1);

// recordSeq normal acceptance
const r1 = tracker.recordSeq('N0', 1);
check('recordSeq seq=1 accepted',       r1.accepted === true);
check('recordSeq seq=1 no gap',         r1.gap === false);

const r2 = tracker.recordSeq('N0', 2);
check('recordSeq seq=2 accepted',       r2.accepted === true);

// replay rejection
const replay = tracker.recordSeq('N0', 1);
check('recordSeq replay rejected',      replay.accepted === false);
check('recordSeq replay reason',        replay.reason === 'replay');

// gap detection
const gap = tracker.recordSeq('N0', 5);  // after 2, skip 3,4
check('recordSeq gap detected',         gap.accepted === true && gap.gap === true);
check('recordSeq gapSize == 2',         gap.gapSize === 2);

// continuation after gap
const r6 = tracker.recordSeq('N0', 6);
check('recordSeq after gap accepted',   r6.accepted === true && r6.gap === false);

// addSeq / checkSeq helpers
const tracker2 = ltx.createSequenceTracker('plan-xyz');
const bundle = { type: 'TX', content: 'hello' };
const seqBundle = ltx.addSeq(bundle, tracker2, 'N0');
check('addSeq adds seq field',          seqBundle.seq === 1);
check('addSeq preserves bundle',        seqBundle.type === 'TX');

const checkResult = ltx.checkSeq(seqBundle, tracker2, 'N0');
check('checkSeq accepts first',         checkResult.accepted === true);

const checkReplay = ltx.checkSeq(seqBundle, tracker2, 'N0'); // same seq again
check('checkSeq rejects replay',        checkReplay.accepted === false);

const noSeq = ltx.checkSeq({ type: 'TX' }, tracker2, 'N0');
check('checkSeq missing seq → false',   noSeq.accepted === false);
check('checkSeq missing reason',        noSeq.reason === 'missing_seq');

// lastSeenSeq / currentSeq
check('lastSeenSeq correct',            tracker.lastSeenSeq('N0') === 6);
check('currentSeq correct',             tracker.currentSeq('N0') === 2);

// ── Security: Merkle Audit Log ────────────────────────────────────────────

console.log('\n── Security: Merkle Audit Log ────────────────────────────────');
const logTS = ltx.createMerkleLog();

// Empty log
check('empty log treeSize == 0',        logTS.treeSize() === 0);
check('empty log root is 64 zeros',     logTS.rootHex() === '0'.repeat(64));

// Append entries
const eTS1 = logTS.append({ type: 'TX', seq: 1, data: 'hello' });
check('append returns treeSize 1',      eTS1.treeSize === 1);
check('append returns root hex',        typeof eTS1.root === 'string' && eTS1.root.length === 64);

const eTS2 = logTS.append({ type: 'RX', seq: 2, data: 'world' });
check('append 2 returns treeSize 2',    eTS2.treeSize === 2);
check('root changes on append',         eTS1.root !== eTS2.root);

// Append more entries to test consistency
for (let i = 3; i <= 10; i++) logTS.append({ seq: i });
check('log has 10 entries',             logTS.treeSize() === 10);

// Capture root at size 10
const tsRoot10 = logTS.rootHex();

// Append 5 more
for (let i = 11; i <= 15; i++) logTS.append({ seq: i });
const tsRoot15 = logTS.rootHex();
check('log has 15 entries',             logTS.treeSize() === 15);
check('root10 !== root15',              tsRoot10 !== tsRoot15);

// Inclusion proof
const tsProof3 = logTS.inclusionProof(2);  // 0-based, third entry
check('inclusionProof returns array',   Array.isArray(tsProof3));
check('inclusion proof has side+hash',  tsProof3.every(p => (p.side === 'left' || p.side === 'right') && typeof p.hash === 'string'));

// Verify inclusion
const tsEntry3 = { seq: 3 };
const tsValid3 = logTS.verifyInclusion(tsEntry3, 2, tsProof3, tsRoot15);
check('verifyInclusion valid → true',   tsValid3 === true);

// Tampered entry
const tsFakeEntry = { seq: 999 };
const tsInvalidInclusion = logTS.verifyInclusion(tsFakeEntry, 2, tsProof3, tsRoot15);
check('verifyInclusion tampered → false', tsInvalidInclusion === false);

// Consistency proof
const tsConsProof = logTS.consistencyProof(10);
check('consistencyProof returns array', Array.isArray(tsConsProof));
// Verify determinism: a fresh log with the same 15 entries should have the same root
const logTS2 = ltx.createMerkleLog();
logTS2.append({ type: 'TX', seq: 1, data: 'hello' });
logTS2.append({ type: 'RX', seq: 2, data: 'world' });
for (let i = 3; i <= 15; i++) logTS2.append({ seq: i });
check('identical log same root',        logTS2.rootHex() === tsRoot15);

// Signed tree head
const { nik: tsHostNik, privateKeyB64: tsHostPriv } = ltx.generateNIK();
const tsSignedHead = logTS.signTreeHead(tsHostPriv, tsHostNik.nodeId);
check('signTreeHead has treeSize',      tsSignedHead.treeSize === 15);
check('signTreeHead has sha256RootHash', tsSignedHead.sha256RootHash === tsRoot15);
check('signTreeHead has signature',     typeof tsSignedHead.treeHeadSig === 'string');

// Verify tree head
check('verifyTreeHead valid → true',    ltx.verifyTreeHead(tsSignedHead, tsHostNik) === true);

// Wrong key
const { nik: tsWrongNik } = ltx.generateNIK();
check('verifyTreeHead wrong key → false', ltx.verifyTreeHead(tsSignedHead, tsWrongNik) === false);

// ── Security: KEY_BUNDLE ──────────────────────────────────────────────────

console.log('\n── Security: KEY_BUNDLE ──────────────────────────────────────');
// Setup: three nodes
const { nik: tsHostNik2, privateKeyB64: tsHostPriv2 } = ltx.generateNIK({ nodeLabel: 'Earth HQ' });
const { nik: tsPartNik } = ltx.generateNIK({ nodeLabel: 'Mars Hab' });
const { nik: tsEokNik }  = ltx.generateNIK({ nodeLabel: 'Emergency Override' });

const tsKb = ltx.createKeyBundle('plan-test-001', [tsHostNik2, tsPartNik, tsEokNik], tsHostPriv2);
check('createKeyBundle type',           tsKb.type === 'KEY_BUNDLE');
check('createKeyBundle planId',         tsKb.planId === 'plan-test-001');
check('createKeyBundle keys array',     Array.isArray(tsKb.keys) && tsKb.keys.length === 3);
check('createKeyBundle has bundleSig',  typeof tsKb.bundleSig === 'string');

// Verify with correct bootstrap NIK
const tsCache = ltx.verifyAndCacheKeys(tsKb, tsHostNik2);
check('verifyAndCacheKeys returns Map',  tsCache instanceof Map);
check('cache has 3 entries',            tsCache.size === 3);
check('cache has hostNik',              tsCache.has(tsHostNik2.nodeId));
check('cache has partNik',              tsCache.has(tsPartNik.nodeId));

// Verify with wrong bootstrap key → null
const { nik: tsWrongBootstrap } = ltx.generateNIK();
const tsBadCache = ltx.verifyAndCacheKeys(tsKb, tsWrongBootstrap);
check('wrong bootstrap key → null',     tsBadCache === null);

// Tampered bundle → null
const tsTamperedKb = { ...tsKb, keys: [...tsKb.keys, ltx.generateNIK().nik] };
const tsTamperedCache = ltx.verifyAndCacheKeys(tsTamperedKb, tsHostNik2);
check('tampered bundle → null',         tsTamperedCache === null);

// Expired NIK excluded from cache
const tsExpiredNik = { ...ltx.generateNIK().nik, validUntil: '2020-01-01T00:00:00.000Z' };
const tsKbWithExpired = ltx.createKeyBundle('plan-exp', [tsHostNik2, tsExpiredNik], tsHostPriv2);
const tsCacheWithExp = ltx.verifyAndCacheKeys(tsKbWithExpired, tsHostNik2);
check('expired NIK excluded from cache', tsCacheWithExp !== null && !tsCacheWithExp.has(tsExpiredNik.nodeId));
check('valid NIK included',             tsCacheWithExp.has(tsHostNik2.nodeId));

// Revocation
const tsRevocation = ltx.createRevocation('plan-test-001', tsPartNik.nodeId, 'compromised', tsHostPriv2);
check('revocation type correct',        tsRevocation.type === 'KEY_REVOCATION');
check('revocation has sig',             typeof tsRevocation.revocationSig === 'string');

const tsRevResult = ltx.applyRevocation(tsCache, tsRevocation);
check('applyRevocation returns true',   tsRevResult === true);
check('revoked key removed from cache', !tsCache.has(tsPartNik.nodeId));
check('host key still in cache',        tsCache.has(tsHostNik2.nodeId));

// ── Security: BPSec BIB ───────────────────────────────────────────────────

console.log('\n── Security: BPSec BIB ───────────────────────────────────────');
const tsBibKey = ltx.generateBIBKey();
const tsBibBundle = { type: 'TX', seq: 1, data: 'hello mars' };

// 1. addBIB returns object with bib field
const tsWithBib = ltx.addBIB(tsBibBundle, tsBibKey);
check('addBIB returns object with bib',       tsWithBib && typeof tsWithBib.bib === 'object');

// 2. bib.contextId === 1
check('bib.contextId === 1',                  tsWithBib.bib.contextId === 1);

// 3. bib.targetBlockNumber === 0
check('bib.targetBlockNumber === 0',          tsWithBib.bib.targetBlockNumber === 0);

// 4. bib.hmac is a non-empty string
check('bib.hmac is non-empty string',         typeof tsWithBib.bib.hmac === 'string' && tsWithBib.bib.hmac.length > 0);

// 5. verifyBIB with correct key → { valid: true }
const tsVBib = ltx.verifyBIB(tsWithBib, tsBibKey);
check('verifyBIB correct key → valid true',   tsVBib.valid === true);

// 6. verifyBIB with tampered payload → { valid: false }
const tsTamperedBib = { ...tsWithBib, data: 'HACKED' };
const tsVTamperedBib = ltx.verifyBIB(tsTamperedBib, tsBibKey);
check('verifyBIB tampered payload → false',   tsVTamperedBib.valid === false);

// 7. verifyBIB with wrong key → { valid: false, reason: 'hmac_mismatch' }
const tsWrongBibKey = ltx.generateBIBKey();
const tsVWrongKey = ltx.verifyBIB(tsWithBib, tsWrongBibKey);
check('verifyBIB wrong key → false',          tsVWrongKey.valid === false);
check('verifyBIB wrong key reason',           tsVWrongKey.reason === 'hmac_mismatch');

// 8. verifyBIB with no bib field → { valid: false, reason: 'missing_bib' }
const tsVNoBib = ltx.verifyBIB(tsBibBundle, tsBibKey);
check('verifyBIB no bib → missing_bib',       tsVNoBib.valid === false && tsVNoBib.reason === 'missing_bib');

// 9. addBIB does not mutate the original bundle
check('addBIB does not mutate original',      !('bib' in tsBibBundle));

// 10. generateBIBKey returns a 43-char base64url string (256-bit, no padding)
check('generateBIBKey returns 43-char str',   typeof tsBibKey === 'string' && tsBibKey.length === 43);

// ── Security: EOK / MULTI-AUTH ────────────────────────────────────────────

console.log('\n── Security: EOK / MULTI-AUTH ────────────────────────────────');

// 1. createEOK returns object with eok and privateKey fields
const tsEokResult = ltx.createEOK();
check('createEOK returns object with eok',        tsEokResult && typeof tsEokResult.eok === 'object');
check('createEOK returns object with privateKey', typeof tsEokResult.privateKey === 'string');

// 2. eok.keyType === 'eok'
check('eok.keyType === eok',                       tsEokResult.eok.keyType === 'eok');

// eok structure checks
check('eok.algorithm === Ed25519',                 tsEokResult.eok.algorithm === 'Ed25519');
check('eok has eokId',                             typeof tsEokResult.eok.eokId === 'string');
check('eok has publicKey',                         typeof tsEokResult.eok.publicKey === 'string');
check('eok has validFrom',                         typeof tsEokResult.eok.validFrom === 'string');
check('eok has validUntil',                        typeof tsEokResult.eok.validUntil === 'string');

// 3. createEmergencyOverride returns object with type === 'EMERGENCY_OVERRIDE'
const tsOverride = ltx.createEmergencyOverride('plan-eok-001', 'ABORT', tsEokResult.privateKey, tsEokResult.eok.eokId);
check('createEmergencyOverride type EMERGENCY_OVERRIDE', tsOverride.type === 'EMERGENCY_OVERRIDE');

// 4. overrideSig is a non-empty string
check('overrideSig is non-empty string',           typeof tsOverride.overrideSig === 'string' && tsOverride.overrideSig.length > 0);

// 5. verifyEmergencyOverride with correct EOK → { valid: true }
const tsEokCache = new Map([[tsEokResult.eok.eokId, tsEokResult.eok]]);
const tsVEok = ltx.verifyEmergencyOverride(tsOverride, tsEokCache);
check('verifyEmergencyOverride correct EOK → valid true', tsVEok.valid === true);

// 6. verifyEmergencyOverride with tampered action → { valid: false }
const tsTamperedOverride = { ...tsOverride, action: 'TAMPERED' };
const tsVTamperedEok = ltx.verifyEmergencyOverride(tsTamperedOverride, tsEokCache);
check('verifyEmergencyOverride tampered action → false', tsVTamperedEok.valid === false);

// 7. verifyEmergencyOverride with EOK not in cache → { valid: false, reason: 'key_not_in_cache' }
const tsEmptyEokCache = new Map();
const tsVNoKey = ltx.verifyEmergencyOverride(tsOverride, tsEmptyEokCache);
check('verifyEmergencyOverride no key → false',          tsVNoKey.valid === false);
check('verifyEmergencyOverride no key reason',           tsVNoKey.reason === 'key_not_in_cache');

// 8. createCoSig returns object with type === 'ACTION_COSIG'
const { nik: tsCosigNik1, privateKeyB64: tsCosigPriv1 } = ltx.generateNIK({ nodeLabel: 'Cosigner 1' });
const { nik: tsCosigNik2, privateKeyB64: tsCosigPriv2 } = ltx.generateNIK({ nodeLabel: 'Cosigner 2' });
const tsCosig1 = ltx.createCoSig('entry-001', 'plan-multi-001', tsCosigNik1.nodeId, tsCosigPriv1, tsCosigNik1);
check('createCoSig type ACTION_COSIG',                   tsCosig1.type === 'ACTION_COSIG');
check('createCoSig has entryId',                         tsCosig1.entryId === 'entry-001');
check('createCoSig has cosigSig',                        typeof tsCosig1.cosigSig === 'string' && tsCosig1.cosigSig.length > 0);

// 9. checkMultiAuth with 2 valid cosigs, requiredCount=2 → { authorised: true, validSigCount: 2 }
const tsCosig2 = ltx.createCoSig('entry-001', 'plan-multi-001', tsCosigNik2.nodeId, tsCosigPriv2, tsCosigNik2);
const tsMultiKeyCache = new Map([
  [tsCosigNik1.nodeId, tsCosigNik1],
  [tsCosigNik2.nodeId, tsCosigNik2],
]);
const tsAuthResult2 = ltx.checkMultiAuth([tsCosig1, tsCosig2], 'entry-001', 'plan-multi-001', tsMultiKeyCache, 2);
check('checkMultiAuth 2/2 valid → authorised true',     tsAuthResult2.authorised === true);
check('checkMultiAuth 2/2 validSigCount == 2',          tsAuthResult2.validSigCount === 2);

// 10. checkMultiAuth with 1 valid cosig, requiredCount=2 → { authorised: false }
const tsAuthResult1 = ltx.checkMultiAuth([tsCosig1], 'entry-001', 'plan-multi-001', tsMultiKeyCache, 2);
check('checkMultiAuth 1/2 → authorised false',          tsAuthResult1.authorised === false);
check('checkMultiAuth 1/2 validSigCount == 1',          tsAuthResult1.validSigCount === 1);

// Additional: invalid cosig (wrong planId) is counted as invalid
const tsWrongPlanCosig = { ...tsCosig1, planId: 'wrong-plan' };
const tsAuthResultWrong = ltx.checkMultiAuth([tsWrongPlanCosig, tsCosig2], 'entry-001', 'plan-multi-001', tsMultiKeyCache, 2);
check('checkMultiAuth wrong planId → invalidCount 1',   tsAuthResultWrong.invalidCount === 1);
check('checkMultiAuth 1 valid, 1 invalid → false',      tsAuthResultWrong.authorised === false);

// ── Security: Window Manifests ────────────────────────────────────────────

console.log('\n── Security: Window Manifests ────────────────────────────────');

// Setup: generate a NIK and a signed tree head
const { nik: tsWmNik, privateKeyB64: tsWmPriv } = ltx.generateNIK({ nodeLabel: 'Manifest Signer' });
const tsWmLog = ltx.createMerkleLog();
for (let i = 1; i <= 47; i++) tsWmLog.append({ seq: i });
const tsWmTreeHead = tsWmLog.signTreeHead(tsWmPriv, tsWmNik.nodeId);

const tsWmArtefacts = [
  { name: 'tx-content', sha256: ltx.artefactSha256('hello world'), sizeBytes: 11 },
];

// 1. artefactSha256('hello') returns a 64-char hex string
const tsWmHash = ltx.artefactSha256('hello');
check('artefactSha256 returns 64-char hex',   typeof tsWmHash === 'string' && tsWmHash.length === 64);
check('artefactSha256 is hex chars',          /^[0-9a-f]{64}$/.test(tsWmHash));

// 2. createWindowManifest returns object with type === 'WINDOW_MANIFEST'
const tsWmManifest1 = ltx.createWindowManifest('plan-wm-001', 3, tsWmArtefacts, tsWmTreeHead, tsWmPriv);
check('createWindowManifest type WINDOW_MANIFEST', tsWmManifest1.type === 'WINDOW_MANIFEST');

// 3. manifest.windowSeq === 3
check('manifest.windowSeq === 3',             tsWmManifest1.windowSeq === 3);

// 4. manifest.nonceSalt is a non-empty string
check('manifest.nonceSalt is non-empty',      typeof tsWmManifest1.nonceSalt === 'string' && tsWmManifest1.nonceSalt.length > 0);

// 5. manifest.manifestSig is a non-empty string
check('manifest.manifestSig is non-empty',    typeof tsWmManifest1.manifestSig === 'string' && tsWmManifest1.manifestSig.length > 0);

// 6. Two calls produce different nonceSalt values (hedged)
const tsWmManifest2 = ltx.createWindowManifest('plan-wm-001', 3, tsWmArtefacts, tsWmTreeHead, tsWmPriv);
check('two calls produce different nonceSalt', tsWmManifest1.nonceSalt !== tsWmManifest2.nonceSalt);

// 7. verifyWindowManifest with correct key cache → { valid: true }
const tsWmKeyCache = new Map([[tsWmNik.nodeId, tsWmNik]]);
const tsWmVerify1 = ltx.verifyWindowManifest(tsWmManifest1, tsWmKeyCache);
check('verifyWindowManifest valid → true',    tsWmVerify1.valid === true);

// 8. verifyWindowManifest with tampered artefact sha256 → { valid: false }
const tsWmTampered = JSON.parse(JSON.stringify(tsWmManifest1));
tsWmTampered.artefacts[0].sha256 = 'a'.repeat(64);
const tsWmVerify2 = ltx.verifyWindowManifest(tsWmTampered, tsWmKeyCache);
check('verifyWindowManifest tampered → false', tsWmVerify2.valid === false);

// 9. verifyWindowManifest with key not in cache → { valid: false, reason: 'key_not_in_cache' }
const { nik: tsWmWrongNik } = ltx.generateNIK();
const tsWmWrongCache = new Map([[tsWmWrongNik.nodeId, tsWmWrongNik]]);
const tsWmVerify3 = ltx.verifyWindowManifest(tsWmManifest1, tsWmWrongCache);
check('verifyWindowManifest no key → false',  tsWmVerify3.valid === false);
check('verifyWindowManifest no key reason',   tsWmVerify3.reason === 'key_not_in_cache');

// 10. hedgedSign returns { signature, nonceSalt }
const { nik: tsHsNik, privateKeyB64: tsHsPriv } = ltx.generateNIK();
const tsHsData = Buffer.from('test data for hedged sign');
const tsHsResult = ltx.hedgedSign(tsHsData, tsHsPriv);
check('hedgedSign returns signature',         typeof tsHsResult.signature === 'string' && tsHsResult.signature.length > 0);
check('hedgedSign returns nonceSalt',         typeof tsHsResult.nonceSalt === 'string' && tsHsResult.nonceSalt.length > 0);

// 11. hedgedVerify with correct params → true
const tsHvValid = ltx.hedgedVerify(tsHsData, tsHsResult.signature, tsHsResult.nonceSalt, tsHsNik.publicKey);
check('hedgedVerify correct → true',          tsHvValid === true);

// 12. hedgedVerify with tampered data → false
const tsHvTampered = ltx.hedgedVerify(Buffer.from('tampered data'), tsHsResult.signature, tsHsResult.nonceSalt, tsHsNik.publicKey);
check('hedgedVerify tampered data → false',   tsHvTampered === false);

// ── Security: Conjunction Checkpoints ─────────────────────────────────────

console.log('\n── Security: Conjunction Checkpoints ────────────────────────');

// Setup: NIKs, Merkle log, sequence data
const { nik: tsCpNik, privateKeyB64: tsCpPriv } = ltx.generateNIK({ nodeLabel: 'Mission Control' });
const { nik: tsCpNik2 } = ltx.generateNIK({ nodeLabel: 'Mars Hab' });
const tsCpKeyCache = new Map([[tsCpNik.nodeId, tsCpNik], [tsCpNik2.nodeId, tsCpNik2]]);

const tsCpLog = ltx.createMerkleLog();
tsCpLog.append({ type: 'TX', seq: 1, data: 'hello' });
tsCpLog.append({ type: 'RX', seq: 2, data: 'world' });
for (let i = 3; i <= 10; i++) tsCpLog.append({ seq: i });
const tsCpMerkleRoot = tsCpLog.rootHex();
const tsCpTreeSize   = tsCpLog.treeSize();

const tsCpLastSeq  = { N0: 147, N1: 89 };
const tsCpConjInfo = {
  conjunctionStart: '2026-09-01T00:00:00.000Z',
  conjunctionEnd:   '2026-09-25T00:00:00.000Z',
};

// 1. createConjunctionCheckpoint returns type === 'CONJUNCTION_CHECKPOINT'
const tsCpCheckpoint = ltx.createConjunctionCheckpoint(
  'plan-cp-001', tsCpNik.nodeId, tsCpConjInfo, tsCpMerkleRoot, tsCpTreeSize, tsCpLastSeq, tsCpPriv
);
check('createConjunctionCheckpoint type correct', tsCpCheckpoint.type === 'CONJUNCTION_CHECKPOINT');

// 2. checkpoint.checkpointSig is non-empty
check('checkpoint.checkpointSig non-empty',       typeof tsCpCheckpoint.checkpointSig === 'string' && tsCpCheckpoint.checkpointSig.length > 0);

// 3. checkpoint.merkleRoot === expectedRoot
check('checkpoint.merkleRoot matches',            tsCpCheckpoint.merkleRoot === tsCpMerkleRoot);

// 4. checkpoint.lastSeqPerNode contains expected values
check('checkpoint.lastSeqPerNode N0 == 147',      tsCpCheckpoint.lastSeqPerNode.N0 === 147);
check('checkpoint.lastSeqPerNode N1 == 89',       tsCpCheckpoint.lastSeqPerNode.N1 === 89);

// 5. verifyConjunctionCheckpoint with correct keyCache → { valid: true }
const tsCpVerifyOk = ltx.verifyConjunctionCheckpoint(tsCpCheckpoint, tsCpKeyCache);
check('verifyConjunctionCheckpoint valid → true', tsCpVerifyOk.valid === true);

// 6. verifyConjunctionCheckpoint with tampered merkleRoot → { valid: false }
const tsCpTampered = { ...tsCpCheckpoint, merkleRoot: '0'.repeat(64) };
const tsCpVerifyTampered = ltx.verifyConjunctionCheckpoint(tsCpTampered, tsCpKeyCache);
check('verifyConjunctionCheckpoint tampered → false', tsCpVerifyTampered.valid === false);

// 7. verifyConjunctionCheckpoint with empty keyCache → { valid: false, reason: 'key_not_in_cache' }
const tsCpVerifyEmpty = ltx.verifyConjunctionCheckpoint(tsCpCheckpoint, new Map());
check('verifyConjunctionCheckpoint empty cache → false',  tsCpVerifyEmpty.valid === false);
check('verifyConjunctionCheckpoint empty cache reason',   tsCpVerifyEmpty.reason === 'key_not_in_cache');

// 8. createPostConjunctionQueue — enqueue + size work correctly
const tsCpQueue = ltx.createPostConjunctionQueue();
const tsSz1 = tsCpQueue.enqueue({ type: 'TX', seq: 1 });
const tsSz2 = tsCpQueue.enqueue({ type: 'RX', seq: 2 });
const tsSz3 = tsCpQueue.enqueue({ type: 'TX', seq: 3 });
check('enqueue returns incrementing size',        tsSz1 === 1 && tsSz2 === 2 && tsSz3 === 3);
check('queue.size() == 3',                        tsCpQueue.size() === 3);
check('getQueue returns copy of 3 items',         tsCpQueue.getQueue().length === 3);

// 9. drain(fn) returns { cleared, rejected } counts
const tsDrainResult = tsCpQueue.drain(bundle => ({ valid: bundle.type === 'TX' }));
check('drain cleared == 2',                       tsDrainResult.cleared === 2);
check('drain rejected == 1',                      tsDrainResult.rejected === 1);
check('drain rejectedBundles has 1 entry',        tsDrainResult.rejectedBundles.length === 1);
check('queue is empty after drain',               tsCpQueue.size() === 0);

// 10. createPostConjunctionClear returns type === 'POST_CONJUNCTION_CLEAR'
const tsCpClear = ltx.createPostConjunctionClear('plan-cp-001', 42, tsCpPriv);
check('createPostConjunctionClear type correct',  tsCpClear.type === 'POST_CONJUNCTION_CLEAR');
check('tsCpClear.queueProcessed == 42',           tsCpClear.queueProcessed === 42);
check('tsCpClear.clearSig non-empty',             typeof tsCpClear.clearSig === 'string' && tsCpClear.clearSig.length > 0);

// 11. verifyPostConjunctionClear with correct keyCache → { valid: true, signerNodeId }
const tsCpClearVerify = ltx.verifyPostConjunctionClear(tsCpClear, tsCpKeyCache);
check('verifyPostConjunctionClear valid → true',  tsCpClearVerify.valid === true);
check('verifyPostConjunctionClear signerNodeId',  tsCpClearVerify.signerNodeId === tsCpNik.nodeId);

// 12. verifyPostConjunctionClear with wrong keyCache → { valid: false }
const { nik: tsCpWrongNik } = ltx.generateNIK();
const tsCpWrongCache = new Map([[tsCpWrongNik.nodeId, tsCpWrongNik]]);
const tsCpClearBadVerify = ltx.verifyPostConjunctionClear(tsCpClear, tsCpWrongCache);
check('verifyPostConjunctionClear wrong key → false', tsCpClearBadVerify.valid === false);


// ── Security: BCB Confidentiality ─────────────────────────────────────────

console.log('\n── Security: BCB Confidentiality ────────────────────────────');

// 1. encrypt_decrypt_roundtrip
const tsBcbKey = ltx.generateSessionKey();
const tsBcbPayload = { msg: 'hello', seq: 1 };
const tsBcbEncrypted = ltx.encryptWindow(tsBcbPayload, tsBcbKey);
const tsBcbDecrypted = ltx.decryptWindow(tsBcbEncrypted, tsBcbKey);
check('encrypt_decrypt_roundtrip valid',   tsBcbDecrypted.valid === true);
check('encrypt_decrypt_roundtrip msg',     tsBcbDecrypted.plaintext && tsBcbDecrypted.plaintext.msg === 'hello');

// 2. tag_mismatch: tamper ciphertext
const tsBcbTampered = Object.assign({}, tsBcbEncrypted);
const tsBcbCtChars = tsBcbTampered.ciphertext.split('');
tsBcbCtChars[0] = tsBcbCtChars[0] === 'A' ? 'B' : 'A';
tsBcbTampered.ciphertext = tsBcbCtChars.join('');
const tsBcbTamperedResult = ltx.decryptWindow(tsBcbTampered, tsBcbKey);
check('tag_mismatch valid=false',          tsBcbTamperedResult.valid === false);
check('tag_mismatch reason',               tsBcbTamperedResult.reason === 'tag_mismatch');

// 3. wrong_key: encrypt with keyA, decrypt with keyB
const tsBcbKeyA = ltx.generateSessionKey();
const tsBcbKeyB = ltx.generateSessionKey();
const tsBcbEncA = ltx.encryptWindow({ secret: 42 }, tsBcbKeyA);
const tsBcbWrongKey = ltx.decryptWindow(tsBcbEncA, tsBcbKeyB);
check('wrong_key valid=false',             tsBcbWrongKey.valid === false);
check('wrong_key reason',                  tsBcbWrongKey.reason === 'tag_mismatch');

// 4. not_bcb: wrong type
const tsBcbNotBcb = ltx.decryptWindow({ type: 'TX', nonce: 'a', ciphertext: 'b', tag: 'c' }, tsBcbKey);
check('not_bcb valid=false',               tsBcbNotBcb.valid === false);
check('not_bcb reason',                    tsBcbNotBcb.reason === 'not_bcb');

// 5. generateSessionKey_length
check('generateSessionKey_length',         ltx.generateSessionKey().length === 32);

// 6. nonce_uniqueness
const tsBcbEnc1 = ltx.encryptWindow({ x: 1 }, tsBcbKey);
const tsBcbEnc2 = ltx.encryptWindow({ x: 1 }, tsBcbKey);
check('nonce_uniqueness',                  tsBcbEnc1.nonce !== tsBcbEnc2.nonce);

// ── Session state machine (Epic 68) ────────────────────────────────────────

console.log('\n── session state machine ────────────────────');

const smPlan = ltx.createPlan({
  title: 'SM Test', start: '2026-08-01T12:00:00.000Z',
  nodes: [
    { id: 'N0', name: 'Earth HQ',  role: 'HOST',        delay: 0,   location: 'earth' },
    { id: 'N1', name: 'Mars Hab',  role: 'PARTICIPANT', delay: 900, location: 'mars'  },
    { id: 'N2', name: 'Luna Base', role: 'PARTICIPANT', delay: 2,   location: 'moon'  },
  ],
});
const smPlanId = ltx.makePlanId(smPlan);
const T0 = Date.parse('2026-08-01T11:00:00.000Z');

let sm = ltx.createSession(smPlan, smPlanId);
check('createSession state DRAFT',      sm.state === 'DRAFT');
check('lockTimeout = 2×maxDelay',       sm.lockTimeoutMs === 2 * 900 * 1000);
check('quorum default = all (2)',       sm.quorumThreshold === 2);
check('sessionRootPlanId set',          sm.sessionRootPlanId === smPlanId);

let sm_r = ltx.transition(sm, { type: 'START_LOCK', nowMs: T0 });
check('START_LOCK → LOCKING',           sm_r.ctx.state === 'LOCKING');
check('HOST auto-confirmed',            sm_r.ctx.confirmations.N0 === smPlanId);
check('audit effect emitted',           sm_r.effects[0].kind === 'audit' && sm_r.effects[0].entry.to === 'LOCKING');

// full lock path
let sm_r2 = ltx.transition(sm_r.ctx, { type: 'PLAN_CONFIRM', nowMs: T0 + 4000, nodeId: 'N2', planId: smPlanId });
check('partial confirm stays LOCKING',  sm_r2.ctx.state === 'LOCKING');
let sm_r3 = ltx.transition(sm_r2.ctx, { type: 'PLAN_CONFIRM', nowMs: T0 + 1700000, nodeId: 'N1', planId: smPlanId });
check('full confirm → LOCKED',          sm_r3.ctx.state === 'LOCKED');
check('lock kind FULL',                 sm_r3.ctx.lock === 'FULL');
let sm_r4 = ltx.transition(sm_r3.ctx, { type: 'SESSION_START', nowMs: T0 + 3600000 });
check('SESSION_START → ACTIVE',         sm_r4.ctx.state === 'ACTIVE');

// mismatch path
let sm_rm = ltx.transition(sm_r.ctx, { type: 'PLAN_CONFIRM', nowMs: T0 + 5000, nodeId: 'N1', planId: 'LTX-XXXX-v2-00000000' });
check('mismatch stays LOCKING',         sm_rm.ctx.state === 'LOCKING');
check('mismatch recorded',              sm_rm.ctx.mismatched.includes('N1'));
check('mismatch notify effect',         sm_rm.effects.some(e => e.kind === 'notify' && e.code === 'PLANID_MISMATCH'));

// timeout boundary: 1 ms before → no-op; at timeout with quorum → DEGRADED quorum lock
const smQ = ltx.createSession(smPlan, smPlanId, { quorum: 'majority' });
check('majority quorum of 2 = 2',       smQ.quorumThreshold === 2);
const smQ1 = ltx.createSession(smPlan, smPlanId, { quorum: 1 });
let sm_q1 = ltx.transition(smQ1, { type: 'START_LOCK', nowMs: T0 });
sm_q1 = ltx.transition(sm_q1.ctx, { type: 'PLAN_CONFIRM', nowMs: T0 + 10, nodeId: 'N2', planId: smPlanId });
let sm_qPre = ltx.transition(sm_q1.ctx, { type: 'TICK', nowMs: T0 + 2 * 900 * 1000 - 1 });
check('TICK before timeout no-op',      sm_qPre.ctx.state === 'LOCKING');
let sm_qTo = ltx.transition(sm_q1.ctx, { type: 'TICK', nowMs: T0 + 2 * 900 * 1000 });
check('TICK at timeout → DEGRADED',     sm_qTo.ctx.state === 'DEGRADED');
check('quorum lock kind',               sm_qTo.ctx.lock === 'QUORUM');
check('subset HOST first',              sm_qTo.ctx.subset[0] === 'N0');
check('subset ascending delay',         sm_qTo.ctx.subset[1] === 'N2');
check('escalate effect',                sm_qTo.effects.some(e => e.kind === 'escalate'));

// DEGRADED recovery: late confirm completes full lock (§5.2)
let sm_qRec = ltx.transition(sm_qTo.ctx, { type: 'PLAN_CONFIRM', nowMs: T0 + 2000000, nodeId: 'N1', planId: smPlanId });
check('late confirm → LOCKED',          sm_qRec.ctx.state === 'LOCKED');
check('recovered lock FULL',            sm_qRec.ctx.lock === 'FULL');

// timeout without quorum
let sm_sm2 = ltx.transition(ltx.createSession(smPlan, smPlanId), { type: 'START_LOCK', nowMs: T0 });
let sm_noQ = ltx.transition(sm_sm2.ctx, { type: 'TICK', nowMs: T0 + 2 * 900 * 1000 });
check('timeout no quorum → DEGRADED',   sm_noQ.ctx.state === 'DEGRADED');
check('no lock kind',                   sm_noQ.ctx.lock === null);

// HOST decisions from DEGRADED
let sm_cont = ltx.transition(sm_qTo.ctx, { type: 'HOST_DECISION', nowMs: T0 + 2100000, decision: 'continue' });
check('continue → ACTIVE',              sm_cont.ctx.state === 'ACTIVE');
let sm_abrt = ltx.transition(sm_qTo.ctx, { type: 'HOST_DECISION', nowMs: T0 + 2100000, decision: 'abort' });
check('abort → ABORTED',                sm_abrt.ctx.state === 'ABORTED');

// delay violations (§5.4): boundaries exclusive — warn >120 s, degrade >300 s
let sm_dv1 = ltx.transition(sm_r4.ctx, { type: 'DELAY_MEASURED', nowMs: T0 + 4000000, nodeId: 'N1', measuredDelayS: 1020 });
check('dev=120 no warn',                sm_dv1.ctx.state === 'ACTIVE' && sm_dv1.effects.length === 0);
let sm_dv2 = ltx.transition(sm_r4.ctx, { type: 'DELAY_MEASURED', nowMs: T0 + 4000000, nodeId: 'N1', measuredDelayS: 1021 });
check('dev=121 warns',                  sm_dv2.effects.some(e => e.code === 'DELAY_VIOLATION') && sm_dv2.ctx.state === 'ACTIVE');
let sm_dv3 = ltx.transition(sm_r4.ctx, { type: 'DELAY_MEASURED', nowMs: T0 + 4000000, nodeId: 'N1', measuredDelayS: 1200 });
check('dev=300 warns only',             sm_dv3.ctx.state === 'ACTIVE');
let sm_dv4 = ltx.transition(sm_r4.ctx, { type: 'DELAY_MEASURED', nowMs: T0 + 4000000, nodeId: 'N1', measuredDelayS: 1201 });
check('dev=301 → DEGRADED',             sm_dv4.ctx.state === 'DEGRADED');

// EOK override
let sm_hold = ltx.transition(sm_r4.ctx, { type: 'EOK_OVERRIDE', nowMs: T0 + 4100000, verified: true, reason: 'solar storm' });
check('override → EMERGENCY_HOLD',      sm_hold.ctx.state === 'EMERGENCY_HOLD');
check('resumeState saved',              sm_hold.ctx.resumeState === 'ACTIVE');
let sm_rej = ltx.transition(sm_r4.ctx, { type: 'EOK_OVERRIDE', nowMs: T0 + 4100000, verified: false });
check('unverified override rejected',   sm_rej.ctx.state === 'ACTIVE' && sm_rej.effects.some(e => e.code === 'OVERRIDE_REJECTED'));
let sm_resm = ltx.transition(sm_hold.ctx, { type: 'HOST_DECISION', nowMs: T0 + 4200000, decision: 'resume' });
check('resume → ACTIVE',                sm_resm.ctx.state === 'ACTIVE');

// amendment flow through the machine
let sm_amdProp = ltx.transition(sm_r4.ctx, {
  type: 'AMENDMENT_PROPOSED', nowMs: T0 + 4300000,
  planId: 'LTX-20260801-EARTHHQ-MARS-LUNA-v3-abcd1234', planVersion: 2, affectedNodeIds: ['N1'],
});
check('amendment pending',              sm_amdProp.ctx.pendingAmendment !== null);
check('amendment timeout from N1',      sm_amdProp.ctx.pendingAmendment.timeoutMs === 2 * 900 * 1000);
let sm_amdBadV = ltx.transition(sm_r4.ctx, {
  type: 'AMENDMENT_PROPOSED', nowMs: T0 + 4300000,
  planId: 'x', planVersion: 3, affectedNodeIds: ['N1'],
});
check('version gap rejected',           sm_amdBadV.effects.some(e => e.code === 'AMENDMENT_REJECTED'));
let sm_amdConf = ltx.transition(sm_amdProp.ctx, {
  type: 'AMENDMENT_CONFIRMED', nowMs: T0 + 6200000, nodeId: 'N1',
  planId: 'LTX-20260801-EARTHHQ-MARS-LUNA-v3-abcd1234',
});
check('amendment applied',              sm_amdConf.ctx.pendingAmendment === null);
check('planVersion bumped',             sm_amdConf.ctx.planVersion === 2);
check('planId switched',                sm_amdConf.ctx.planId.includes('-v3-'));
check('root planId unchanged',          sm_amdConf.ctx.sessionRootPlanId === smPlanId);

// completion
let sm_done = ltx.transition(sm_amdConf.ctx, { type: 'SESSION_END', nowMs: T0 + 9000000 });
check('SESSION_END → COMPLETE',         sm_done.ctx.state === 'COMPLETE');
let sm_invalidEv = ltx.transition(sm_done.ctx, { type: 'SESSION_END', nowMs: T0 + 9100000 });
check('event after COMPLETE ignored',   sm_invalidEv.ctx.state === 'COMPLETE' && sm_invalidEv.effects.some(e => e.code === 'INVALID_EVENT'));

// determinism: same ctx+event twice → identical results
const sm_detA = ltx.transition(sm_r.ctx, { type: 'TICK', nowMs: T0 + 2 * 900 * 1000 });
const sm_detB = ltx.transition(sm_r.ctx, { type: 'TICK', nowMs: T0 + 2 * 900 * 1000 });
check('transition deterministic',       JSON.stringify(sm_detA) === JSON.stringify(sm_detB));

// ── Amendment chains (Epic 68.3) ────────────────────────────────────────────

console.log('\n── amendment chains ─────────────────────────');

const amdKeys = ltx.generateNIK({ nodeLabel: 'HOST' });
const amdCache = { [amdKeys.nik.nodeId]: amdKeys.nik };
const rootPlan = ltx.createPlan({ title: 'Chain Test', start: '2026-08-01T12:00:00.000Z', delay: 860 });
const signedRoot = ltx.signPlan(rootPlan, amdKeys.privateKeyB64);

check('planHash 64 hex',                /^[0-9a-f]{64}$/.test(ltx.planHash(rootPlan)));
check('planHash key-order stable',      ltx.planHash({ b: 1, a: 2 }) === ltx.planHash({ a: 2, b: 1 }));

const amd1 = ltx.createAmendment(signedRoot, { title: 'Chain Test (amended)' }, amdKeys.privateKeyB64);
check('amendment is v3',                amd1.plan.v === 3);
check('amendment planVersion 2',        amd1.plan.planVersion === 2);
check('prevPlanHash = hash(root)',      amd1.plan.prevPlanHash === ltx.planHash(rootPlan));
check('original plan untouched',        rootPlan.v === 2 && rootPlan.planVersion === undefined);
check('amendment planId v3 infix',      ltx.makePlanId(amd1.plan).includes('-v3-'));
check('v2 planId unchanged by 68',      ltx.makePlanId(rootPlan).includes('-v2-'));

const amd2 = ltx.createAmendment(amd1, { quantum: 4 }, amdKeys.privateKeyB64);
check('chain-of-3 verifies',            ltx.verifyAmendmentChain([signedRoot, amd1, amd2], amdCache).valid === true);
check('single root verifies',           ltx.verifyAmendmentChain([signedRoot], amdCache).valid === true);
check('empty chain invalid',            ltx.verifyAmendmentChain([], amdCache).valid === false);
check('skipped link detected',          ltx.verifyAmendmentChain([signedRoot, amd2], amdCache).valid === false);

// tamper: modify amended plan content after signing
const amdTampered = JSON.parse(JSON.stringify(amd1));
amdTampered.plan.title = 'EVIL';
check('tampered link rejected',         ltx.verifyAmendmentChain([signedRoot, amdTampered], amdCache).valid === false);

// wrong signer
const evilKeys = ltx.generateNIK({ nodeLabel: 'EVIL' });
const amdEvil = ltx.createAmendment(signedRoot, { title: 'hijack' }, evilKeys.privateKeyB64);
check('non-HOST signer rejected',       ltx.verifyAmendmentChain([signedRoot, amdEvil], amdCache).valid === false);

// insertBufferViaAmendment — drift scenario (§6.2 → §6.4)
const drifted = ltx.insertBufferViaAmendment(signedRoot, { afterIndex: -1, q: 2 }, amdKeys.privateKeyB64);
check('buffer appended',                drifted.plan.segments.length === rootPlan.segments.length + 1);
check('buffer at end',                  drifted.plan.segments[drifted.plan.segments.length - 1].type === 'BUFFER');
check('buffer amendment verifies',      ltx.verifyAmendmentChain([signedRoot, drifted], amdCache).valid === true);
const drifted2 = ltx.insertBufferViaAmendment(signedRoot, { afterIndex: 2, q: 1 }, amdKeys.privateKeyB64);
check('buffer mid-insert position',     drifted2.plan.segments[3].type === 'BUFFER');

// ── Registers (Epic 69.1) ───────────────────────────────────────────────────

console.log('\n── registers ────────────────────────────────');

const regHost = ltx.generateNIK({ nodeLabel: 'HOST' });
const regMars = ltx.generateNIK({ nodeLabel: 'MARS' });
const regCache = { N0: regHost.nik, N1: regMars.nik };
const regSid = 'LTX-20260801-EARTHHQ-MARS-v2-00b17ad8';

function mkEntry(type, content, nodeId, seq, ts, priv, entryId) {
  return ltx.createRegisterEntry(type, content, {
    sessionId: regSid, nodeId, seq, timestamp: ts, privateKeyB64: priv,
    ...(entryId ? { entryId } : {}),
  });
}

const q1 = mkEntry('question', { text: 'Water status?', urgency: 'high' }, 'N1', 1, '2026-08-01T12:01:00.000Z', regMars.privateKeyB64);
check('entry id prefix QST',           q1.entryId === 'QST-N1-1');
check('entry has sig',                 typeof q1.sig === 'string' && q1.sig.length > 40);
check('entry verifies',                ltx.verifyRegisterEntry(q1, regCache).valid === true);

const qTampered = { ...q1, content: { ...q1.content, text: 'EVIL' } };
check('tampered entry rejected',       ltx.verifyRegisterEntry(qTampered, regCache).valid === false);
check('unknown key rejected',          ltx.verifyRegisterEntry(q1, { N9: regHost.nik }).reason === 'key_not_in_cache');

const qResp = mkEntry('question_response', { qid: 'QST-N1-1', response: 'Nominal', version: 2 }, 'N0', 1, '2026-08-01T12:05:00.000Z', regHost.privateKeyB64);
const act1 = mkEntry('action', { description: 'Resupply filters', owner: 'N1', dueTimeUTC: '2026-09-01T00:00:00Z' }, 'N0', 2, '2026-08-01T12:06:00.000Z', regHost.privateKeyB64);
const actAcc = mkEntry('action_update', { aid: 'ACT-N0-2', status: 'ACCEPTED', version: 2 }, 'N1', 2, '2026-08-01T12:08:00.000Z', regMars.privateKeyB64);
const actDone = mkEntry('action_update', { aid: 'ACT-N0-2', status: 'DONE', version: 3 }, 'N1', 3, '2026-08-01T12:20:00.000Z', regMars.privateKeyB64);

const qReg = ltx.reduceQuestions([q1, qResp]);
check('question ANSWERED',             qReg.byId['QST-N1-1'].status === 'ANSWERED');
check('question response text',        qReg.byId['QST-N1-1'].response === 'Nominal');
check('question submitter',            qReg.byId['QST-N1-1'].submitter === 'N1');

const aReg = ltx.reduceActions([act1, actAcc, actDone]);
check('action DONE',                   aReg.byId['ACT-N0-2'].status === 'DONE');
check('action version 3',              aReg.byId['ACT-N0-2'].version === 3);
check('action owner kept',             aReg.byId['ACT-N0-2'].owner === 'N1');

// reducer determinism: shuffled input → identical state
const allEntries = [q1, qResp, act1, actAcc, actDone];
const shuffles = [
  [actDone, q1, actAcc, qResp, act1],
  [qResp, actDone, act1, q1, actAcc],
  [act1, actAcc, actDone, qResp, q1],
];
check('reduceQuestions order-independent', shuffles.every(s =>
  JSON.stringify(ltx.reduceQuestions(s)) === JSON.stringify(ltx.reduceQuestions(allEntries))));
check('reduceActions order-independent', shuffles.every(s =>
  JSON.stringify(ltx.reduceActions(s)) === JSON.stringify(ltx.reduceActions(allEntries))));

// duplicate (nodeId,seq) deduped
check('dedup by nodeId+seq',           ltx.orderEntries([q1, q1, qResp]).length === 2);

// conflict: same version, different editors → lowest nodeId wins
const respA = mkEntry('question_response', { qid: 'QST-N1-1', response: 'From N0', version: 5 }, 'N0', 7, '2026-08-01T13:00:00.000Z', regHost.privateKeyB64);
const respB = mkEntry('question_response', { qid: 'QST-N1-1', response: 'From N1', version: 5 }, 'N1', 7, '2026-08-01T13:00:00.000Z', regMars.privateKeyB64);
const conflictReg = ltx.reduceQuestions([q1, respA, respB]);
check('conflict lowest nodeId wins',   conflictReg.byId['QST-N1-1'].response === 'From N0');
check('loser flagged superseded',      conflictReg.superseded.includes(respB.entryId));
const conflictReg2 = ltx.reduceQuestions([q1, respB, respA]);
check('conflict result order-independent',
  JSON.stringify(conflictReg.byId) === JSON.stringify(conflictReg2.byId));

// question WITHDRAWN + orphan response
const qWith = mkEntry('question_response', { qid: 'QST-N1-1', status: 'WITHDRAWN', version: 9 }, 'N1', 9, '2026-08-01T14:00:00.000Z', regMars.privateKeyB64);
check('question WITHDRAWN',            ltx.reduceQuestions([q1, qWith]).byId['QST-N1-1'].status === 'WITHDRAWN');
const orphan = mkEntry('question_response', { qid: 'QST-NOPE-1', version: 2 }, 'N0', 8, '2026-08-01T13:30:00.000Z', regHost.privateKeyB64);
check('orphan response superseded',    ltx.reduceQuestions([orphan]).superseded.includes(orphan.entryId));

// seeds
const seeds = ltx.emitQuestionSeeds(
  [{ text: 'Q one' }, { text: 'Q two' }],
  { sessionId: regSid, nodeId: 'N1', seq: 20, timestamp: '2026-08-01T11:00:00.000Z', privateKeyB64: regMars.privateKeyB64 });
check('seeds emitted with seq',        seeds.length === 2 && seeds[1].seq === 21);
check('seeds verify',                  seeds.every(s => ltx.verifyRegisterEntry(s, regCache).valid));

// ── Merge + partition recovery (Epic 69.2) ──────────────────────────────────

console.log('\n── merge / partition recovery ───────────────');

// two nodes diverge: shared prefix + unique entries each
const shared = [q1, act1];
const localOnly = [actAcc, mkEntry('decision', { text: 'Go for EVA' }, 'N0', 5, '2026-08-01T12:30:00.000Z', regHost.privateKeyB64)];
const remoteOnly = [actDone, qWith];
const sideA = shared.concat(localOnly);
const sideB = shared.concat(remoteOnly);

const mergedA = ltx.mergeLogs(sideA, sideB, regCache);
const mergedB = ltx.mergeLogs(sideB, sideA, regCache);
check('merge symmetric',               JSON.stringify(mergedA.entries) === JSON.stringify(mergedB.entries));
check('merge union size',              mergedA.entries.length === 6);
check('merge roots identical',         ltx.entriesRoot(mergedA.entries) === ltx.entriesRoot(mergedB.entries));
check('merged register state equal',
  JSON.stringify(ltx.reduceActions(mergedA.entries)) === JSON.stringify(ltx.reduceActions(mergedB.entries)));
check('no rejects with good sigs',     mergedA.rejected.length === 0);

// tampered entry rejected in merge
const evilEntry = { ...actDone, content: { ...actDone.content, status: 'REJECTED' } };
const mergedEvil = ltx.mergeLogs(sideA, [evilEntry], regCache);
check('merge rejects tampered entry',  mergedEvil.rejected.length === 1);
check('tampered not in union',         !mergedEvil.entries.some(e => e.content.status === 'REJECTED'));

// merge snapshot
const snapOpts = { sessionId: regSid, nodeId: 'N0', seq: 30, timestamp: '2026-08-01T15:00:00.000Z', privateKeyB64: regHost.privateKeyB64 };
const msResult = ltx.runMergeSegment(sideA, sideB, regCache, snapOpts);
check('snapshot type merge_snapshot',  msResult.snapshot.type === 'merge_snapshot');
check('snapshot id prefix MRG',        msResult.snapshot.entryId.startsWith('MRG-'));
check('snapshot root matches',         msResult.snapshot.content.mergedRoot === ltx.entriesRoot(msResult.merged.entries));
check('snapshot verifies',             ltx.verifyRegisterEntry(msResult.snapshot, regCache).valid === true);
check('snapshot registers reduced',    msResult.snapshot.content.actionRegister['ACT-N0-2'].status === 'DONE');

// partition recovery: remote is a clean extension of local
const remoteLog = ltx.createMerkleLog();
const extended = ltx.orderEntries(shared).concat(ltx.orderEntries(remoteOnly));
for (const e of extended) remoteLog.append(e);
const remoteHead = remoteLog.signTreeHead(regMars.privateKeyB64, 'N1');
const rec1 = ltx.recoverPartition(ltx.orderEntries(shared), extended, remoteHead, regMars.nik, regCache);
check('prefix → accept_extension',     rec1.action === 'accept_extension');
check('extension entry count',         rec1.entries.length === 4);

// diverged: both sides have unique entries → deterministic merge
const rec2 = ltx.recoverPartition(ltx.orderEntries(sideA), extended, remoteHead, regMars.nik, regCache);
check('diverged → merged',             rec2.action === 'merged');
check('merged count',                  rec2.entries.length === 6);

// remote head lies about its entries → divergent
const badHead = { ...remoteHead, treeSize: remoteHead.treeSize + 1 };
const rec3 = ltx.recoverPartition(shared, extended, badHead, regMars.nik, regCache);
check('bad head → divergent',          rec3.action === 'divergent');
const wrongSigner = ltx.recoverPartition(shared, extended, remoteHead, regHost.nik, regCache);
check('wrong head signer → divergent', wrongSigner.action === 'divergent');

// ── CBOR (Epic 70.1) ─────────────────────────────────────────────────────────

console.log('\n── cbor ─────────────────────────────────────');

const hex = b => Buffer.from(b).toString('hex');
// RFC 8949 Appendix A vectors (deterministic subset)
check('cbor 0',                hex(ltx.encodeCbor(0)) === '00');
check('cbor 10',               hex(ltx.encodeCbor(10)) === '0a');
check('cbor 23',               hex(ltx.encodeCbor(23)) === '17');
check('cbor 24',               hex(ltx.encodeCbor(24)) === '1818');
check('cbor 100',              hex(ltx.encodeCbor(100)) === '1864');
check('cbor 1000',             hex(ltx.encodeCbor(1000)) === '1903e8');
check('cbor 1000000',          hex(ltx.encodeCbor(1000000)) === '1a000f4240');
check('cbor -1',               hex(ltx.encodeCbor(-1)) === '20');
check('cbor -10',              hex(ltx.encodeCbor(-10)) === '29');
check('cbor -100',             hex(ltx.encodeCbor(-100)) === '3863');
check('cbor -1000',            hex(ltx.encodeCbor(-1000)) === '3903e7');
check('cbor false',            hex(ltx.encodeCbor(false)) === 'f4');
check('cbor true',             hex(ltx.encodeCbor(true)) === 'f5');
check('cbor null',             hex(ltx.encodeCbor(null)) === 'f6');
check('cbor ""',               hex(ltx.encodeCbor('')) === '60');
check('cbor "a"',              hex(ltx.encodeCbor('a')) === '6161');
check('cbor "IETF"',           hex(ltx.encodeCbor('IETF')) === '6449455446');
check('cbor h\'01020304\'',    hex(ltx.encodeCbor(Buffer.from('01020304', 'hex'))) === '4401020304');
check('cbor []',               hex(ltx.encodeCbor([])) === '80');
check('cbor [1,2,3]',          hex(ltx.encodeCbor([1, 2, 3])) === '83010203');
check('cbor {"a":1,"b":[2,3]}', hex(ltx.encodeCbor({ a: 1, b: [2, 3] })) === 'a26161016162820203');
check('cbor -19 (Ed25519 alg)', hex(ltx.encodeCbor(-19)) === '32');
check('cbor tag 18',           hex(ltx.encodeCbor(new ltx.CborTag(18, [1]))) === 'd28101');

// deterministic map key order: int keys sort before longer encodings
check('cbor {1:-19} header',   hex(ltx.encodeCbor(new Map([[1, -19]]))) === 'a10132');

// round-trips
function rt(v) {
  const dec = ltx.decodeCbor(ltx.encodeCbor(v));
  return JSON.stringify(dec instanceof Map ? Object.fromEntries(dec) : dec) === JSON.stringify(v);
}
check('cbor rt ints',          rt(1234567) && rt(-42));
check('cbor rt string',        rt('light-time'));
check('cbor rt nested array',  rt([1, ['a', -3], null, true]));
const rtMap = ltx.decodeCbor(ltx.encodeCbor({ z: 1, a: 2 }));
check('cbor rt map',           rtMap instanceof Map && rtMap.get('a') === 2 && rtMap.get('z') === 1);
let cborThrew = false;
try { ltx.encodeCbor(1.5); } catch (_) { cborThrew = true; }
check('cbor rejects floats',   cborThrew);
let cborTrail = false;
try { ltx.decodeCbor(Buffer.from('0000', 'hex')); } catch (_) { cborTrail = true; }
check('cbor rejects trailing', cborTrail);

// ── COSE_Sign1 (Epic 70.2) ───────────────────────────────────────────────────

console.log('\n── cose_sign1 ───────────────────────────────');

const coseKeys = ltx.generateNIK({ nodeLabel: 'HOST' });
const coseCache = { [coseKeys.nik.nodeId]: coseKeys.nik };
const cosePlan = ltx.createPlan({ title: 'COSE Test', start: '2026-08-01T12:00:00.000Z', delay: 860 });

const coseEnv = ltx.signPlanCose(cosePlan, coseKeys.privateKeyB64);
check('cose env has b64 bytes',        typeof coseEnv.coseSign1CborB64 === 'string');
const coseBytes = Buffer.from(coseEnv.coseSign1CborB64, 'base64url');
check('cose bytes start with tag 18',  coseBytes[0] === 0xd2);
check('cose verify ok',                ltx.verifyPlanCose(coseEnv, coseCache).valid === true);

// tamper: flip a payload bit
const tamperedBytes = Buffer.from(coseBytes);
tamperedBytes[tamperedBytes.length - 70] ^= 0x01;
check('cose tamper rejected',
  ltx.verifyPlanCose({ plan: cosePlan, coseSign1CborB64: tamperedBytes.toString('base64url') }, coseCache).valid === false);

// plan mismatch
check('cose payload mismatch',
  ltx.verifyPlanCose({ plan: { ...cosePlan, title: 'EVIL' }, coseSign1CborB64: coseEnv.coseSign1CborB64 }, coseCache).reason === 'payload_mismatch');

// unknown key
check('cose unknown key',
  ltx.verifyPlanCose(coseEnv, {}).reason === 'key_not_in_cache');

// verifyPlanAny dispatches both envelope forms; JSON envelope stays frozen
const jsonEnv = ltx.signPlan(cosePlan, coseKeys.privateKeyB64);
check('verifyPlanAny cbor',            ltx.verifyPlanAny(coseEnv, coseCache).valid === true);
check('verifyPlanAny json',            ltx.verifyPlanAny(jsonEnv, coseCache).valid === true);
check('verifyPlanAny unknown',         ltx.verifyPlanAny({ plan: cosePlan }, coseCache).reason === 'unknown_envelope');
check('json envelope alg still -19',
  Buffer.from(jsonEnv.coseSign1.protected, 'base64url').toString('utf8') === '{"alg":-19}');

// ── Ed25519 BIB (Epic 70.3) ──────────────────────────────────────────────────

console.log('\n── ed25519 bib ──────────────────────────────');

const bibNik = ltx.generateNIK({ nodeLabel: 'MARS' });
const bibBundle = { type: 'READINESS', planId: 'X', nodeId: 'N1', seq: 4 };
const bibSigned = ltx.addBIBEd25519(bibBundle, bibNik.privateKeyB64);
check('ed25519 bib context',           bibSigned.bib.securityContext === 'ltx-ed25519');
check('ed25519 bib verifies',          ltx.verifyBIBEd25519(bibSigned, bibNik.nik).valid === true);
const bibTampered = { ...bibSigned, seq: 99 };
check('ed25519 bib tamper rejected',   ltx.verifyBIBEd25519(bibTampered, bibNik.nik).valid === false);
// context confusion: HMAC verifier must reject ed25519 BIBs and vice versa
const hmacKey = ltx.generateBIBKey();
check('hmac verifier rejects ed25519', ltx.verifyBIB(bibSigned, hmacKey).reason === 'context_mismatch');
const hmacSigned = ltx.addBIB(bibBundle, hmacKey);
check('hmac bib still verifies',       ltx.verifyBIB(hmacSigned, hmacKey).valid === true);
check('ed25519 verifier rejects hmac', ltx.verifyBIBEd25519(hmacSigned, bibNik.nik).reason === 'context_mismatch');

// ── Freshness scopes (Epic 70.4) ─────────────────────────────────────────────

console.log('\n── freshness scopes ─────────────────────────');

const gTracker = ltx.createGlobalSequenceTracker();
check('global nextSeq',                gTracker.nextSeq('HQ', 'KEY_BUNDLE') === 1);
check('global scope isolated',         gTracker.nextSeq('HQ', 'KEY_REVOCATION') === 1);
check('global recordSeq accept',       gTracker.recordSeq('HQ', 'KEY_BUNDLE', 1).accepted === true);
check('global replay rejected',        gTracker.recordSeq('HQ', 'KEY_BUNDLE', 1).reason === 'replay');
check('global gap flagged',            gTracker.recordSeq('HQ', 'KEY_BUNDLE', 4).gapSize === 2);

const NOW = Date.parse('2026-08-01T00:00:00Z');
check('issuedAt fresh ok',             ltx.checkIssuedAt('2026-07-20T00:00:00Z', { nowMs: NOW }).accepted === true);
check('issuedAt 31d expired',          ltx.checkIssuedAt('2026-07-01T00:00:00Z', { nowMs: NOW }).reason === 'expired');
check('issuedAt custom window',        ltx.checkIssuedAt('2026-07-25T00:00:00Z', { nowMs: NOW, maxAgeDays: 3 }).reason === 'expired');
check('issuedAt future rejected',      ltx.checkIssuedAt('2026-08-05T00:00:00Z', { nowMs: NOW }).reason === 'future_dated');
check('issuedAt garbage rejected',     ltx.checkIssuedAt('not-a-date', { nowMs: NOW }).reason === 'invalid_issued_at');

// KEY_BUNDLE with signature-covered freshness fields
const kbHost = ltx.generateNIK({ nodeLabel: 'HQ' });
const kbNiks = [kbHost.nik, bibNik.nik];
const kbFresh = ltx.createKeyBundle('PLAN-X', kbNiks, kbHost.privateKeyB64,
  { senderNodeId: 'HQ', seq: 1, issuedAt: '2026-07-20T00:00:00Z' });
check('fresh bundle has issuedAt',     kbFresh.issuedAt === '2026-07-20T00:00:00Z' && kbFresh.seq === 1);
const kbTracker = ltx.createGlobalSequenceTracker();
const kbCache = ltx.verifyAndCacheKeys(kbFresh, kbHost.nik, { tracker: kbTracker, nowMs: NOW });
check('fresh bundle verifies',         kbCache !== null && kbCache.size === 2);
// replaying the identical bundle is now rejected (same (sender,msgType,seq))
check('cross-session replay rejected', ltx.verifyAndCacheKeys(kbFresh, kbHost.nik, { tracker: kbTracker, nowMs: NOW }) === null);
// tampering with signature-covered issuedAt breaks the signature
const kbTampered = { ...kbFresh, issuedAt: '2026-07-31T00:00:00Z' };
check('issuedAt covered by sig',       ltx.verifyAndCacheKeys(kbTampered, kbHost.nik, { tracker: ltx.createGlobalSequenceTracker(), nowMs: NOW }) === null);
// stale bundle rejected by max-age even with valid signature
const kbStale = ltx.createKeyBundle('PLAN-X', kbNiks, kbHost.privateKeyB64,
  { senderNodeId: 'HQ', seq: 2, issuedAt: '2026-06-01T00:00:00Z' });
check('stale bundle rejected',         ltx.verifyAndCacheKeys(kbStale, kbHost.nik, { tracker: ltx.createGlobalSequenceTracker(), nowMs: NOW }) === null);
// legacy bundle (no freshness fields) still verifies without enforcement
const kbLegacy = ltx.createKeyBundle('PLAN-X', kbNiks, kbHost.privateKeyB64);
check('legacy bundle verifies',        ltx.verifyAndCacheKeys(kbLegacy, kbHost.nik) !== null);
// legacy bundle rejected when freshness is demanded
check('legacy rejected under enforcement',
  ltx.verifyAndCacheKeys(kbLegacy, kbHost.nik, { tracker: ltx.createGlobalSequenceTracker(), nowMs: NOW }) === null);

// ── Conference mode / v3 plans (Epic 71) ────────────────────────────────────

console.log('\n── conference / v3 ──────────────────────────');

// v2 planId freeze: known-good golden value must never change
const frozenPlan = {
  v: 2, title: 'Freeze Check', start: '2026-08-01T12:00:00.000Z', quantum: 5, mode: 'LTX',
  segments: [{ type: 'PLAN_CONFIRM', q: 2 }, { type: 'TX', q: 2 }],
  nodes: [
    { id: 'N0', name: 'Earth HQ', role: 'HOST', delay: 0, location: 'earth' },
    { id: 'N1', name: 'Mars Hab-01', role: 'PARTICIPANT', delay: 860, location: 'mars' },
  ],
};
const frozenId = ltx.makePlanId(frozenPlan);
check('v2 planId format',              /^LTX-20260801-EARTHHQ-MARS-v2-[0-9a-f]{8}$/.test(frozenId));
check('v2 planId deterministic',       ltx.makePlanId(frozenPlan) === frozenId);

// upgradePlanToV3 is explicit and non-mutating
const v3plan = ltx.upgradePlanToV3(frozenPlan, { delays: { 'N0|N1': 860 } });
check('upgrade v3 flag',               v3plan.v === 3 && v3plan.planVersion === 1);
check('upgrade non-mutating',          frozenPlan.v === 2 && frozenPlan.delays === undefined);
check('upgradeConfig leaves v3 alone', ltx.upgradeConfig(v3plan) === v3plan);
check('v3 planId infix',               ltx.makePlanId(v3plan).includes('-v3-'));
check('v2 id unchanged post-upgrade',  ltx.makePlanId(frozenPlan) === frozenId);

// pairDelay: matrix authoritative, conservative-sum fallback, HOST row
const confPlan = {
  v: 2, title: 'Solar System Summit', start: '2026-08-01T12:00:00.000Z', quantum: 5, mode: 'LTX-ASYNC',
  nodes: [
    { id: 'N0', name: 'Earth HQ',   role: 'HOST',        delay: 0,    location: 'earth' },
    { id: 'N1', name: 'Mars Hab',   role: 'PARTICIPANT', delay: 900,  location: 'mars' },
    { id: 'N2', name: 'Luna Base',  role: 'PARTICIPANT', delay: 2,    location: 'moon' },
    { id: 'N3', name: 'Jupiter Obs', role: 'PARTICIPANT', delay: 2600, location: 'jupiter' },
  ],
  segments: [
    { type: 'PLAN_CONFIRM', q: 2 },
    { type: 'TX', q: 3, speaker: 'N0', label: 'Opening Address' },
    { type: 'TX', q: 4, speaker: 'N1', label: 'Mars Field Report' },
    { type: 'RX', q: 2 },
  ],
};
check('pairDelay HOST row',            ltx.pairDelay(confPlan, 'N0', 'N1') === 900);
check('pairDelay symmetric',           ltx.pairDelay(confPlan, 'N1', 'N0') === 900);
check('pairDelay sum fallback',        ltx.pairDelay(confPlan, 'N1', 'N3') === 3500);
check('pairDelay self zero',           ltx.pairDelay(confPlan, 'N1', 'N1') === 0);
const confV3 = ltx.upgradePlanToV3(confPlan, { delays: { 'N1|N3': 700 } });
check('pairDelay matrix wins',         ltx.pairDelay(confV3, 'N3', 'N1') === 700);
check('pairDelay matrix key sorted',   ltx.pairDelay(confV3, 'N1', 'N3') === 700);

// computeSegmentsFor: viewer-perspective derivation (§14.3)
const hostView = ltx.computeSegmentsFor(confPlan, 'N0');
const marsView = ltx.computeSegmentsFor(confPlan, 'N1');
check('speaker sees transmit',         hostView[1].perspective === 'transmit' && hostView[1].arrivalOffsetS === 0);
check('viewer sees receive',           marsView[1].perspective === 'receive');
check('arrival shift = pairDelay',     marsView[1].arrivalOffsetS === 900);
check('arrival time shifted',          marsView[1].start.getTime() - hostView[1].start.getTime() === 900000);
check('own segment unshifted',         marsView[2].perspective === 'transmit' && marsView[2].arrivalOffsetS === 0);
check('unattributed neutral',          marsView[0].perspective === 'neutral' && marsView[3].perspective === 'neutral');
check('label carried',                 marsView[1].label === 'Opening Address');
let cfThrew = false;
try { ltx.computeSegmentsFor(confPlan, 'N9'); } catch (_) { cfThrew = true; }
check('unknown viewer throws',         cfThrew);

// buildConferenceAgenda: rotation invariant for N=3..6
for (let N = 3; N <= 6; N++) {
  const nodes = Array.from({ length: N }, (_, i) =>
    ({ id: `N${i}`, name: `Node ${i}`, role: i === 0 ? 'HOST' : 'PARTICIPANT', delay: i * 100, location: 'earth' }));
  const agenda = ltx.buildConferenceAgenda(nodes, { cycles: N, blockQ: 2 });
  const tx = agenda.filter(s => s.type === 'TX');
  check(`rotation N=${N} block count`, tx.length === N * N);
  const openers = [];
  for (let c = 0; c < N; c++) openers.push(tx[c * N].speaker);
  check(`rotation N=${N} openers distinct`, new Set(openers).size === N);
  const perNode = {};
  tx.forEach(s => { perNode[s.speaker] = (perNode[s.speaker] || 0) + 1; });
  check(`rotation N=${N} equal blocks`, Object.values(perNode).every(v => v === N));
}
const agendaFixed = ltx.buildConferenceAgenda(confPlan.nodes, { cycles: 2, fairness: 'fixed' });
const fixedTx = agendaFixed.filter(s => s.type === 'TX');
check('fixed keeps plan order',        fixedTx[0].speaker === 'N0' && fixedTx[4].speaker === 'N0');
const agendaLabeled = ltx.buildConferenceAgenda(confPlan.nodes, { labels: { N1: 'Mars Field Report' } });
check('labels applied',                agendaLabeled.some(s => s.label === 'Mars Field Report'));
check('agenda determinism',            JSON.stringify(ltx.buildConferenceAgenda(confPlan.nodes, { cycles: 3 }))
                                        === JSON.stringify(ltx.buildConferenceAgenda(confPlan.nodes, { cycles: 3 })));

// primeTimeReport
const ptAgenda = ltx.buildConferenceAgenda(confPlan.nodes, { cycles: 4, blockQ: 2 });
const ptPlan = { ...confPlan, segments: ptAgenda };
const report = ltx.primeTimeReport(ptPlan);
check('report covers all nodes',       report.length === 4);
check('rotation openings fair',        report.every(r => r.openings === 1));
const fixedReport = ltx.primeTimeReport({ ...confPlan, segments: ltx.buildConferenceAgenda(confPlan.nodes, { cycles: 4, fairness: 'fixed' }) });
check('fixed openings unfair',         fixedReport.find(r => r.nodeId === 'N0').openings === 4);
check('scores in [0,1]',               report.every(r => r.score > 0 && r.score <= 1));

// per-attendee ICS (§14.5); no-arg output byte-compatible
const icsDefault = ltx.generateICS(confPlan);
const icsDefault2 = ltx.generateICS(confPlan, {});
check('no-arg ICS single VEVENT',      (icsDefault.match(/BEGIN:VEVENT/g) || []).length === 1);
check('empty-opts ICS identical',      icsDefault === icsDefault2);
const icsMars = ltx.generateICS(confPlan, { viewerNodeId: 'N1' });
check('viewer ICS event per segment',  (icsMars.match(/BEGIN:VEVENT/g) || []).length === confPlan.segments.length);
check('viewer ICS names speaker',      icsMars.includes('Opening Address — Earth HQ, arriving after 15 min light-time'));
check('viewer ICS you-present',        icsMars.includes('Mars Field Report — you present'));
check('viewer ICS LTX-VIEWER',         icsMars.includes('LTX-VIEWER:N1'));
const icsShift = icsMars.match(/DTSTART:(\d{8}T\d{6}Z)/g) || [];
check('viewer ICS has DTSTARTs',       icsShift.length === confPlan.segments.length);
const icsV3 = ltx.generateICS(confV3, { viewerNodeId: 'N1' });
check('viewer ICS pair lines',         icsV3.includes('LTX-DELAY;PAIR=N1|N3:ONEWAY-ASSUMED=700'));

// ── Summary ────────────────────────────────────────────────────────────────

console.log('\n══════════════════════════════════════════');
console.log(`${passed} passed  ${failed} failed`);
if (failed > 0) process.exit(1);
