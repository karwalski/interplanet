'use strict';
/**
 * run.js — Unit tests for ltx-sdk.js (JavaScript SDK).
 * Story 28.1 — Cryptographic Identity and Canonical JSON
 * No external test framework. Run with: node tests/run.js
 */

const ltx = require('../ltx-sdk');

let passed = 0;
let failed = 0;

function check(name, cond) {
  if (cond) { passed++; }
  else { failed++; console.log('FAIL:', name); }
}

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
// No structural whitespace: verify with a simple object that has no string values containing spaces
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
const keyCache = new Map([[signerNik.nodeId, signerNik]]);
const vResult = ltx.verifyPlan(signed, keyCache);
check('verifyPlan valid plan → true',    vResult.valid === true);

// verifyPlan — tampered payload
const tampered = JSON.parse(JSON.stringify(signed));
tampered.coseSign1.payload = Buffer.from(ltx.canonicalJSON({ ...planToSign, title: 'HACKED' })).toString('base64url');
const vTampered = ltx.verifyPlan(tampered, keyCache);
check('verifyPlan tampered → false',     vTampered.valid === false);

// verifyPlan — wrong key (key not in cache)
const { nik: wrongNik } = ltx.generateNIK();
const wrongCache = new Map([[wrongNik.nodeId, wrongNik]]);
const vWrong = ltx.verifyPlan(signed, wrongCache);
check('verifyPlan wrong key → false',    vWrong.valid === false);
check('verifyPlan wrong key reason',     vWrong.reason === 'key_not_in_cache');

// verifyPlan — expired key
const expiredNik2 = { ...signerNik, validUntil: '2020-01-01T00:00:00.000Z' };
const expiredCache = new Map([[expiredNik2.nodeId, expiredNik2]]);
const vExpired = ltx.verifyPlan(signed, expiredCache);
check('verifyPlan expired key → false',  vExpired.valid === false);
check('verifyPlan expired reason',       vExpired.reason === 'key_expired');

// verifyPlan — missing coseSign1
const vMissing = ltx.verifyPlan({ plan: planToSign }, keyCache);
check('verifyPlan missing COSE → false', vMissing.valid === false);

// Cross-language verification: see integration tests (Python ↔ JS roundtrip)
// is validated separately; the Sig_Structure is identical across languages.

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
const log = ltx.createMerkleLog();

// Empty log
check('empty log treeSize == 0',        log.treeSize() === 0);
check('empty log root is 64 zeros',     log.rootHex() === '0'.repeat(64));

// Append entries
const e1 = log.append({ type: 'TX', seq: 1, data: 'hello' });
check('append returns treeSize 1',      e1.treeSize === 1);
check('append returns root hex',        typeof e1.root === 'string' && e1.root.length === 64);

const e2 = log.append({ type: 'RX', seq: 2, data: 'world' });
check('append 2 returns treeSize 2',    e2.treeSize === 2);
check('root changes on append',         e1.root !== e2.root);

// Append more entries to test consistency
for (let i = 3; i <= 10; i++) log.append({ seq: i });
check('log has 10 entries',             log.treeSize() === 10);

// Capture root at size 10
const root10 = log.rootHex();

// Append 5 more
for (let i = 11; i <= 15; i++) log.append({ seq: i });
const root15 = log.rootHex();
check('log has 15 entries',             log.treeSize() === 15);
check('root10 !== root15',              root10 !== root15);

// Inclusion proof
const proof3 = log.inclusionProof(2);  // 0-based, third entry
check('inclusionProof returns array',   Array.isArray(proof3));
check('inclusion proof has side+hash',  proof3.every(p => (p.side === 'left' || p.side === 'right') && typeof p.hash === 'string'));

// Verify inclusion
const entry3 = { seq: 3 };
const valid3 = log.verifyInclusion(entry3, 2, proof3, root15);
check('verifyInclusion valid → true',   valid3 === true);

// Tampered entry
const fakeEntry = { seq: 999 };
const invalidInclusion = log.verifyInclusion(fakeEntry, 2, proof3, root15);
check('verifyInclusion tampered → false', invalidInclusion === false);

