#!/usr/bin/env node
'use strict';

/**
 * interplanet — CLI for planetary time, light-travel delay, and meeting windows.
 *
 * Commands:
 *   interplanet time <planet> [--tz <offset>]   — local time on a planet
 *   interplanet mtc                              — Mars Coordinated Time
 *   interplanet light-travel <from> <to>         — one-way light travel (seconds)
 *   interplanet distance <from> <to>             — distance in AU and km
 *   interplanet windows <a> <b> [--days <n>]     — overlapping work windows
 *   interplanet los <a> <b>                      — line-of-sight status
 *   interplanet planets                          — list supported planets
 *   interplanet ltx <sub> <nodes...>             — LTX session planning
 *   interplanet help                             — show usage
 *
 * <planet>/<from>/<to> accepts: mercury venus earth mars jupiter saturn uranus neptune
 */

const path = require('path');
const PT = require(path.resolve(__dirname, '../../javascript/planet-time/planet-time.js'));
const LTX = require(path.resolve(__dirname, '../../javascript/ltx/ltx-sdk.js'));

const PLANETS = PT.PLANETS || {};
const PLANET_KEYS = Object.keys(PLANETS);

// ── Helpers ───────────────────────────────────────────────────────────────────

function die(msg) {
  process.stderr.write('error: ' + msg + '\n');
  process.exit(1);
}

function validatePlanet(key) {
  if (!PLANET_KEYS.includes(key)) die('Unknown planet "' + key + '". Run "interplanet planets" for the list.');
}

function parseArgs(argv) {
  const args = { positional: [], flags: {} };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const flag = argv[i].slice(2);
      args.flags[flag] = argv[i + 1] !== undefined && !argv[i + 1].startsWith('--')
        ? argv[++i]
        : true;
    } else {
      args.positional.push(argv[i]);
    }
  }
  return args;
}

function pad2(n) { return String(n).padStart(2, '0'); }

function fmtTime(pt) {
  return pad2(pt.hour) + ':' + pad2(pt.minute) + ':' + pad2(pt.second);
}

function fmtLightTime(s) { return PT.formatLightTime(s); }

// ── Commands ──────────────────────────────────────────────────────────────────

function cmdTime(args) {
  const planet = args.positional[0];
  if (!planet) die('Usage: interplanet time <planet> [--tz <hours>]');
  validatePlanet(planet);
  const tz   = parseFloat(args.flags.tz || '0');
  const utcMs = Date.now();
  const pt   = PT.getPlanetTime(planet, new Date(utcMs), tz);
  const p    = PLANETS[planet];
  const name = p ? (p.name || planet) : planet;

  console.log('Planet   : ' + name + ' ' + (p && p.symbol ? p.symbol : ''));
  console.log('Local    : ' + fmtTime(pt));
  console.log('Day      : ' + pt.dayNumber);
  if (planet === 'mars') {
    const si = pt.solInfo;
    if (si) console.log('Sol      : ' + si.solInYear + ' / ' + si.solsPerYear);
  }
  console.log('Work hr  : ' + (pt.isWorkHour ? 'yes' : 'no') + ' (' + (pt.isWorkPeriod ? 'work period' : 'rest period') + ')');
  console.log('UTC now  : ' + new Date(utcMs).toISOString());
}

function cmdMTC(args) {
  const utcMs = Date.now();
  const mtc = PT.getMTC(new Date(utcMs));
  console.log('MTC      : ' + pad2(mtc.hour) + ':' + pad2(mtc.minute) + ':' + pad2(mtc.second));
  console.log('Sol      : ' + mtc.sol);
  console.log('UTC now  : ' + new Date(utcMs).toISOString());
}

function cmdLightTravel(args) {
  const [a, b] = args.positional;
  if (!a || !b) die('Usage: interplanet light-travel <from> <to>');
  validatePlanet(a); validatePlanet(b);
  const now = new Date();
  const lt = PT.lightTravelSeconds(a, b, now);
  console.log('From     : ' + a);
  console.log('To       : ' + b);
  console.log('One-way  : ' + lt.toFixed(1) + ' s  (' + fmtLightTime(lt) + ')');
  console.log('Round-trip: ' + (lt * 2).toFixed(1) + ' s  (' + fmtLightTime(lt * 2) + ')');
  console.log('UTC now  : ' + now.toISOString());
}

