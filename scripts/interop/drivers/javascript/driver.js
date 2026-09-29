'use strict';
// Baseline driver for the JavaScript reference SDK itself (javascript/ltx):
// checks that the harness agrees with the reference end to end.
const fs = require('fs');
const path = require('path');
const ltx = require(path.join(process.env.ROOT, 'javascript/ltx/ltx-sdk.js'));
const { REP, V3_EXTRAS } = require('../../plan.js');

const [inDir, outDir] = process.argv.slice(2);
const unhash = h => JSON.stringify(ltx.decodeHash(h));

const plan = ltx.createPlan(REP);
fs.writeFileSync(path.join(outDir, 'wire-v2.json'), unhash(ltx.encodeHash(plan)));
console.log('ID_V2', ltx.makePlanId(plan));

const v3 = ltx.upgradePlanToV3(plan, V3_EXTRAS);
fs.writeFileSync(path.join(outDir, 'wire-v3.json'), unhash(ltx.encodeHash(v3)));
console.log('ID_V3', ltx.makePlanId(v3));

for (const v of ['2', '3', 'P']) {
  const parsed = JSON.parse(fs.readFileSync(path.join(inDir, `js-v${v}.json`), 'utf8'));
  console.log(`JS_V${v}`, ltx.makePlanId(parsed));
}