// Consistency proof
const consProof = log.consistencyProof(10);
check('consistencyProof returns array', Array.isArray(consProof));
// Verify determinism: a fresh log with the same 15 entries should have the same root
const log2 = ltx.createMerkleLog();
log2.append({ type: 'TX', seq: 1, data: 'hello' });
log2.append({ type: 'RX', seq: 2, data: 'world' });
for (let i = 3; i <= 15; i++) log2.append({ seq: i });
check('identical log same root',        log2.rootHex() === root15);

// Signed tree head
const { nik: hostNik, privateKeyB64: hostPriv } = ltx.generateNIK();
const signedHead = log.signTreeHead(hostPriv, hostNik.nodeId);
check('signTreeHead has treeSize',      signedHead.treeSize === 15);
check('signTreeHead has sha256RootHash', signedHead.sha256RootHash === root15);
check('signTreeHead has signature',     typeof signedHead.treeHeadSig === 'string');

// Verify tree head
check('verifyTreeHead valid → true',    ltx.verifyTreeHead(signedHead, hostNik) === true);

// Wrong key
const { nik: wrongNik2 } = ltx.generateNIK();
check('verifyTreeHead wrong key → false', ltx.verifyTreeHead(signedHead, wrongNik2) === false);

// ── Security: KEY_BUNDLE ──────────────────────────────────────────────────

console.log('\n── Security: KEY_BUNDLE ──────────────────────────────────────');
// Setup: two nodes
const { nik: hostNik2, privateKeyB64: hostPriv2 } = ltx.generateNIK({ nodeLabel: 'Earth HQ' });
const { nik: partNik } = ltx.generateNIK({ nodeLabel: 'Mars Hab' });
const { nik: eokNik } = ltx.generateNIK({ nodeLabel: 'Emergency Override' });

const kb = ltx.createKeyBundle('plan-test-001', [hostNik2, partNik, eokNik], hostPriv2);
check('createKeyBundle type',           kb.type === 'KEY_BUNDLE');
check('createKeyBundle planId',         kb.planId === 'plan-test-001');
check('createKeyBundle keys array',     Array.isArray(kb.keys) && kb.keys.length === 3);
check('createKeyBundle has bundleSig',  typeof kb.bundleSig === 'string');

// Verify with correct bootstrap NIK (host's NIK is the bootstrap key)
const cache2 = ltx.verifyAndCacheKeys(kb, hostNik2);
check('verifyAndCacheKeys returns Map',  cache2 instanceof Map);
check('cache has 3 entries',            cache2.size === 3);
check('cache has hostNik',              cache2.has(hostNik2.nodeId));
check('cache has partNik',              cache2.has(partNik.nodeId));

// Verify with wrong bootstrap key → null
const { nik: wrongNik3 } = ltx.generateNIK();
const badCache = ltx.verifyAndCacheKeys(kb, wrongNik3);
check('wrong bootstrap key → null',     badCache === null);

// Tampered bundle → null
const tamperedKb = { ...kb, keys: [...kb.keys, ltx.generateNIK().nik] };
const tamperedCache = ltx.verifyAndCacheKeys(tamperedKb, hostNik2);
check('tampered bundle → null',         tamperedCache === null);

// Expired NIK excluded from cache
const expiredNikKb = { ...ltx.generateNIK().nik, validUntil: '2020-01-01T00:00:00.000Z' };
const kbWithExpired = ltx.createKeyBundle('plan-exp', [hostNik2, expiredNikKb], hostPriv2);
const cacheWithExp = ltx.verifyAndCacheKeys(kbWithExpired, hostNik2);
check('expired NIK excluded from cache', cacheWithExp !== null && !cacheWithExp.has(expiredNikKb.nodeId));
check('valid NIK included',             cacheWithExp.has(hostNik2.nodeId));

// Revocation
const revocation = ltx.createRevocation('plan-test-001', partNik.nodeId, 'compromised', hostPriv2);
check('revocation type correct',        revocation.type === 'KEY_REVOCATION');
check('revocation has sig',             typeof revocation.revocationSig === 'string');

