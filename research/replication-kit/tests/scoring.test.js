'use strict';
/**
 * scoring.test.js — Tests for scoring/score.js (IP-R2, Refs #19)
 * Synthetic logs plus one end-to-end run of the relay at a tiny time scale.
 * Run: node tests/scoring.test.js
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const score = require('../scoring/score');
const relayLib = require('../relay/relay');

let passed = 0;
let failed = 0;
function check(name, cond) {
  if (cond) { passed++; }
  else { failed++; console.log('FAIL:', name); }
}
const wait = ms => new Promise(r => setTimeout(r, ms));
const near = (a, b) => Math.abs(a - b) < 1e-9;

const scenarioA = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'scenarios', 'co2-removal.json'), 'utf8'));
const scenarioB = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'scenarios', 'o2-pressure.json'), 'utf8'));

async function main() {
  // ── Scenario files ──
  console.log('\n── Scoring: scenario files ──────────────────');
  for (const sc of [scenarioA, scenarioB]) {
    check(`${sc.id}: three roles, two sites`, Object.keys(sc.roles).length === 3
      && new Set(Object.values(sc.roles).map(r => r.site)).size === 2);
    check(`${sc.id}: faults have injections, items, keywords`, sc.faults.every(f =>
      f.injections.length > 0 && f.items.length > 0 && f.contextKeywords.length > 0));
    check(`${sc.id}: every item's first accepted answer is an option`, sc.faults.every(f =>
      f.items.every(i => i.options.map(score.normalise).includes(score.normalise(i.accepted[0])))));
    check(`${sc.id}: deadlines after injections`, sc.faults.every(f =>
      f.injections.every(i => i.atMin < f.resolveByMin) && f.resolveByMin <= sc.durationMin));
    check(`${sc.id}: patterns compile`, sc.scoring.clarificationPatterns.every(p => new RegExp(p, 'i')));
  }

  // ── Answer matching ──
  check('normalise case and spaces', score.normalise('  Fan_Motor  Degradation. ') === 'fan motor degradation');
  check('accepted variant matches', score.isCorrect(scenarioA.faults[0].items[1], 'ls7'));
  check('wrong answer rejected', !score.isCorrect(scenarioA.faults[0].items[1], 'LS-4'));

  // ── Synthetic session (timeScale 1, times in ms) ──
  console.log('\n── Scoring: synthetic session ───────────────');
  const M = 60000;
  const roles = scenarioA.roles;
  const base = { teamId: 'T01', conditionId: 'D10-P0' };
  const ev = [
    Object.assign({ event: 'config', tMs: 0, timeScale: 1 }, base),
    Object.assign({ event: 'session_start', tMs: 0, oneWayDelayMs: 10 * M, protocol: false,
      interruptionMode: 'hold', roles }, base),
    // crew1 -> fc at 3 min, delivered 13 min, with context
    { event: 'send', id: 'm-1:fc', msgId: 'm-1', from: 'crew1', to: 'fc', sentMs: 3 * M, heldMs: 0,
      text: 'F1 scrubber B fan current 1.2 A, delta-P 0.4 kPa, ppCO2 3.9.' },
    { event: 'deliver', id: 'm-1:fc', deliveredMs: 13 * M, tMs: 13 * M },
    // fc -> crew1 at 8 min (m-1 still in transit): crossed; clarification; no context keywords
    { event: 'send', id: 'm-2:crew1', msgId: 'm-2', from: 'fc', to: 'crew1', sentMs: 8 * M, heldMs: 0,
      text: 'What do you mean, anything new up there' },
    { event: 'deliver', id: 'm-2:crew1', deliveredMs: 18 * M, tMs: 18 * M },
    // crew2 -> crew1 same site: never a marker
    { event: 'send', id: 'm-3:crew1', msgId: 'm-3', from: 'crew2', to: 'crew1', sentMs: 9 * M, heldMs: 0,
      text: 'say again?' },
    { event: 'deliver', id: 'm-3:crew1', deliveredMs: 9 * M, tMs: 9 * M },
    // fc -> both crew at 20 min, one copy held 5 min by an outage
    { event: 'send', id: 'm-4:crew1', msgId: 'm-4', from: 'fc', to: 'crew1', sentMs: 20 * M, heldMs: 5 * M,
      text: 'F1: fan motor degradation, run LS-7.' },
    { event: 'send', id: 'm-4:crew2', msgId: 'm-4', from: 'fc', to: 'crew2', sentMs: 20 * M, heldMs: 5 * M,
      text: 'F1: fan motor degradation, run LS-7.' },
    { event: 'deliver', id: 'm-4:crew1', deliveredMs: 35 * M, tMs: 35 * M },
    { event: 'deliver', id: 'm-4:crew2', deliveredMs: 35 * M, tMs: 35 * M },
    // answers: F1 diagnosis wrong then right; F1 procedure right; F2 diagnosis right but late
    { event: 'answer', tMs: 30 * M, from: 'crew1', faultId: 'F1', itemId: 'diagnosis', answer: 'inlet filter blockage' },
    { event: 'answer', tMs: 36 * M, from: 'crew1', faultId: 'F1', itemId: 'diagnosis', answer: 'Fan motor degradation' },
    { event: 'answer', tMs: 37 * M, from: 'crew2', faultId: 'F1', itemId: 'procedure', answer: 'LS-7' },
    { event: 'answer', tMs: 100 * M, from: 'crew2', faultId: 'F2', itemId: 'first_procedure', answer: 'WS-5' },
    { event: 'answer', tMs: 141 * M, from: 'crew2', faultId: 'F2', itemId: 'diagnosis', answer: 'tank full' },
    { event: 'drop', tMs: 50 * M, id: 'x' },
    { event: 'session_end', tMs: 150 * M },
  ];
  const r = score.scoreSession(ev, scenarioA);
  const f1 = r.faults.find(f => f.faultId === 'F1');
  const f2 = r.faults.find(f => f.faultId === 'F2');
  check('ids carried', r.teamId === 'T01' && r.conditionId === 'D10-P0' && r.scenarioId === 'co2-removal');
  check('delay reported in minutes', r.oneWayDelayMin === 10);
  check('F1 completed correctly', f1.completed && f1.completedCorrectly && f1.accuracy === 1);
  check('F1 final answer is the last one', f1.items[0].finalAnswer === 'Fan motor degradation' && f1.items[0].attempts === 2);
  check('F1 time to correct from first injection', near(f1.items[0].timeToCorrectMin, 34));
  check('F2 not completed (late diagnosis)', !f2.completed && f2.items[0].lateAnswers === 1 && !f2.items[0].answered);
  check('F2 wrong procedure scored wrong', f2.items[1].answered && !f2.items[1].correct);
  check('completion counts', r.completion.faultsCompleted === 1 && r.completion.faults === 2);
  check('accuracy proportion', r.accuracy.correctItems === 2 && r.accuracy.items === 4 && r.accuracy.proportion === 0.5);
  check('clarification request counted once', r.missedContext.clarificationRequests === 1);
  check('same-site message ignored', !r.missedContext.markers.some(m => m.id === 'm-3:crew1'));
  check('crossed message detected', r.missedContext.crossedMessages === 1
    && r.missedContext.markers.find(m => m.type === 'crossed_message').inTransit[0] === 'm-1:fc');
  check('no-context message detected', r.missedContext.noContextRestatement === 1
    && r.missedContext.markers.find(m => m.type === 'no_context_restatement').id === 'm-2:crew1');
  check('delivery stats', r.delivery.messagesSent === 4 && r.delivery.crossSiteCopies === 4
    && r.delivery.heldByInterruption === 2 && r.delivery.meanHeldMin === 5 && r.delivery.dropped === 1);

  const sheet = score.parseCsv(score.codingSheet(ev, r));
  check('coding sheet one row per copy', sheet.length === 5);
  check('coding sheet carries auto markers',
    sheet.find(x => x.message_id === 'm-2:crew1').auto_markers.split(';').length === 3);
  check('coding sheet round-trips commas', sheet.find(x => x.message_id === 'm-1:fc').text.includes('1.2 A, delta-P'));

  check('log without session_start throws', (() => { try { score.scoreSession([], scenarioA); return false; } catch (e) { return true; } })());
  check('JSONL parse error names line', (() => { try { score.parseJsonl('{}\n{bad'); return false; } catch (e) { return /line 2/.test(e.message); } })());

  // ── NASA-TLX ──
  console.log('\n── Scoring: NASA-TLX import ─────────────────');
  const csv = [
    'participant_id,team_id,condition_id,role,mental,physical,temporal,performance,effort,frustration,w_mental,w_physical,w_temporal,w_performance,w_effort,w_frustration',
    'P1,T01,D10-P0,crew1,60,10,70,30,50,40,5,0,4,2,3,1',
    'P2,T01,D10-P0,crew2,60,10,70,30,50,40,,,,,,',
    '"P3",T01,D10-P0,fc,120,10,70,30,50,40,,,,,,',
    'P4,T02,D10-P0,fc,0,0,0,0,0,0,5,5,5,0,0,1',
  ].join('\r\n');
  const tlx = score.importTlx(csv);
  const p1 = tlx.participants.find(p => p.participantId === 'P1');
  check('raw TLX is mean of six', near(p1.rawTlx, 260 / 6));
  check('weighted TLX', near(p1.weightedTlx, (60 * 5 + 10 * 0 + 70 * 4 + 30 * 2 + 50 * 3 + 40 * 1) / 15));
  check('no weights gives null weighted', tlx.participants.find(p => p.participantId === 'P2').weightedTlx === null);
  check('out-of-range rating rejected', tlx.errors.some(e => /row 4: mental/.test(e)) && !tlx.participants.some(p => p.participantId === 'P3'));
  check('bad weights reported', tlx.errors.some(e => /row 5: weights/.test(e)));
  const t01 = tlx.teams.find(t => t.teamId === 'T01');
  check('team mean over valid rows', t01.n === 2 && near(t01.meanRawTlx, 260 / 6));
  check('missing id reported', score.importTlx('participant_id,team_id,condition_id,mental,physical,temporal,performance,effort,frustration\n,T1,C,1,1,1,1,1,1')
    .errors.some(e => /participant_id/.test(e)));

  // ── End-to-end: relay log scored ──
  console.log('\n── Scoring: relay end-to-end ────────────────');
  const scale = 0.0001; // 1 scenario minute = 6 ms
  const conditions = require('../conditions.json');
  const cond = conditions.conditions.find(c => c.id === 'D10-P1-INT');
  const logFile = path.join(os.tmpdir(), `score-e2e-${process.pid}.jsonl`);
  const relay = relayLib.createRelay(Object.assign(relayLib.conditionToSettings(cond, scale), {
    teamId: 'T09', conditionId: cond.id, roles: scenarioA.roles, log: logFile,
    injections: relayLib.scenarioInjections(scenarioA, scale),
  }));
  relay.log('config', { scenarioId: scenarioA.id, timeScale: scale });
  const crewSaw = [];
  relay.subscribe('crew1', m => crewSaw.push(m));
  relay.start();
  await wait(20); // about 3 scenario minutes: F1 alert has arrived
  check('e2e: briefing and F1 alert delivered to crew', crewSaw.some(m => /CAUTION F1/.test(m.text))
    && crewSaw.some(m => /You are the crew/.test(m.text)));
  relay.send('crew1', 'fc', 'F1 scrubber B fan 1.2 A, delta-P 0.4 kPa. Which procedure?');
  relay.answer('crew1', 'F1', 'diagnosis', 'fan motor degradation');
  relay.answer('crew2', 'F1', 'procedure', 'LS-7');
  relay.answer('crew2', 'F2', 'diagnosis', 'tank-full interlock');
  relay.answer('crew2', 'F2', 'first_procedure', 'WS-2');
  await wait(100);
  relay.close();
  const events = score.parseJsonl(fs.readFileSync(logFile, 'utf8'));
  fs.unlinkSync(logFile);
  const e2e = score.scoreSession(events, scenarioA);
  check('e2e: time scale read from log', e2e.timeScale === scale);
  check('e2e: delay recovered in minutes', near(e2e.oneWayDelayMin, 10));
  check('e2e: protocol flag', e2e.protocol === true);
  check('e2e: all faults completed correctly', e2e.completion.faultsCompletedCorrectly === 2 && e2e.accuracy.proportion === 1);
  check('e2e: message counted', e2e.delivery.messagesSent === 1);

  console.log('\n══════════════════════════════════════════');
  console.log(`scoring: ${passed} passed  ${failed} failed`);
  return { passed, failed };
}

module.exports = main;
if (require.main === module) main().then(x => { if (x.failed) process.exit(1); });
