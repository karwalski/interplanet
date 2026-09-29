'use strict';
/**
 * relay.js — Delay-injecting text relay for the InterPlanet replication kit
 * Story IP-R2 (Refs #19)
 *
 * Holds each text message for the configured one-way delay before it becomes
 * visible to the recipient, models interrupted delivery (link outage windows),
 * injects scripted scenario events, and writes every event to a JSONL log.
 *
 * No dependencies. Plain Node http server with Server-Sent Events.
 *
 * Library use:
 *   const { createRelay, createServer } = require('./relay');
 *
 * CLI use:
 *   node relay.js --condition D10-P1 --team T01 [--port 8787] [--time-scale 1]
 *                 [--conditions ../conditions.json] [--scenario ../scenarios/co2-removal.json]
 *                 [--log ./logs/T01-D10-P1.jsonl]
 *
 * HTTP API (all JSON, CORS open for local use):
 *   GET  /                      minimal participant client (text only)
 *   GET  /config                roles, condition id, protocol flag (no delay value)
 *   POST /send    {from, to, text}                 queue a message
 *   POST /answer  {from, faultId, itemId, answer}  submit a scored answer (not delayed)
 *   GET  /events?participant=ID                    SSE stream of delivered messages
 *   GET  /inbox?participant=ID                     all delivered messages (polling)
 *   POST /start                                    start the session clock and injections
 */

const fs = require('fs');
const http = require('http');
const path = require('path');
const { URL } = require('url');

// ── Pure delay logic ─────────────────────────────────────────────────────────

/**
 * Link between two roles. Roles on the same site (e.g. both crew members) have
 * no delay; roles on different sites get the one-way delay.
 */
function linkDelayMs(fromRole, toRole, roles, oneWayDelayMs) {
  const a = roles[fromRole];
  const b = roles[toRole];
  if (!a || !b) throw new Error(`unknown role: ${!a ? fromRole : toRole}`);
  return a.site === b.site ? 0 : oneWayDelayMs;
}

/**
 * Compute when a message sent at sentMs (ms since session start) is delivered.
 * Interruption windows are [startMs, endMs) link outages. A window only
 * affects cross-site traffic. In 'hold' mode a message that would arrive
 * during an outage is delivered when the outage ends (store and forward). In
 * 'drop' mode it is lost.
 *
 * @returns {{ deliverMs: number|null, heldMs: number, dropped: boolean, arrivalMs: number }}
 */
function computeDelivery(sentMs, delayMs, interruptions, mode) {
  const arrivalMs = sentMs + delayMs;
  if (delayMs === 0 || !interruptions || interruptions.length === 0) {
    return { deliverMs: arrivalMs, heldMs: 0, dropped: false, arrivalMs };
  }
  const windows = interruptions.slice().sort((x, y) => x.startMs - y.startMs);
  let t = arrivalMs;
  let hit = false;
  for (const w of windows) {
    if (t >= w.startMs && t < w.endMs) { t = w.endMs; hit = true; }
  }
  if (hit && mode === 'drop') return { deliverMs: null, heldMs: 0, dropped: true, arrivalMs };
  return { deliverMs: t, heldMs: t - arrivalMs, dropped: false, arrivalMs };
}

/** Convert a condition (minutes) to relay settings (ms), applying timeScale. */
function conditionToSettings(condition, timeScale) {
  const k = 60000 * (timeScale === undefined ? 1 : timeScale);
  return {
    oneWayDelayMs: Math.round(condition.oneWayDelayMin * k),
    interruptions: (condition.interruptions || []).map(w => ({
      startMs: Math.round(w.startMin * k), endMs: Math.round(w.endMin * k),
    })),
    interruptionMode: condition.interruptionMode || 'hold',
    protocol: !!condition.protocol,
  };
}

// ── Relay core ───────────────────────────────────────────────────────────────

const DEFAULT_ROLES = {
  crew1: { site: 'spacecraft', label: 'Crew member 1' },
  crew2: { site: 'spacecraft', label: 'Crew member 2' },
  fc:    { site: 'ground',     label: 'Flight controller' },
};

/**
 * @param {object} cfg
 *   roles, oneWayDelayMs, interruptions, interruptionMode, protocol,
 *   conditionId, teamId, injections [{atMs, to, text, faultId}],
 *   log (function(event) | string path), clock {now, setTimeout, clearTimeout}
 */