const revResult = ltx.applyRevocation(cache2, revocation);
check('applyRevocation returns true',   revResult === true);
check('revoked key removed from cache', !cache2.has(partNik.nodeId));
check('host key still in cache',        cache2.has(hostNik2.nodeId));

// ── Security: BPSec BIB ───────────────────────────────────────────────────

console.log('\n── Security: BPSec BIB ───────────────────────────────────────');
const bibKey = ltx.generateBIBKey();
const bibBundle = { type: 'TX', seq: 1, data: 'hello mars' };

// 1. addBIB returns object with bib field
const withBib = ltx.addBIB(bibBundle, bibKey);
check('addBIB returns object with bib',       withBib && typeof withBib.bib === 'object');

// 2. bib.contextId === 1
check('bib.contextId === 1',                  withBib.bib.contextId === 1);

// 3. bib.targetBlockNumber === 0
check('bib.targetBlockNumber === 0',          withBib.bib.targetBlockNumber === 0);

// 4. bib.hmac is a non-empty string
check('bib.hmac is non-empty string',         typeof withBib.bib.hmac === 'string' && withBib.bib.hmac.length > 0);

// 5. verifyBIB with correct key → { valid: true }
const vBib = ltx.verifyBIB(withBib, bibKey);
check('verifyBIB correct key → valid true',   vBib.valid === true);

// 6. verifyBIB with tampered payload → { valid: false }
const tamperedBib = { ...withBib, data: 'HACKED' };
const vTamperedBib = ltx.verifyBIB(tamperedBib, bibKey);
check('verifyBIB tampered payload → false',   vTamperedBib.valid === false);

// 7. verifyBIB with wrong key → { valid: false, reason: 'hmac_mismatch' }
const wrongBibKey = ltx.generateBIBKey();
const vWrongKey = ltx.verifyBIB(withBib, wrongBibKey);
check('verifyBIB wrong key → false',          vWrongKey.valid === false);
check('verifyBIB wrong key reason',           vWrongKey.reason === 'hmac_mismatch');

// 8. verifyBIB with no bib field → { valid: false, reason: 'missing_bib' }
const vNoBib = ltx.verifyBIB(bibBundle, bibKey);
check('verifyBIB no bib → missing_bib',       vNoBib.valid === false && vNoBib.reason === 'missing_bib');

// 9. addBIB does not mutate the original bundle
check('addBIB does not mutate original',      !('bib' in bibBundle));

// 10. generateBIBKey returns a 43-char base64url string (256-bit, no padding)
check('generateBIBKey returns 43-char str',   typeof bibKey === 'string' && bibKey.length === 43);

// ── Security: EOK / MULTI-AUTH ────────────────────────────────────────────

console.log('\n── Security: EOK / MULTI-AUTH ────────────────────────────────');

// 1. createEOK returns object with eok and privateKey fields
const eokResult = ltx.createEOK();
check('createEOK returns object with eok',        eokResult && typeof eokResult.eok === 'object');
check('createEOK returns object with privateKey', typeof eokResult.privateKey === 'string');

// 2. eok.keyType === 'eok'
check('eok.keyType === eok',                       eokResult.eok.keyType === 'eok');

// eok structure checks
check('eok.algorithm === Ed25519',                 eokResult.eok.algorithm === 'Ed25519');
check('eok has eokId',                             typeof eokResult.eok.eokId === 'string');
check('eok has publicKey',                         typeof eokResult.eok.publicKey === 'string');
check('eok has validFrom',                         typeof eokResult.eok.validFrom === 'string');
check('eok has validUntil',                        typeof eokResult.eok.validUntil === 'string');

// 3. createEmergencyOverride returns object with type === 'EMERGENCY_OVERRIDE'
const override = ltx.createEmergencyOverride('plan-eok-001', 'ABORT', eokResult.privateKey, eokResult.eok.eokId);
check('createEmergencyOverride type EMERGENCY_OVERRIDE', override.type === 'EMERGENCY_OVERRIDE');

