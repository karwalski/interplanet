'use strict';
/**
 * score.js — Scoring for the InterPlanet replication kit
 * Story IP-R2 (Refs #19)
 *
 * Reads a relay JSONL log and the scenario file and computes:
 *   - task completion per fault (every item answered before the fault deadline)
 *   - response accuracy against the scenario ground truth
 *   - missed-context markers (provisional, for human coding)
 *   - delivery statistics
 * Optionally imports NASA-TLX responses from CSV and exports a coding sheet.
 *
 * No dependencies.
 *
 * CLI:
 *   node score.js --log logs/T01-D10-P1-co2-removal.jsonl --scenario scenarios/co2-removal.json
 *                 [--tlx tlx.csv] [--coding-sheet coding.csv] [--out result.json]
 *                 [--time-scale 1]   (only needed if the log has no config event)
 */

const fs = require('fs');

const TLX_SCALES = ['mental', 'physical', 'temporal', 'performance', 'effort', 'frustration'];

// ── Parsing ──────────────────────────────────────────────────────────────────

function parseJsonl(text) {
  return text.split(/\r?\n/).filter(l => l.trim() !== '').map((l, i) => {
    try { return JSON.parse(l); } catch (e) { throw new Error(`JSONL line ${i + 1}: ${e.message}`); }
  });
}

/** Minimal RFC 4180 CSV parser (quoted fields, doubled quotes, CRLF). */
function parseCsv(text) {
  const rows = [];
  let row = [], field = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') q = false;
      else field += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(field); rows.push(row); row = []; field = '';
    } else field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  const nonEmpty = rows.filter(r => r.some(x => x.trim() !== ''));
  if (nonEmpty.length === 0) return [];
  const header = nonEmpty[0].map(h => h.trim().toLowerCase());
  return nonEmpty.slice(1).map(r => {
    const o = {};
    header.forEach((h, j) => { o[h] = (r[j] || '').trim(); });
    return o;
  });
}

