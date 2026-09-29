'use strict';

/**
 * relay-server/server.js
 * LTX DTN store-and-forward relay server
 * Simulates light-time delays for interplanetary LTX meetings.
 * No external dependencies -- stdlib only (http, crypto).
 */

const http   = require('http');
const crypto = require('crypto');

// ── State ──────────────────────────────────────────────────────────────────

/** @type {Map<string, {nodes:object[], delay_ms:number, tls_fingerprint:string, created_at:number}>} */
const sessions = new Map();

/**
 * Frame shape: {nodeId, targetNodeId, data, timestamp_ms, deliverAt, delay_ms}
 * @type {Map<string, Array>}
 */
const queues = new Map();

const startTime = Date.now();

// ── Plan ID ────────────────────────────────────────────────────────────────

/**
 * upgradeConfig() from javascript/ltx/ltx-sdk.js: a v1 plan gains v: 2 and a
 * nodes[] pair; a v2+ plan with nodes is returned unchanged (same key order).
 * @param {object} cfg
 * @returns {object}
 */
function upgradeConfig(cfg) {
  if (cfg.v >= 2 && Array.isArray(cfg.nodes) && cfg.nodes.length) return cfg;
  const remoteLoc = (cfg.rxName || '').toLowerCase().includes('mars') ? 'mars'
    : (cfg.rxName || '').toLowerCase().includes('moon') ? 'moon' : 'earth';
  return {
    ...cfg,
    v: 2,
    nodes: [
      { id: 'N0', name: cfg.txName || 'Earth HQ',    role: 'HOST',        delay: 0,              location: 'earth'   },
      { id: 'N1', name: cfg.rxName || 'Mars Hab-01', role: 'PARTICIPANT', delay: cfg.delay || 0, location: remoteLoc },
    ],
  };
}

/** Canonical JSON (RFC 8785 for plan data), as canonicalJSON() in ltx-sdk.js. */
function canonicalJSON(obj) {
  if (obj === null || typeof obj !== 'object') return JSON.stringify(obj);
  if (Array.isArray(obj)) return '[' + obj.map(canonicalJSON).join(',') + ']';
  const keys = Object.keys(obj).sort();
  return '{' + keys.map(k => JSON.stringify(k) + ':' + canonicalJSON(obj[k])).join(',') + '}';
}

/**
 * Relay session ID: the spec planId (docs/LTX-SPECIFICATION.md sections 4.3
 * and 4.5) of the plan exactly as received, identical to makePlanId() in
 * javascript/ltx/ltx-sdk.js (golden vectors: spec/golden/plan-ids.json).
 * v2: imul31 over the UTF-16 code units of JSON.stringify(plan), in the plan's
 * own key order. v3: first 8 hex of SHA-256 over canonical JSON.
 * @param {object} plan  Plan as parsed from the request body (JSON.parse)
 * @returns {string}
 * @throws {RangeError} when plan.start is not a valid date
 */
function makePlanId(plan) {
  const c       = upgradeConfig(plan);
  const date    = new Date(c.start).toISOString().slice(0, 10).replace(/-/g, '');
  const nodes   = c.nodes || [];
  const idPart  = (name, n) => String(name || '').replace(/\s+/g, '').toUpperCase().slice(0, n);
  const hostStr = (nodes[0] && nodes[0].name) ? idPart(nodes[0].name, 8) : 'HOST';
  const nodeStr = nodes.length > 1
    ? nodes.slice(1).map(n => idPart(n && n.name, 4)).join('-').slice(0, 16)
    : 'RX';
  if (c.v >= 3) {
    const digest = crypto.createHash('sha256').update(canonicalJSON(c), 'utf8').digest('hex');
    return `LTX-${date}-${hostStr}-${nodeStr}-v3-${digest.slice(0, 8)}`;
  }
  // FROZEN v2 path (section 4.3).
  const raw = JSON.stringify(c);
  let h = 0;
  for (let i = 0; i < raw.length; i++) h = (Math.imul(31, h) + raw.charCodeAt(i)) >>> 0;
  return `LTX-${date}-${hostStr}-${nodeStr}-v2-${h.toString(16).padStart(8, '0')}`;
}