// 4. overrideSig is a non-empty string
check('overrideSig is non-empty string',           typeof override.overrideSig === 'string' && override.overrideSig.length > 0);

// 5. verifyEmergencyOverride with correct EOK → { valid: true }
const eokCache = new Map([[eokResult.eok.eokId, eokResult.eok]]);
const vEok = ltx.verifyEmergencyOverride(override, eokCache);
check('verifyEmergencyOverride correct EOK → valid true', vEok.valid === true);

// 6. verifyEmergencyOverride with tampered action → { valid: false }
const tamperedOverride = { ...override, action: 'TAMPERED' };
const vTamperedEok = ltx.verifyEmergencyOverride(tamperedOverride, eokCache);
check('verifyEmergencyOverride tampered action → false', vTamperedEok.valid === false);

// 7. verifyEmergencyOverride with EOK not in cache → { valid: false, reason: 'key_not_in_cache' }
const emptyEokCache = new Map();
const vNoKey = ltx.verifyEmergencyOverride(override, emptyEokCache);
check('verifyEmergencyOverride no key → false',          vNoKey.valid === false);
check('verifyEmergencyOverride no key reason',           vNoKey.reason === 'key_not_in_cache');

// 8. createCoSig returns object with type === 'ACTION_COSIG'
const { nik: cosigNik1, privateKeyB64: cosigPriv1 } = ltx.generateNIK({ nodeLabel: 'Cosigner 1' });
const { nik: cosigNik2, privateKeyB64: cosigPriv2 } = ltx.generateNIK({ nodeLabel: 'Cosigner 2' });
const cosig1 = ltx.createCoSig('entry-001', 'plan-multi-001', cosigNik1.nodeId, cosigPriv1, cosigNik1);
check('createCoSig type ACTION_COSIG',                   cosig1.type === 'ACTION_COSIG');
check('createCoSig has entryId',                         cosig1.entryId === 'entry-001');
check('createCoSig has cosigSig',                        typeof cosig1.cosigSig === 'string' && cosig1.cosigSig.length > 0);

// 9. checkMultiAuth with 2 valid cosigs, requiredCount=2 → { authorised: true, validSigCount: 2 }
const cosig2 = ltx.createCoSig('entry-001', 'plan-multi-001', cosigNik2.nodeId, cosigPriv2, cosigNik2);
const multiKeyCache = new Map([
  [cosigNik1.nodeId, cosigNik1],
  [cosigNik2.nodeId, cosigNik2],
]);
const authResult2 = ltx.checkMultiAuth([cosig1, cosig2], 'entry-001', 'plan-multi-001', multiKeyCache, 2);
check('checkMultiAuth 2/2 valid → authorised true',     authResult2.authorised === true);
check('checkMultiAuth 2/2 validSigCount == 2',          authResult2.validSigCount === 2);

// 10. checkMultiAuth with 1 valid cosig, requiredCount=2 → { authorised: false }
const authResult1 = ltx.checkMultiAuth([cosig1], 'entry-001', 'plan-multi-001', multiKeyCache, 2);
check('checkMultiAuth 1/2 → authorised false',          authResult1.authorised === false);
check('checkMultiAuth 1/2 validSigCount == 1',          authResult1.validSigCount === 1);

// Additional: invalid cosig (wrong planId) is counted as invalid
const wrongPlanCosig = { ...cosig1, planId: 'wrong-plan' };
const authResultWrong = ltx.checkMultiAuth([wrongPlanCosig, cosig2], 'entry-001', 'plan-multi-001', multiKeyCache, 2);
check('checkMultiAuth wrong planId → invalidCount 1',   authResultWrong.invalidCount === 1);
check('checkMultiAuth 1 valid, 1 invalid → false',      authResultWrong.authorised === false);

// ── Security: Window Manifests ────────────────────────────────────────────

console.log('\n── Security: Window Manifests ────────────────────────────────');

