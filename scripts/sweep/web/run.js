'use strict';
/**
 * Sweep web suite runner (issue #38). Serves a copy of demo/ under php -S
 * (so /api/*.php work, with a SQLite getDB stub) and runs every test file in
 * tests/ in Chromium via Playwright.
 *
 * Run: node scripts/sweep/web/run.js [--only <regex>] [--file <name>]
 * Exit status is non-zero when any test fails.
 */
const fs = require('fs');
const path = require('path');
const { startSite } = require('./lib/site');
const { Harness, results, setFilter } = require('./lib/harness');

(async () => {
  const args = process.argv.slice(2);
  const onlyIdx = args.indexOf('--only');
  if (onlyIdx !== -1) setFilter(new RegExp(args[onlyIdx + 1]));
  const fileIdx = args.indexOf('--file');
  const files = fs.readdirSync(path.join(__dirname, 'tests')).filter((f) => f.endsWith('.js')).sort()
    .filter((f) => fileIdx === -1 || f.startsWith(args[fileIdx + 1]));

  const site = await startSite();
  const h = new Harness(site.base);
  await h.start();
  try {
    for (const f of files) {
      console.log(`\n── ${f} ──`);
      await require(path.join(__dirname, 'tests', f))(h, site);
    }
  } finally {
    await h.stop();
    site.stop();
  }
  console.log(`\nexternal hosts stubbed: ${Array.from(h.external).sort().join(', ') || 'none'}`);
  console.log(`web sweep: ${results.passed} passed, ${results.failed} failed`);
  for (const f of results.failures) console.log('  FAILED: ' + f);
  process.exit(results.failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
