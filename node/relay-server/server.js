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
 * Compute a deterministic relay session ID from a plan object.
 * Hashes a canonical JSON subset with a 32-bit polynomial.
 * @param {object} plan
 * @returns {string}
 */
function makePlanId(plan) {
  const canonical = JSON.stringify({
    v:        plan.v,
    title:    plan.title,
    start:    plan.start,
    quantum:  plan.quantum,
    mode:     plan.mode,
    nodes:    plan.nodes,
    segments: plan.segments,
  });
  let h = 0;
  for (const b of Buffer.from(canonical)) h = ((h * 31) + b) >>> 0;
  return Buffer.from(h.toString(16).padStart(8, '0')).toString('base64url');
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

  const sessionId   = makePlanId(body);
  const participants = body.nodes.filter(n => n.role !== 'HOST');
  const delayS       = (participants[0] && participants[0].delay != null)
    ? Number(participants[0].delay) : 0;
  const delay_ms     = Math.round(delayS * 1000);

  const tls_fingerprint = (body.relay && body.relay.tls_fingerprint)
    ? body.relay.tls_fingerprint
    : crypto.randomBytes(16).toString('hex');

  sessions.set(sessionId, {
    nodes: body.nodes, delay_ms, tls_fingerprint, created_at: Date.now(), plan: body,
  });
  if (!queues.has(sessionId)) queues.set(sessionId, []);

  sendJSON(res, 200, { sessionId, status: 'ready', delay_ms, tls_fingerprint });
}

function handleDeleteSession(req, res, sessionId) {
  if (!sessions.has(sessionId)) return sendJSON(res, 404, { error: 'Session not found' });
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

// ── Router ─────────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url    = new URL(req.url, 'http://localhost');
  const path   = url.pathname;
  const method = req.method;

  try {
    if (method === 'GET'  && path === '/relay/health')   return handleHealth(req, res);
    if (method === 'POST' && path === '/relay/session')  return handleRegisterSession(req, res);

    const delMatch  = path.match(/^\/relay\/session\/([^/]+)$/);
    if (method === 'DELETE' && delMatch)  return handleDeleteSession(req, res, delMatch[1]);

    const sendMatch = path.match(/^\/relay\/([^/]+)\/send$/);
    if (method === 'POST' && sendMatch)   return handleSend(req, res, sendMatch[1]);

    const recvMatch = path.match(/^\/relay\/([^/]+)\/receive$/);
    if (method === 'GET'  && recvMatch)   return handleReceive(req, res, recvMatch[1]);

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

module.exports = { server, sessions, queues, makePlanId, safeEqual };