// Setup: generate a NIK and a signed tree head
const { nik: wmNik, privateKeyB64: wmPriv } = ltx.generateNIK({ nodeLabel: 'Manifest Signer' });
const wmLog = ltx.createMerkleLog();
for (let i = 1; i <= 47; i++) wmLog.append({ seq: i });
const wmTreeHead = wmLog.signTreeHead(wmPriv, wmNik.nodeId);

const wmArtefacts = [
  { name: 'tx-content', sha256: ltx.artefactSha256('hello world'), sizeBytes: 11 },
];

// 1. artefactSha256('hello') returns a 64-char hex string
const wmHash = ltx.artefactSha256('hello');
check('artefactSha256 returns 64-char hex',   typeof wmHash === 'string' && wmHash.length === 64);
check('artefactSha256 is hex chars',          /^[0-9a-f]{64}$/.test(wmHash));

// 2. createWindowManifest returns object with type === 'WINDOW_MANIFEST'
const wmManifest1 = ltx.createWindowManifest('plan-wm-001', 3, wmArtefacts, wmTreeHead, wmPriv);
check('createWindowManifest type WINDOW_MANIFEST', wmManifest1.type === 'WINDOW_MANIFEST');

// 3. manifest.windowSeq === 3
check('manifest.windowSeq === 3',             wmManifest1.windowSeq === 3);

// 4. manifest.nonceSalt is a non-empty string
check('manifest.nonceSalt is non-empty',      typeof wmManifest1.nonceSalt === 'string' && wmManifest1.nonceSalt.length > 0);

// 5. manifest.manifestSig is a non-empty string
check('manifest.manifestSig is non-empty',    typeof wmManifest1.manifestSig === 'string' && wmManifest1.manifestSig.length > 0);

// 6. Two calls produce different nonceSalt values (hedged)
const wmManifest2 = ltx.createWindowManifest('plan-wm-001', 3, wmArtefacts, wmTreeHead, wmPriv);
check('two calls produce different nonceSalt', wmManifest1.nonceSalt !== wmManifest2.nonceSalt);

// 7. verifyWindowManifest with correct key cache → { valid: true }
const wmKeyCache = new Map([[wmNik.nodeId, wmNik]]);
const wmVerify1 = ltx.verifyWindowManifest(wmManifest1, wmKeyCache);
check('verifyWindowManifest valid → true',    wmVerify1.valid === true);

// 8. verifyWindowManifest with tampered artefact sha256 → { valid: false }
const wmTampered = JSON.parse(JSON.stringify(wmManifest1));
wmTampered.artefacts[0].sha256 = 'a'.repeat(64);
const wmVerify2 = ltx.verifyWindowManifest(wmTampered, wmKeyCache);
check('verifyWindowManifest tampered → false', wmVerify2.valid === false);

// 9. verifyWindowManifest with key not in cache → { valid: false, reason: 'key_not_in_cache' }
const { nik: wmWrongNik } = ltx.generateNIK();
const wmWrongCache = new Map([[wmWrongNik.nodeId, wmWrongNik]]);
const wmVerify3 = ltx.verifyWindowManifest(wmManifest1, wmWrongCache);
check('verifyWindowManifest no key → false',  wmVerify3.valid === false);
check('verifyWindowManifest no key reason',   wmVerify3.reason === 'key_not_in_cache');

// 10. hedgedSign returns { signature, nonceSalt }
const { nik: hsNik, privateKeyB64: hsPriv } = ltx.generateNIK();
const hsData = Buffer.from('test data for hedged sign');
const hsResult = ltx.hedgedSign(hsData, hsPriv);
check('hedgedSign returns signature',         typeof hsResult.signature === 'string' && hsResult.signature.length > 0);
check('hedgedSign returns nonceSalt',         typeof hsResult.nonceSalt === 'string' && hsResult.nonceSalt.length > 0);

// 11. hedgedVerify with correct params → true
const hvValid = ltx.hedgedVerify(hsData, hsResult.signature, hsResult.nonceSalt, hsNik.publicKey);
check('hedgedVerify correct → true',          hvValid === true);

