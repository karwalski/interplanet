#!/usr/bin/env node
/**
 * compare.js: compare one port's probe output with expected.tsv.
 *
 *   node compare.js <expected.tsv> <port.tsv> <port name>
 *
 * Columns: body utc_ms hour minute second day_number light_s mtc_sol mtc_hour
 * mtc_minute mtc_second ("-" where not applicable). Everything must match
 * exactly except light_s, which may differ by up to 1 s. Prints each
 * disagreement (the first 20) and exits 1 if there is any.
 */
'use strict';

const fs = require('fs');
const [expFile, gotFile, port] = process.argv.slice(2);
const COLS = ['body', 'utc_ms', 'hour', 'minute', 'second', 'day_number', 'light_s',
  'mtc_sol', 'mtc_hour', 'mtc_minute', 'mtc_second'];
const LIGHT_TOL = 1.0;

const rows = (f) => fs.readFileSync(f, 'utf8').split('\n').filter((l) => l.trim()).map((l) => l.trim().split(/\t/));
const want = rows(expFile);
const got = rows(gotFile);

let bad = 0, maxLight = 0;
const report = [];
if (got.length !== want.length) {
  report.push(`row count ${got.length}, expected ${want.length}`);
  bad++;
}
for (let i = 0; i < Math.min(want.length, got.length); i++) {
  const w = want[i], g = got[i];
  if (g.length !== COLS.length) { bad++; report.push(`row ${i + 1}: ${g.length} columns: ${g.join(' ')}`); continue; }
  const diffs = [];
  for (let c = 0; c < COLS.length; c++) {
    if (COLS[c] === 'light_s' && w[c] !== '-' && g[c] !== '-') {
      const d = Math.abs(Number(w[c]) - Number(g[c]));
      if (!(d <= LIGHT_TOL)) diffs.push(`light_s ${g[c]} (JS ${w[c]}, off ${d.toFixed(3)} s)`);
      else maxLight = Math.max(maxLight, d);
    } else if (w[c] !== g[c]) {
      diffs.push(`${COLS[c]} ${g[c]} (JS ${w[c]})`);
    }
  }
  if (diffs.length) {
    bad++;
    report.push(`${w[0]} @ ${w[1]} (${new Date(Number(w[1])).toISOString()}): ${diffs.join(', ')}`);
  }
}
for (const line of report.slice(0, 20)) console.log(`  ${port}: ${line}`);
if (report.length > 20) console.log(`  ${port}: ... ${report.length - 20} more`);
const ok = want.length - bad;
console.log(`${port}: ${ok} of ${want.length} cases agree with planet-time.js` +
  ` (max light-time difference ${maxLight.toFixed(3)} s)`);
process.exit(bad ? 1 : 0);