function cmdDistance(args) {
  const [a, b] = args.positional;
  if (!a || !b) die('Usage: interplanet distance <from> <to>');
  validatePlanet(a); validatePlanet(b);
  const now   = new Date();
  const lt    = PT.lightTravelSeconds(a, b, now);
  const AU_KM = 149597870.7;
  const C_KMS = 299792.458;
  const au    = lt / (AU_KM / C_KMS);
  console.log('From     : ' + a);
  console.log('To       : ' + b);
  console.log('Distance : ' + au.toFixed(4) + ' AU');
  console.log('         : ' + (au * AU_KM).toFixed(0) + ' km');
  console.log('UTC now  : ' + now.toISOString());
}

function cmdWindows(args) {
  const [a, b] = args.positional;
  if (!a || !b) die('Usage: interplanet windows <a> <b> [--days <n>]');
  validatePlanet(a); validatePlanet(b);
  const days  = parseInt(args.flags.days  || '7', 10);
  const now   = new Date();
  const wins  = PT.findMeetingWindows(a, b, days, now);
  console.log('From    : ' + a + '  To: ' + b);
  console.log('Horizon : ' + days + ' day(s)');
  if (!wins.length) {
    console.log('No overlapping work windows found.');
    return;
  }
  wins.forEach((w, i) => {
    const start = new Date(w.startMs).toISOString().replace('T', ' ').slice(0, 16);
    const end   = new Date(w.endMs).toISOString().replace('T', ' ').slice(0, 16);
    console.log('  [' + (i + 1) + '] ' + start + ' \u2192 ' + end + '  (' + w.durationMinutes + ' min)');
  });
}

function cmdLOS(args) {
  const [a, b] = args.positional;
  if (!a || !b) die('Usage: interplanet los <a> <b>');
  validatePlanet(a); validatePlanet(b);
  const now    = new Date();
  const los    = PT.checkLineOfSight(a, b, now);
  const status = los.blocked ? 'BLOCKED' : los.degraded ? 'DEGRADED' : 'CLEAR';
  console.log('From     : ' + a);
  console.log('To       : ' + b);
  console.log('Status   : ' + status);
  console.log('Elong    : ' + los.elongDeg.toFixed(2) + '\u00b0');
  if (los.closestSunAu != null)
    console.log('Sun dist : ' + los.closestSunAu.toFixed(4) + ' AU');
  console.log('UTC now  : ' + now.toISOString());
}

function cmdPlanets() {
  console.log('Supported planets:');
  PLANET_KEYS.forEach(k => {
    const p = PLANETS[k];
    console.log('  ' + k.padEnd(10) + ' ' + (p && p.symbol ? p.symbol : ' ') + '  ' + (p && p.name ? p.name : k));
  });
}

function cmdHelp() {
  console.log([
    'interplanet \u2014 Interplanetary Time CLI v0.1.0',
    '',
    'Commands:',
    '  time <planet> [--tz <h>]      Local time on a planet',
    '  mtc                           Mars Coordinated Time',
    '  light-travel <from> <to>      One-way light travel time',
    '  distance <from> <to>          Distance in AU and km',
    '  windows <a> <b> [--days <n>]  Overlapping work windows (default 7 days, 15-min step)',
    '  los <a> <b>                   Line-of-sight status',
    '  planets                       List all supported planets',
    '  ltx <sub> <nodes...>          LTX (Light-Time eXchange) session planning',
    '  help                          Show this help',
    '',
    'Examples:',
    '  interplanet time mars',
    '  interplanet light-travel earth mars',
    '  interplanet windows earth mars --days 14',
    '  interplanet los earth mars',
    '  interplanet ltx hash "Earth HQ:host:earth" "Mars Base:participant:mars"',
  ].join('\n'));
}

// ── LTX helpers ───────────────────────────────────────────────────────────────

/**
 * Parse a node string 'name:role:location[:delaySec]' into a node object.
 * e.g. 'Earth HQ:host:earth' or 'Mars Base:participant:mars:1240'
 */
function parseNodeStr(str) {
  const parts = str.split(':');
  if (parts.length < 3) die('Invalid node format "' + str + '" \u2014 expected name:role:location[:delaySec]');
  const name     = parts[0].trim();
  const role     = parts[1].trim().toUpperCase();
  const location = parts[2].trim().toLowerCase();
  const delay    = parts[3] !== undefined ? parseInt(parts[3], 10) : 0;
  if (!name)     die('Node name is empty in "' + str + '"');
  if (!location) die('Node location is empty in "' + str + '"');
  return { name, role, location, delay };
}

/**
 * Build an LTX plan from parsed CLI positional args (node strings).
 */