// 12. hedgedVerify with tampered data → false
const hvTampered = ltx.hedgedVerify(Buffer.from('tampered data'), hsResult.signature, hsResult.nonceSalt, hsNik.publicKey);
check('hedgedVerify tampered data → false',   hvTampered === false);

// ── Security: Conjunction Checkpoints ─────────────────────────────────────

console.log('\n── Security: Conjunction Checkpoints ────────────────────────');

// Setup: generate a NIK for signing, build a merkle log and sequence tracker
const { nik: cpNik, privateKeyB64: cpPriv } = ltx.generateNIK({ nodeLabel: 'Mission Control' });
const { nik: cpNik2 } = ltx.generateNIK({ nodeLabel: 'Mars Hab' });
const cpKeyCache = new Map([[cpNik.nodeId, cpNik], [cpNik2.nodeId, cpNik2]]);

const cpLog = ltx.createMerkleLog();
cpLog.append({ type: 'TX', seq: 1, data: 'hello' });
cpLog.append({ type: 'RX', seq: 2, data: 'world' });
for (let i = 3; i <= 10; i++) cpLog.append({ seq: i });
const cpMerkleRoot = cpLog.rootHex();
const cpTreeSize   = cpLog.treeSize();

const cpLastSeq = { N0: 147, N1: 89 };
const cpConjInfo = {
  conjunctionStart: '2026-09-01T00:00:00.000Z',
  conjunctionEnd:   '2026-09-25T00:00:00.000Z',
};

// 1. createConjunctionCheckpoint returns type === 'CONJUNCTION_CHECKPOINT'
const cpCheckpoint = ltx.createConjunctionCheckpoint(
  'plan-cp-001', cpNik.nodeId, cpConjInfo, cpMerkleRoot, cpTreeSize, cpLastSeq, cpPriv
);
check('createConjunctionCheckpoint type correct', cpCheckpoint.type === 'CONJUNCTION_CHECKPOINT');

// 2. checkpoint.checkpointSig is non-empty
check('checkpoint.checkpointSig non-empty',       typeof cpCheckpoint.checkpointSig === 'string' && cpCheckpoint.checkpointSig.length > 0);

// 3. checkpoint.merkleRoot === expectedRoot
check('checkpoint.merkleRoot matches',            cpCheckpoint.merkleRoot === cpMerkleRoot);

// 4. checkpoint.lastSeqPerNode contains expected values
check('checkpoint.lastSeqPerNode N0 == 147',      cpCheckpoint.lastSeqPerNode.N0 === 147);
check('checkpoint.lastSeqPerNode N1 == 89',       cpCheckpoint.lastSeqPerNode.N1 === 89);

// 5. verifyConjunctionCheckpoint with correct keyCache → { valid: true }
const cpVerifyOk = ltx.verifyConjunctionCheckpoint(cpCheckpoint, cpKeyCache);
check('verifyConjunctionCheckpoint valid → true', cpVerifyOk.valid === true);

// 6. verifyConjunctionCheckpoint with tampered merkleRoot → { valid: false }
const cpTampered = { ...cpCheckpoint, merkleRoot: '0'.repeat(64) };
const cpVerifyTampered = ltx.verifyConjunctionCheckpoint(cpTampered, cpKeyCache);
check('verifyConjunctionCheckpoint tampered → false', cpVerifyTampered.valid === false);

// 7. verifyConjunctionCheckpoint with empty keyCache → { valid: false, reason: 'key_not_in_cache' }
const cpVerifyEmpty = ltx.verifyConjunctionCheckpoint(cpCheckpoint, new Map());
check('verifyConjunctionCheckpoint empty cache → false',  cpVerifyEmpty.valid === false);
check('verifyConjunctionCheckpoint empty cache reason',   cpVerifyEmpty.reason === 'key_not_in_cache');

