'use strict';
/**
 * cross_sdk_verify_ts.js — TypeScript SDK verifier side of the cross-SDK integration test.
 * Reads a JSON blob from stdin (produced by cross_sdk_sign_py.py or cross_sdk_sign_ts.js)
 * and verifies the signed plan using the TypeScript SDK (CJS build).
 *
 * Exits 0 on success, 1 on failure.
 */

const ltx = require('../typescript/ltx/dist/cjs/index.js');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  let parsed;
  try {
    parsed = JSON.parse(input);
  } catch (e) {
    console.error('ERROR: failed to parse JSON input:', e.message);
    process.exit(1);
  }

  const { nik, signed_envelope: signedEnvelope } = parsed;

  if (!nik || !signedEnvelope) {
    console.error('ERROR: input must have nik and signed_envelope fields');
    process.exit(1);
  }

  // Build key cache using the provided NIK
  const keyCache = new Map([[nik.nodeId, nik]]);

  const result = ltx.verifyPlan(signedEnvelope, keyCache);

  if (result.valid) {
    console.log('PASS: TypeScript verifyPlan → valid=true');
    process.exit(0);
  } else {
    console.error(`FAIL: TypeScript verifyPlan → valid=false, reason=${result.reason}`);
    process.exit(1);
  }
});