function buildPlanFromArgs(args) {
  const nodeStrs = args.positional;
  if (!nodeStrs.length) die('Usage: interplanet ltx <subcmd> <node1:role:location> [<node2> ...]');
  const nodes = nodeStrs.map(function(s, i) {
    const n = parseNodeStr(s);
    return { id: 'N' + i, name: n.name, role: n.role, location: n.location, delay: n.delay };
  });
  const opts = { nodes: nodes };
  if (args.flags.title)   opts.title   = args.flags.title;
  if (args.flags.start)   opts.start   = args.flags.start;
  if (args.flags.quantum) opts.quantum = parseInt(args.flags.quantum, 10);
  if (args.flags.mode)    opts.mode    = args.flags.mode;
  return LTX.createPlan(opts);
}

// ── LTX subcommands ───────────────────────────────────────────────────────────

function cmdLtxPlan(args) {
  const plan = buildPlanFromArgs(args);
  console.log(JSON.stringify(plan, null, 2));
}

function cmdLtxSegments(args) {
  const plan = buildPlanFromArgs(args);
  const segs = LTX.computeSegments(plan);
  segs.forEach(function(s) {
    const startMs = s.start.getTime();
    const endMs   = s.end.getTime();
    console.log(s.type + ' (' + startMs + '\u2013' + endMs + ', ' + s.durMin + 'm)');
  });
}

function cmdLtxHash(args) {
  const plan = buildPlanFromArgs(args);
  console.log(LTX.encodeHash(plan));
}

function cmdLtxICS(args) {
  const plan = buildPlanFromArgs(args);
  process.stdout.write(LTX.generateICS(plan));
  process.stdout.write('\n');
}

async function cmdLtxSend(args) {
  const plan   = buildPlanFromArgs(args);
  const apiUrl = args.flags.api || undefined;
  try {
    const result = await LTX.storeSession(plan, apiUrl);
    console.log(JSON.stringify(result, null, 2));
  } catch (e) {
    die('ltx send failed: ' + e.message);
  }
}

function cmdLtxHelp() {
  console.log([
    'interplanet ltx \u2014 LTX (Light-Time eXchange) subcommands',
    '',
    'Usage:',
    '  ltx plan     <node1:role:location> [<node2> ...] [--title "T"] [--start ISO] [--quantum N] [--mode async|sync]',
    '  ltx segments <node1:role:location> [<node2> ...]',
    '  ltx hash     <node1:role:location> [<node2> ...]',
    '  ltx ics      <node1:role:location> [<node2> ...]',
    '  ltx send     <node1:role:location> [<node2> ...] [--api URL]',
    '',
    'Node format:  name:role:location[:delaySec]',
    '  e.g.  "Earth HQ:host:earth"',
    '  e.g.  "Mars Base:participant:mars:1240"',
    '',
    'Examples:',
    '  interplanet ltx hash "Earth HQ:host:earth" "Mars Base:participant:mars"',
    '  interplanet ltx plan "Earth HQ:host:earth" "Mars Base:participant:mars:1240" --title "Daily Sync"',
    '  interplanet ltx ics  "Earth HQ:host:earth" "Mars Base:participant:mars:800"',
    '  interplanet ltx send "Earth HQ:host:earth" "Mars Base:participant:mars"',
  ].join('\n'));
}

async function cmdLtx(sub, args) {
  switch (sub) {
    case 'plan':     cmdLtxPlan(args);       break;
    case 'segments': cmdLtxSegments(args);   break;
    case 'hash':     cmdLtxHash(args);       break;
    case 'ics':      cmdLtxICS(args);        break;
    case 'send':     await cmdLtxSend(args); break;
    case 'help':
    case '--help':
    case undefined:  cmdLtxHelp();           break;
    default:
      process.stderr.write('Unknown ltx subcommand "' + sub + '". Run "interplanet ltx help".\n');
      process.exit(1);
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

const [,, cmd, ...rest] = process.argv;

(async () => {
  const args = parseArgs(rest);

  switch (cmd) {
    case 'time':         cmdTime(args);         break;
    case 'mtc':          cmdMTC(args);          break;
    case 'light-travel': cmdLightTravel(args);  break;
    case 'distance':     cmdDistance(args);     break;
    case 'windows':      cmdWindows(args);      break;
    case 'los':          cmdLOS(args);          break;
    case 'planets':      cmdPlanets();          break;
    case 'ltx':          await cmdLtx(args.positional[0], { positional: args.positional.slice(1), flags: args.flags }); break;
    case 'help':
    case '--help':
    case '-h':
    case undefined:      cmdHelp();             break;
    default:
      process.stderr.write('Unknown command "' + cmd + '". Run "interplanet help".\n');
      process.exit(1);
  }
})().catch(function(e) { process.stderr.write(e.message + '\n'); process.exit(1); });