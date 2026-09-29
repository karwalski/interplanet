// TypeScript port (typescript/planet-time, built dist/cjs). Usage: node probe_ts.js <inputs.txt>
'use strict';
const fs = require('fs');
const ipt = require('../../../../typescript/planet-time/dist/cjs/index.js');

const out = [];
for (const line of fs.readFileSync(process.argv[2], 'utf8').split('\n')) {
  if (!line.trim()) continue;
  const [body, s] = line.trim().split(' ');
  const ms = Number(s);
  const pt = ipt.getPlanetTime(body, ms, 0);
  const light = (body === 'earth' || body === 'moon') ? '-' : ipt.lightTravelSeconds('earth', body, ms).toFixed(3);
  let mtc = ['-', '-', '-', '-'];
  if (body === 'mars') { const m = ipt.getMTC(ms); mtc = [m.sol, m.hour, m.minute, m.second]; }
  out.push([body, ms, pt.hour, pt.minute, pt.second, pt.dayNumber, light, ...mtc].join('\t'));
}
process.stdout.write(out.join('\n') + '\n');