function createRelay(cfg) {
  const roles = cfg.roles || DEFAULT_ROLES;
  const delayMs = cfg.oneWayDelayMs || 0;
  const interruptions = cfg.interruptions || [];
  const mode = cfg.interruptionMode || 'hold';
  const clock = cfg.clock || { now: Date.now, setTimeout, clearTimeout };
  const listeners = new Set();
  const delivered = [];
  const timers = new Set();
  let startedAt = null;
  let nextId = 1;
  let logFd = null;
  let closed = false;

  let writeLog;
  if (typeof cfg.log === 'function') writeLog = cfg.log;
  else if (typeof cfg.log === 'string') {
    fs.mkdirSync(path.dirname(cfg.log), { recursive: true });
    logFd = fs.openSync(cfg.log, 'a');
    writeLog = ev => fs.writeSync(logFd, JSON.stringify(ev) + '\n');
  } else writeLog = () => {};

  function rel() { return startedAt === null ? 0 : clock.now() - startedAt; }

  function log(event, fields) {
    if (closed) return null; // e.g. a client disconnecting after the session ended
    const now = clock.now();
    const ev = Object.assign({ t: new Date(now).toISOString(), tMs: rel(), event,
      teamId: cfg.teamId || null, conditionId: cfg.conditionId || null }, fields);
    writeLog(ev);
    return ev;
  }

  function schedule(ms, fn) {
    const h = clock.setTimeout(() => { timers.delete(h); fn(); }, Math.max(0, ms));
    timers.add(h);
    return h;
  }

  function deliver(msg) {
    msg.deliveredMs = rel();
    delivered.push(msg);
    log('deliver', { id: msg.id, from: msg.from, to: msg.to, deliveredMs: msg.deliveredMs });
    for (const l of listeners) {
      if (l.participant === msg.to) l.fn(msg);
    }
  }

  // `to` may be a role id, a site name (e.g. 'spacecraft') or 'all'.
  function recipients(to, from) {
    if (roles[to]) return [to];
    const ids = Object.keys(roles).filter(r => r !== from);
    if (to === 'all') return ids;
    const bySite = ids.filter(r => roles[r].site === to);
    if (bySite.length) return bySite;
    throw new Error(`unknown recipient: ${to}`);
  }

  function start() {
    if (startedAt !== null) return false;
    startedAt = clock.now();
    log('session_start', { oneWayDelayMs: delayMs, interruptions, interruptionMode: mode,
      protocol: !!cfg.protocol, roles });
    for (const w of interruptions) {
      schedule(w.startMs, () => log('interruption_start', { startMs: w.startMs, endMs: w.endMs }));
      schedule(w.endMs, () => log('interruption_end', { startMs: w.startMs, endMs: w.endMs }));
    }
    for (const inj of cfg.injections || []) {
      schedule(inj.atMs, () => {
        const ev = log('inject', { faultId: inj.faultId || null, to: inj.to, text: inj.text, injectionId: inj.id || null });
        for (const r of recipients(inj.to, null)) {
          deliver({ id: `inj-${nextId++}`, from: 'sim', to: r, text: inj.text, sentMs: ev.tMs, faultId: inj.faultId || null });
        }
      });
    }
    return true;
  }

  /** Queue a message. One queued copy per recipient, each with its own link delay. */
  function send(from, to, text) {
    if (startedAt === null) throw new Error('session not started');
    if (closed) throw new Error('session closed');
    if (!roles[from]) throw new Error(`unknown sender: ${from}`);
    if (typeof text !== 'string' || text.trim() === '') throw new Error('empty message');
    const id = `m-${nextId++}`;
    const sentMs = rel();
    const out = [];
    const targets = recipients(to, from);
    for (const r of targets) {
      const d = linkDelayMs(from, r, roles, delayMs);
      const plan = d === 0
        ? { deliverMs: sentMs, heldMs: 0, dropped: false, arrivalMs: sentMs }
        : computeDelivery(sentMs, d, interruptions, mode);
      const msg = { id: `${id}:${r}`, msgId: id, from, to: r, text, sentMs };
      log('send', { id: msg.id, msgId: id, from, to: r, text, sentMs,
        scheduledDeliverMs: plan.deliverMs, heldMs: plan.heldMs, dropped: plan.dropped });
      if (plan.dropped) log('drop', { id: msg.id, from, to: r, arrivalMs: plan.arrivalMs });
      else if (plan.deliverMs === sentMs) deliver(msg);
      else schedule(plan.deliverMs - sentMs, () => deliver(msg));
      out.push({ id: msg.id, to: r, sentMs, dropped: plan.dropped });
    }
    return out;
  }

  /** Record a scored answer. Answers go to the experimenter, not across the link. */
  function answer(from, faultId, itemId, value) {
    if (startedAt === null) throw new Error('session not started');
    if (closed) throw new Error('session closed');
    if (!roles[from]) throw new Error(`unknown sender: ${from}`);
    return log('answer', { from, faultId: String(faultId), itemId: String(itemId), answer: String(value) });
  }

  function subscribe(participant, fn) {
    const l = { participant, fn };
    listeners.add(l);
    return () => listeners.delete(l);
  }

  function inbox(participant) {
    return delivered.filter(m => (m.to === participant));
  }

  function close() {
    if (closed) return;
    for (const h of timers) clock.clearTimeout(h);
    timers.clear();
    if (startedAt !== null) log('session_end', {});
    closed = true;
    if (logFd !== null) { fs.closeSync(logFd); logFd = null; }
  }

  return { start, send, answer, subscribe, inbox, close, log, elapsedMs: rel,
    get started() { return startedAt !== null; }, roles, protocol: !!cfg.protocol };
}

// ── HTTP server ──────────────────────────────────────────────────────────────

