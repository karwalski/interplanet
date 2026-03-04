'use strict';
/**
 * cross_sdk_sign_ts.js — TypeScript SDK signer side of the cross-SDK integration test.
 * Generates a NIK, signs a plan, and prints a JSON blob for the Python verifier.
 */

const ltx = require('../typescript/ltx/dist/cjs/index.js');

const { nik, privateKeyB64 } = ltx.generateNIK({ nodeLabel: 'TypeScript SDK Signer' });

const plan = ltx.createPlan({
  title: 'Cross-SDK Test',
  start: '2026-06-15T09:00:00.000Z',
  delay: 800,
});

const signedEnvelope = ltx.signPlan(plan, privateKeyB64);

const output = {
  nik,
  signed_envelope: signedEnvelope,
};

process.stdout.write(JSON.stringify(output) + '\n');