// ── Request helpers ────────────────────────────────────────────────────────

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end',  () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function sendJSON(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type':   'application/json',
    'Content-Length': Buffer.byteLength(payload),
  });
  res.end(payload);
}

function extractBearer(req) {
  const auth = req.headers['authorization'] || '';
  const m = auth.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

/**
 * Timing-safe string equality using crypto.timingSafeEqual.
 * Returns false if lengths differ (no early exit leaking length).
 */
function safeEqual(a, b) {
  try {
    const ba = Buffer.from(String(a));
    const bb = Buffer.from(String(b));
    if (ba.length !== bb.length) return false;
    return crypto.timingSafeEqual(ba, bb);
  } catch (_) {
    return false;
  }
}

// ── Route handlers ─────────────────────────────────────────────────────────

async function handleRegisterSession(req, res) {
  let body;
  try { body = JSON.parse(await readBody(req)); }
  catch (_) { return sendJSON(res, 400, { error: 'Invalid JSON body' }); }

  if (!body || !Array.isArray(body.nodes) || !body.nodes.length) {
    return sendJSON(res, 400, { error: 'Plan must include nodes array' });
  }

  let sessionId;
  try { sessionId = makePlanId(body); }
  catch (_) { return sendJSON(res, 400, { error: 'Plan must include a valid start timestamp' }); }
  const participants = body.nodes.filter(n => n.role !== 'HOST');
  const delayS       = (participants[0] && participants[0].delay != null)
    ? Number(participants[0].delay) : 0;
  const delay_ms     = Math.round(delayS * 1000);

  // Re-registering a live session must not hand it to a new token: only the
  // holder of its token (Bearer, or the same relay.tls_fingerprint) may.
  const existing = sessions.get(sessionId);
  if (existing) {
    const token = extractBearer(req);
    const owner = (token && safeEqual(token, existing.tls_fingerprint)) ||
      (body.relay && body.relay.tls_fingerprint && safeEqual(body.relay.tls_fingerprint, existing.tls_fingerprint));
    if (!owner) {
      return sendJSON(res, 409, { error: 'Session already registered', sessionId, planId: sessionId });
    }
  }
  // The owner re-registering keeps its token unless the plan names one.
  const tls_fingerprint = (body.relay && body.relay.tls_fingerprint)
    ? String(body.relay.tls_fingerprint)
    : (existing ? existing.tls_fingerprint : crypto.randomBytes(16).toString('hex'));

  sessions.set(sessionId, {
    nodes: body.nodes, delay_ms, tls_fingerprint, created_at: Date.now(), plan: body,
  });
  if (!queues.has(sessionId)) queues.set(sessionId, []);

  sendJSON(res, 200, { sessionId, planId: sessionId, status: 'ready', delay_ms, tls_fingerprint });
}

function handleDeleteSession(req, res, sessionId) {
  const session = sessions.get(sessionId);
  if (!session) return sendJSON(res, 404, { error: 'Session not found' });
  const token = extractBearer(req);
  if (!token || !safeEqual(token, session.tls_fingerprint)) {
    return sendJSON(res, 401, { error: 'Invalid or missing Authorization token' });
  }
  sessions.delete(sessionId);
  queues.delete(sessionId);
  sendJSON(res, 200, { deleted: true, sessionId });
}

async function handleSend(req, res, sessionId) {
  const session = sessions.get(sessionId);
  if (!session) return sendJSON(res, 404, { error: 'Session not found' });

  const token = extractBearer(req);
  if (!token || !safeEqual(token, session.tls_fingerprint)) {
    return sendJSON(res, 401, { error: 'Invalid or missing Authorization token' });
  }

  let body;
  try { body = JSON.parse(await readBody(req)); }
  catch (_) { return sendJSON(res, 400, { error: 'Invalid JSON body' }); }

  const { nodeId, targetNodeId, data, timestamp_ms } = body;
  if (!nodeId || data === undefined || data === null) {
    return sendJSON(res, 400, { error: 'nodeId and data are required' });
  }

  const nodeIds = session.nodes.map(n => n.id);
  if (!nodeIds.includes(nodeId)) {
    return sendJSON(res, 400, { error: `nodeId '${nodeId}' not in session` });
  }

  const ts        = typeof timestamp_ms === 'number' ? timestamp_ms : Date.now();
  const deliverAt = ts + session.delay_ms;

  const queue = queues.get(sessionId) || [];
  queue.push({ nodeId, targetNodeId: targetNodeId || null, data, timestamp_ms: ts, deliverAt, delay_ms: session.delay_ms });
  queues.set(sessionId, queue);

  sendJSON(res, 200, { queued: true, deliver_at: deliverAt });
}

function handleReceive(req, res, sessionId) {
  const session = sessions.get(sessionId);
  if (!session) return sendJSON(res, 404, { error: 'Session not found' });

  const token = extractBearer(req);
  if (!token || !safeEqual(token, session.tls_fingerprint)) {
    return sendJSON(res, 401, { error: 'Invalid or missing Authorization token' });
  }

  const url    = new URL(req.url, 'http://localhost');
  const nodeId = url.searchParams.get('node');
  if (!nodeId) return sendJSON(res, 400, { error: 'node query param required' });

  const nodeIds = session.nodes.map(n => n.id);
  if (!nodeIds.includes(nodeId)) {
    return sendJSON(res, 400, { error: `nodeId '${nodeId}' not in session` });
  }

  const now   = Date.now();
  const queue = queues.get(sessionId) || [];
  const ready = [], pending = [];

  for (const frame of queue) {
    const forMe = frame.nodeId !== nodeId &&
      (!frame.targetNodeId || frame.targetNodeId === nodeId);
    if (forMe && frame.deliverAt <= now) ready.push(frame);
    else pending.push(frame);
  }

  queues.set(sessionId, pending);

  sendJSON(res, 200, {
    frames: ready.map(f => ({
      nodeId: f.nodeId, targetNodeId: f.targetNodeId,
      data: f.data, timestamp_ms: f.timestamp_ms, delay_ms: f.delay_ms,
    })),
  });
}

function handleHealth(req, res) {
  let totalFrames = 0;
  for (const q of queues.values()) totalFrames += q.length;
  sendJSON(res, 200, {
    status: 'ok',
    sessions: sessions.size,
    queued_frames: totalFrames,
    uptime_s: Math.floor((Date.now() - startTime) / 1000),
  });
}

/** Percent-decode a session id path segment (planIds may hold non-ASCII names). */
function decodeId(seg) {
  try { return decodeURIComponent(seg); } catch (_) { return seg; }
}

// ── Router ─────────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url    = new URL(req.url, 'http://localhost');
  const path   = url.pathname;
  const method = req.method;

  try {
    if (method === 'GET'  && path === '/relay/health')   return handleHealth(req, res);
    if (method === 'POST' && path === '/relay/session')  return handleRegisterSession(req, res);

    const delMatch  = path.match(/^\/relay\/session\/([^/]+)$/);
    if (method === 'DELETE' && delMatch)  return handleDeleteSession(req, res, decodeId(delMatch[1]));

    const sendMatch = path.match(/^\/relay\/([^/]+)\/send$/);
    if (method === 'POST' && sendMatch)   return handleSend(req, res, decodeId(sendMatch[1]));

    const recvMatch = path.match(/^\/relay\/([^/]+)\/receive$/);
    if (method === 'GET'  && recvMatch)   return handleReceive(req, res, decodeId(recvMatch[1]));

    sendJSON(res, 404, { error: 'Not found', path });
  } catch (err) {
    sendJSON(res, 500, { error: 'Internal server error', detail: err.message });
  }
});

// ── Start ──────────────────────────────────────────────────────────────────

const PORT = (() => {
  if (process.env.PORT) return Number(process.env.PORT);
  const idx = process.argv.indexOf('--port');
  if (idx !== -1 && process.argv[idx + 1]) return Number(process.argv[idx + 1]);
  return 3000;
})();

if (require.main === module) {
  server.listen(PORT, () => {
    process.stdout.write(`LTX relay server listening on port ${PORT}\n`);
  });
}

module.exports = { server, sessions, queues, makePlanId, upgradeConfig, canonicalJSON, safeEqual };