function _readJson(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', c => { body += c; if (body.length > 65536) req.destroy(); });
    req.on('end', () => { try { resolve(body ? JSON.parse(body) : {}); } catch (e) { reject(e); } });
    req.on('error', reject);
  });
}

function _json(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
  res.end(JSON.stringify(obj));
}

function createServer(relay, opts) {
  const o = opts || {};
  const clientHtml = o.clientHtml || fs.readFileSync(path.join(__dirname, 'client.html'), 'utf8');
  return http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    try {
      if (req.method === 'OPTIONS') {
        res.writeHead(204, { 'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'Content-Type', 'Access-Control-Allow-Methods': 'GET, POST' });
        return res.end();
      }
      if (req.method === 'GET' && url.pathname === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        return res.end(clientHtml);
      }
      if (req.method === 'GET' && url.pathname === '/config') {
        // The delay value is deliberately not exposed to participants.
        return _json(res, 200, { roles: relay.roles, protocol: relay.protocol, started: relay.started });
      }
      if (req.method === 'POST' && url.pathname === '/start') {
        return _json(res, 200, { started: relay.start() });
      }
      if (req.method === 'POST' && url.pathname === '/send') {
        const b = await _readJson(req);
        return _json(res, 200, { queued: relay.send(b.from, b.to, b.text) });
      }
      if (req.method === 'POST' && url.pathname === '/answer') {
        const b = await _readJson(req);
        const ev = relay.answer(b.from, b.faultId, b.itemId, b.answer);
        return _json(res, 200, { recorded: ev.tMs });
      }
      if (req.method === 'GET' && url.pathname === '/inbox') {
        return _json(res, 200, { messages: relay.inbox(url.searchParams.get('participant')) });
      }
      if (req.method === 'GET' && url.pathname === '/events') {
        const p = url.searchParams.get('participant');
        if (!relay.roles[p]) return _json(res, 400, { error: 'unknown participant' });
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache',
          Connection: 'keep-alive', 'Access-Control-Allow-Origin': '*' });
        res.write(': connected\n\n');
        relay.log('client_connect', { participant: p });
        const off = relay.subscribe(p, msg => res.write(`data: ${JSON.stringify(msg)}\n\n`));
        req.on('close', () => { off(); relay.log('client_disconnect', { participant: p }); });
        return undefined;
      }
      return _json(res, 404, { error: 'not found' });
    } catch (e) {
      return _json(res, 400, { error: e.message });
    }
  });
}

// ── Scenario loading ─────────────────────────────────────────────────────────

/** Scenario injections (minutes) to relay injections (ms). */
function scenarioInjections(scenario, timeScale) {
  const k = 60000 * (timeScale === undefined ? 1 : timeScale);
  const out = [];
  const b = scenario.briefing || {};
  for (const to of Object.keys(b)) {
    out.push({ id: `briefing-${to}`, faultId: null, atMs: 0, to, text: b[to] });
  }
  for (const f of scenario.faults || []) {
    for (const inj of f.injections || []) {
      out.push({ id: inj.id, faultId: f.id, atMs: Math.round(inj.atMin * k), to: inj.to, text: inj.text });
    }
  }
  return out.sort((a, b) => a.atMs - b.atMs);
}

// ── CLI ──────────────────────────────────────────────────────────────────────

function _args(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) a[argv[i].slice(2)] = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
  }
  return a;
}

if (require.main === module) {
  const a = _args(process.argv.slice(2));
  const kit = path.join(__dirname, '..');
  const conditions = JSON.parse(fs.readFileSync(a.conditions || path.join(kit, 'conditions.json'), 'utf8'));
  const condition = conditions.conditions.find(c => c.id === a.condition);
  if (!condition) {
    console.error(`Unknown or missing --condition. Known: ${conditions.conditions.map(c => c.id).join(', ')}`);
    process.exit(2);
  }
  const scale = a['time-scale'] !== undefined ? Number(a['time-scale']) : 1;
  const scenario = JSON.parse(fs.readFileSync(a.scenario || path.join(kit, 'scenarios', 'co2-removal.json'), 'utf8'));
  const team = a.team || 'T00';
  const settings = conditionToSettings(condition, scale);
  const logPath = a.log || path.join(kit, 'logs', `${team}-${condition.id}-${scenario.id}.jsonl`);
  const relay = createRelay(Object.assign({}, settings, {
    conditionId: condition.id, teamId: team, log: logPath, roles: scenario.roles,
    injections: scenarioInjections(scenario, scale),
  }));
  relay.log('config', { scenarioId: scenario.id, timeScale: scale });
  const server = createServer(relay);
  const port = Number(a.port || 8787);
  server.listen(port, '127.0.0.1', () => {
    console.log(`Relay for team ${team}, condition ${condition.id}, scenario ${scenario.id}`);
    console.log(`Participant client: http://127.0.0.1:${port}/  (POST /start to begin)`);
    console.log(`Log: ${logPath}`);
  });
  process.on('SIGINT', () => { relay.close(); server.close(); process.exit(0); });
}

module.exports = {
  DEFAULT_ROLES,
  linkDelayMs,
  computeDelivery,
  conditionToSettings,
  scenarioInjections,
  createRelay,
  createServer,
};
