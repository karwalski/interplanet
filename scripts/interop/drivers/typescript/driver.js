'use strict';
// Interop driver for typescript/ltx, run against its compiled CommonJS build
// (see scripts/interop/run.js and ports.js).
const fs = require('fs');
const path = require('path');
const ltx = require('./build/ts/index.js');

const [inDir, outDir] = process.argv.slice(2);

const plan = ltx.createPlan({
  title: 'Réunion Mars 🚀',
  start: '2026-03-15T14:00:00.000Z',
  quantum: 3,
  mode: 'LTX-ASYNC',
  nodes: [
    { id: 'N0', name: 'Earth HQ', role: 'HOST', delay: 0, location: 'earth' },
    { id: 'N1', name: 'Mars Hab-01', role: 'PARTICIPANT', delay: 840, location: 'mars' },
    { id: 'N2', name: 'L-1 Gateway', role: 'PARTICIPANT', delay: 2, location: 'moon' },
  ],
  segments: [
    { type: 'PLAN_CONFIRM', q: 2 },
    { type: 'TX', q: 3, speaker: 'N0', label: 'Ouverture: état de la mission' },
    { type: 'RX', q: 3 },
    { type: 'TX', q: 2, speaker: 'N1', label: 'Réponse 🔴' },
    { type: 'BUFFER', q: 1 },
  ],
});

const unhash = h => Buffer.from(h.slice(3), 'base64url').toString('utf8');

fs.writeFileSync(path.join(outDir, 'wire-v2.json'), unhash(ltx.encodeHash(plan)));
console.log('ID_V2', ltx.makePlanId(plan));

const v3 = ltx.upgradePlanToV3(plan, { delays: { 'N1|N2': 842 } });
fs.writeFileSync(path.join(outDir, 'wire-v3.json'), unhash(ltx.encodeHash(v3)));
console.log('ID_V3', ltx.makePlanId(v3));

for (const v of ['2', '3', 'P']) {
  const parsed = JSON.parse(fs.readFileSync(path.join(inDir, `js-v${v}.json`), 'utf8'));
  console.log(`JS_V${v}`, ltx.makePlanId(parsed));
}