// 8. createPostConjunctionQueue — enqueue + size work correctly
const cpQueue = ltx.createPostConjunctionQueue();
const sz1 = cpQueue.enqueue({ type: 'TX', seq: 1 });
const sz2 = cpQueue.enqueue({ type: 'RX', seq: 2 });
const sz3 = cpQueue.enqueue({ type: 'TX', seq: 3 });
check('enqueue returns incrementing size',        sz1 === 1 && sz2 === 2 && sz3 === 3);
check('queue.size() == 3',                        cpQueue.size() === 3);
check('getQueue returns copy of 3 items',         cpQueue.getQueue().length === 3);

// 9. drain(fn) returns { cleared, rejected } counts
const drainResult = cpQueue.drain(bundle => ({ valid: bundle.type === 'TX' }));
check('drain cleared == 2',                       drainResult.cleared === 2);
check('drain rejected == 1',                      drainResult.rejected === 1);
check('drain rejectedBundles has 1 entry',        drainResult.rejectedBundles.length === 1 && drainResult.rejectedBundles[0].type === 'RX');
check('queue is empty after drain',               cpQueue.size() === 0);

// 10. createPostConjunctionClear returns type === 'POST_CONJUNCTION_CLEAR'
const cpClear = ltx.createPostConjunctionClear('plan-cp-001', 42, cpPriv);
check('createPostConjunctionClear type correct',  cpClear.type === 'POST_CONJUNCTION_CLEAR');
check('cpClear.queueProcessed == 42',             cpClear.queueProcessed === 42);
check('cpClear.clearSig non-empty',               typeof cpClear.clearSig === 'string' && cpClear.clearSig.length > 0);

// 11. verifyPostConjunctionClear with correct keyCache → { valid: true, signerNodeId }
const cpClearVerify = ltx.verifyPostConjunctionClear(cpClear, cpKeyCache);
check('verifyPostConjunctionClear valid → true',  cpClearVerify.valid === true);
check('verifyPostConjunctionClear signerNodeId',  cpClearVerify.signerNodeId === cpNik.nodeId);

// 12. verifyPostConjunctionClear with wrong keyCache → { valid: false }
const { nik: cpWrongNik } = ltx.generateNIK();
const cpWrongCache = new Map([[cpWrongNik.nodeId, cpWrongNik]]);
const cpClearBadVerify = ltx.verifyPostConjunctionClear(cpClear, cpWrongCache);
check('verifyPostConjunctionClear wrong key → false', cpClearBadVerify.valid === false);

// ── Security: Release Manifests ──────────────────────────────────────────

console.log('\n── Security: Release Manifests ──────────────────────────────');

// 1. generateRSK_keys: both keys are non-empty strings
const rsk = ltx.generateRSK();
check('generateRSK_keys privateKeyB64 non-empty',  typeof rsk.privateKeyB64 === 'string' && rsk.privateKeyB64.length > 0);
check('generateRSK_keys publicKeyB64 non-empty',   typeof rsk.publicKeyB64  === 'string' && rsk.publicKeyB64.length  > 0);

// 2. manifest_roundtrip: createManifest + verifyManifest with correct RSK → valid=true, files matches
const rmFiles = [
  { path: 'dist/ltx-sdk.js',     content: Buffer.from('console.log("ltx")') },
  { path: 'dist/ltx-sdk.min.js', content: Buffer.from('console.log("ltx-min")') },
];
const rmManifest = ltx.createManifest('ltx-sdk', '1.0.0', rmFiles, rsk.privateKeyB64);
const rmVerify   = ltx.verifyManifest(rmManifest, rsk.publicKeyB64);
check('manifest_roundtrip valid === true',         rmVerify.valid === true);
check('manifest_roundtrip files length matches',   Array.isArray(rmVerify.files) && rmVerify.files.length === 2);
check('manifest_roundtrip files[0].path matches',  rmVerify.files[0].path === 'dist/ltx-sdk.js');

// 3. manifest_tamper_file: change a file sha256 in the manifest, verify → valid=false (bad_signature)
const rmTampered = { ...rmManifest, files: [
  { path: rmManifest.files[0].path, sha256: '0'.repeat(64) },
  rmManifest.files[1],
]};
const rmTamperedVerify = ltx.verifyManifest(rmTampered, rsk.publicKeyB64);
check('manifest_tamper_file valid === false',      rmTamperedVerify.valid === false);
check('manifest_tamper_file reason bad_signature', rmTamperedVerify.reason === 'bad_signature');

