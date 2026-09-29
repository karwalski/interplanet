'use strict';
/**
 * run.js — Runs all replication-kit tests (IP-R2, Refs #19).
 * Run: node tests/run.js
 */

(async () => {
  let passed = 0;
  let failed = 0;
  for (const t of ['./relay.test', './scoring.test']) {
    const r = await require(t)();
    passed += r.passed;
    failed += r.failed;
  }
  console.log(`\nreplication kit total: ${passed} passed  ${failed} failed`);
  if (failed > 0) process.exit(1);
})();