function toCsv(rows, columns) {
  const esc = v => {
    const s = v === undefined || v === null ? '' : String(v);
    return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [columns.join(',')].concat(rows.map(r => columns.map(c => esc(r[c])).join(','))).join('\n') + '\n';
}

// ── Answer scoring ───────────────────────────────────────────────────────────

function normalise(s) {
  return String(s).toLowerCase().replace(/[\s_]+/g, ' ').trim().replace(/[.;:!]+$/, '').trim();
}

function isCorrect(item, answer) {
  const a = normalise(answer);
  return item.accepted.some(x => normalise(x) === a);
}

// ── Session scoring ──────────────────────────────────────────────────────────

/**
 * @param {object[]} events   parsed JSONL events from relay.js
 * @param {object} scenario
 * @param {{ timeScale?: number }} [opts]
 */
function scoreSession(events, scenario, opts) {
  const cfgEv = events.find(e => e.event === 'config');
  const startEv = events.find(e => e.event === 'session_start');
  if (!startEv) throw new Error('log has no session_start event');
  const scale = (opts && opts.timeScale !== undefined) ? opts.timeScale
    : (cfgEv && cfgEv.timeScale !== undefined ? cfgEv.timeScale : 1);
  const minMs = 60000 * scale;
  const roles = startEv.roles || scenario.roles;
  const siteOf = r => (roles[r] ? roles[r].site : null);

  const sends = events.filter(e => e.event === 'send');
  const deliveries = new Map(events.filter(e => e.event === 'deliver').map(e => [e.id, e.deliveredMs]));
  const answers = events.filter(e => e.event === 'answer');

  // ── Completion and accuracy ──
  const faults = scenario.faults.map(f => {
    const deadlineMs = f.resolveByMin * minMs;
    const firstInjMs = Math.min(...f.injections.map(i => i.atMin * minMs));
    const items = f.items.map(item => {
      const mine = answers.filter(a => a.faultId === f.id && a.itemId === item.id && a.tMs <= deadlineMs);
      const final = mine.length ? mine[mine.length - 1] : null;
      const firstCorrect = mine.find(a => isCorrect(item, a.answer));
      return {
        itemId: item.id,
        answered: !!final,
        finalAnswer: final ? final.answer : null,
        correct: final ? isCorrect(item, final.answer) : false,
        attempts: mine.length,
        timeToCorrectMin: firstCorrect ? (firstCorrect.tMs - firstInjMs) / minMs : null,
        lateAnswers: answers.filter(a => a.faultId === f.id && a.itemId === item.id && a.tMs > deadlineMs).length,
      };
    });
    const nCorrect = items.filter(i => i.correct).length;
    return {
      faultId: f.id,
      completed: items.every(i => i.answered),
      completedCorrectly: items.every(i => i.correct),
      accuracy: items.length ? nCorrect / items.length : null,
      items,
    };
  });

  // ── Missed-context markers (provisional) ──
  const patterns = ((scenario.scoring && scenario.scoring.clarificationPatterns) || []).map(p => new RegExp(p, 'i'));
  const crossSite = sends.filter(s => siteOf(s.from) !== siteOf(s.to));
  // One logical message may be queued to several recipients; mark per msgId.
  const seenMsg = new Set();
  const markers = [];
  const activeFaults = t => scenario.faults.filter(f =>
    Math.min(...f.injections.map(i => i.atMin * minMs)) <= t && t <= f.resolveByMin * minMs);

  for (const s of crossSite) {
    const key = `${s.msgId || s.id}`;
    const first = !seenMsg.has(key);
    seenMsg.add(key);
    // Clarification request.
    if (first && patterns.some(re => re.test(s.text))) {
      markers.push({ type: 'clarification_request', id: s.id, from: s.from, tMs: s.sentMs });
    }
    // Crossed message: sent while a message from the recipient to the sender was in transit.
    const inTransit = crossSite.filter(o => o.from === s.to && o.to === s.from && o.sentMs < s.sentMs
      && (o.dropped || !deliveries.has(o.id) || deliveries.get(o.id) > s.sentMs));
    if (inTransit.length) {
      markers.push({ type: 'crossed_message', id: s.id, from: s.from, tMs: s.sentMs, inTransit: inTransit.map(o => o.id) });
    }
    // No context restatement: mentions none of the active faults' keywords.
    const act = activeFaults(s.sentMs);
    if (first && act.length) {
      const text = s.text.toLowerCase();
      const hasCtx = act.some(f => (f.contextKeywords || []).some(k => text.includes(k.toLowerCase())));
      if (!hasCtx) markers.push({ type: 'no_context_restatement', id: s.id, from: s.from, tMs: s.sentMs });
    }
  }
  const count = t => markers.filter(m => m.type === t).length;

  // ── Delivery ──
  const held = crossSite.filter(s => s.heldMs > 0);
  const lastEv = events[events.length - 1];

  const nItems = faults.reduce((n, f) => n + f.items.length, 0);
  const nCorrect = faults.reduce((n, f) => n + f.items.filter(i => i.correct).length, 0);

  return {
    teamId: startEv.teamId || null,
    conditionId: startEv.conditionId || null,
    scenarioId: scenario.id,
    oneWayDelayMin: startEv.oneWayDelayMs / minMs,
    protocol: !!startEv.protocol,
    interruptionMode: startEv.interruptionMode,
    timeScale: scale,
    sessionMin: lastEv ? lastEv.tMs / minMs : 0,
    completion: {
      faultsCompleted: faults.filter(f => f.completed).length,
      faultsCompletedCorrectly: faults.filter(f => f.completedCorrectly).length,
      faults: faults.length,
    },
    accuracy: { correctItems: nCorrect, items: nItems, proportion: nItems ? nCorrect / nItems : null },
    faults,
    missedContext: {
      clarificationRequests: count('clarification_request'),
      crossedMessages: count('crossed_message'),
      noContextRestatement: count('no_context_restatement'),
      markers,
      note: 'Automatic markers are provisional proxies. Confirm with human coding before analysis.',
    },
    delivery: {
      messagesSent: new Set(sends.map(s => s.msgId || s.id)).size,
      crossSiteCopies: crossSite.length,
      heldByInterruption: held.length,
      meanHeldMin: held.length ? held.reduce((n, s) => n + s.heldMs, 0) / held.length / minMs : 0,
      dropped: events.filter(e => e.event === 'drop').length,
    },
  };
}

/** One row per sent message copy, with automatic markers, for human coders. */
function codingSheet(events, result) {
  const byId = {};
  for (const m of result.missedContext.markers) (byId[m.id] = byId[m.id] || []).push(m.type);
  const deliveries = new Map(events.filter(e => e.event === 'deliver').map(e => [e.id, e.deliveredMs]));
  const rows = events.filter(e => e.event === 'send').map(s => ({
    team_id: result.teamId, condition_id: result.conditionId, message_id: s.id,
    from: s.from, to: s.to, sent_ms: s.sentMs, delivered_ms: deliveries.has(s.id) ? deliveries.get(s.id) : '',
    auto_markers: (byId[s.id] || []).join(';'), coder_markers: '', coder_id: '', text: s.text,
  }));
  return toCsv(rows, ['team_id', 'condition_id', 'message_id', 'from', 'to', 'sent_ms', 'delivered_ms',
    'auto_markers', 'coder_markers', 'coder_id', 'text']);
}

// ── NASA-TLX import ──────────────────────────────────────────────────────────

/**
 * Import NASA-TLX responses. Required columns: participant_id, team_id,
 * condition_id, and the six subscales (0-100). Optional pairwise weights
 * w_<scale> (integers summing to 15) produce a weighted score as well.
 * @returns {{ participants: object[], teams: object[], errors: string[] }}
 */
function importTlx(csvText) {
  const rows = parseCsv(csvText);
  const errors = [];
  const participants = [];
  rows.forEach((r, i) => {
    const line = i + 2;
    for (const k of ['participant_id', 'team_id', 'condition_id']) {
      if (!r[k]) errors.push(`row ${line}: missing ${k}`);
    }
    const ratings = {};
    let ok = true;
    for (const s of TLX_SCALES) {
      const v = Number(r[s]);
      if (r[s] === undefined || r[s] === '' || !Number.isFinite(v) || v < 0 || v > 100) {
        errors.push(`row ${line}: ${s} must be a number from 0 to 100`);
        ok = false;
      } else ratings[s] = v;
    }
    if (!ok) return;
    const raw = TLX_SCALES.reduce((n, s) => n + ratings[s], 0) / TLX_SCALES.length;
    let weighted = null;
    if (TLX_SCALES.every(s => r[`w_${s}`] !== undefined && r[`w_${s}`] !== '')) {
      const w = TLX_SCALES.map(s => Number(r[`w_${s}`]));
      const sum = w.reduce((a, b) => a + b, 0);
      if (w.some(x => !Number.isInteger(x) || x < 0 || x > 5) || sum !== 15) {
        errors.push(`row ${line}: weights must be integers 0 to 5 summing to 15 (got ${sum})`);
      } else {
        weighted = TLX_SCALES.reduce((n, s, j) => n + ratings[s] * w[j], 0) / 15;
      }
    }
    participants.push({ participantId: r.participant_id, teamId: r.team_id, conditionId: r.condition_id,
      role: r.role || null, ratings, rawTlx: raw, weightedTlx: weighted });
  });
  const groups = new Map();
  for (const p of participants) {
    const k = `${p.teamId}\u0000${p.conditionId}`;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(p);
  }
  const teams = [...groups.values()].map(ps => ({
    teamId: ps[0].teamId, conditionId: ps[0].conditionId, n: ps.length,
    meanRawTlx: ps.reduce((n, p) => n + p.rawTlx, 0) / ps.length,
  }));
  return { participants, teams, errors };
}

// ── CLI ──────────────────────────────────────────────────────────────────────

if (require.main === module) {
  const a = {};
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) if (argv[i].startsWith('--')) a[argv[i].slice(2)] = argv[++i];
  if (!a.log || !a.scenario) {
    console.error('Usage: node score.js --log <log.jsonl> --scenario <scenario.json> [--tlx <tlx.csv>] [--coding-sheet <out.csv>] [--out <result.json>]');
    process.exit(2);
  }
  const events = parseJsonl(fs.readFileSync(a.log, 'utf8'));
  const scenario = JSON.parse(fs.readFileSync(a.scenario, 'utf8'));
  const result = scoreSession(events, scenario, a['time-scale'] !== undefined ? { timeScale: Number(a['time-scale']) } : {});
  if (a.tlx) {
    const tlx = importTlx(fs.readFileSync(a.tlx, 'utf8'));
    result.tlx = {
      errors: tlx.errors,
      participants: tlx.participants.filter(p => p.teamId === result.teamId && p.conditionId === result.conditionId),
      team: tlx.teams.find(t => t.teamId === result.teamId && t.conditionId === result.conditionId) || null,
    };
  }
  if (a['coding-sheet']) fs.writeFileSync(a['coding-sheet'], codingSheet(events, result));
  const out = JSON.stringify(result, null, 2);
  if (a.out) fs.writeFileSync(a.out, out + '\n');
  else console.log(out);
}

module.exports = {
  TLX_SCALES,
  parseJsonl,
  parseCsv,
  toCsv,
  normalise,
  isCorrect,
  scoreSession,
  codingSheet,
  importTlx,
};