// 4. manifest_wrong_key: createManifest with RSK_A, verify with RSK_B public key → valid=false (key_mismatch)
const rskB      = ltx.generateRSK();
const rmWrongKey = ltx.verifyManifest(rmManifest, rskB.publicKeyB64);
check('manifest_wrong_key valid === false',        rmWrongKey.valid === false);
check('manifest_wrong_key reason key_mismatch',    rmWrongKey.reason === 'key_mismatch');

// 5. manifest_file_sha256: sha256 of Buffer.from('hello') matches known value
const rmHelloFiles = [{ path: 'hello.txt', content: Buffer.from('hello') }];
const rmHelloManifest = ltx.createManifest('test-pkg', '0.1.0', rmHelloFiles, rsk.privateKeyB64);
const expectedSha256  = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
check('manifest_file_sha256 matches known value',  rmHelloManifest.files[0].sha256 === expectedSha256);


// ── Security: BCB Confidentiality ─────────────────────────────────────────

console.log('\n── Security: BCB Confidentiality ────────────────────────────');

// 1. encrypt_decrypt_roundtrip
const bcbKey = ltx.generateSessionKey();
const bcbPayload = { msg: 'hello', seq: 1 };
const bcbEncrypted = ltx.encryptWindow(bcbPayload, bcbKey);
const bcbDecrypted = ltx.decryptWindow(bcbEncrypted, bcbKey);
check('encrypt_decrypt_roundtrip valid',   bcbDecrypted.valid === true);
check('encrypt_decrypt_roundtrip msg',     bcbDecrypted.plaintext && bcbDecrypted.plaintext.msg === 'hello');

// 2. tag_mismatch: tamper ciphertext
const bcbTampered = Object.assign({}, bcbEncrypted);
const ctChars = bcbTampered.ciphertext.split('');
ctChars[0] = ctChars[0] === 'A' ? 'B' : 'A';
bcbTampered.ciphertext = ctChars.join('');
const bcbTamperedResult = ltx.decryptWindow(bcbTampered, bcbKey);
check('tag_mismatch valid=false',          bcbTamperedResult.valid === false);
check('tag_mismatch reason',               bcbTamperedResult.reason === 'tag_mismatch');

// 3. wrong_key: encrypt with keyA, decrypt with keyB
const bcbKeyA = ltx.generateSessionKey();
const bcbKeyB = ltx.generateSessionKey();
const bcbEncA = ltx.encryptWindow({ secret: 42 }, bcbKeyA);
const bcbWrongKey = ltx.decryptWindow(bcbEncA, bcbKeyB);
check('wrong_key valid=false',             bcbWrongKey.valid === false);
check('wrong_key reason',                  bcbWrongKey.reason === 'tag_mismatch');

// 4. not_bcb: wrong type
const bcbNotBcb = ltx.decryptWindow({ type: 'TX', nonce: 'a', ciphertext: 'b', tag: 'c' }, bcbKey);
check('not_bcb valid=false',               bcbNotBcb.valid === false);
check('not_bcb reason',                    bcbNotBcb.reason === 'not_bcb');

// 5. generateSessionKey_length
check('generateSessionKey_length',         ltx.generateSessionKey().length === 32);

// 6. nonce_uniqueness
const bcbEnc1 = ltx.encryptWindow({ x: 1 }, bcbKey);
const bcbEnc2 = ltx.encryptWindow({ x: 1 }, bcbKey);
check('nonce_uniqueness',                  bcbEnc1.nonce !== bcbEnc2.nonce);

// ── Security Suite (§22.1 — Story 28.10) ──────────────────────────────────

const secSuite = require('./security_suite');
passed += secSuite.passed();
failed += secSuite.failed();

// ── Summary ────────────────────────────────────────────────────────────────

console.log('\n══════════════════════════════════════════');
console.log(`${passed} passed  ${failed} failed`);
if (failed > 0) process.exit(1);
