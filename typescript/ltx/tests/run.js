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

// ── Summary ────────────────────────────────────────────────────────────────

console.log('\n══════════════════════════════════════════');
console.log(`${passed} passed  ${failed} failed`);
if (failed > 0) process.exit(1);
