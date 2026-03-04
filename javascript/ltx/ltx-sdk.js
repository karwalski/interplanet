'use strict';

/**
 * ltx-sdk.js — LTX (Light-Time eXchange) Developer SDK
 * Story 22.1 — JavaScript/TypeScript SDK for embedding and controlling LTX sessions
 *
 * Usage (browser CDN):
 *   <script src="ltx-sdk.js"></script>
 *   const plan = LtxSdk.createPlan({ hostName: 'Earth HQ', delay: 800 });
 *
 * Usage (Node.js):
 *   const LtxSdk = require('./ltx-sdk');
 *   const plan = LtxSdk.createPlan({ hostName: 'Earth HQ', delay: 800 });
 */

(function (global, factory) {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = factory();
  } else if (typeof window !== 'undefined') {
    window.LtxSdk = factory();
  }
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const VERSION = '1.0.0';

  // ── Segment types ──────────────────────────────────────────────────────────

  const SEG_TYPES = ['PLAN_CONFIRM', 'TX', 'RX', 'CAUCUS', 'BUFFER', 'MERGE'];

  const DEFAULT_QUANTUM = 5; // minutes per quantum (LTX SPECIFICATION.md §3.2)

  const DEFAULT_SEGMENTS = [
    { type: 'PLAN_CONFIRM', q: 2 },
    { type: 'TX',           q: 2 },
    { type: 'RX',           q: 2 },
    { type: 'CAUCUS',       q: 2 },
    { type: 'TX',           q: 2 },
    { type: 'RX',           q: 2 },
    { type: 'BUFFER',       q: 1 },
  ];

  // ── Internal utilities ─────────────────────────────────────────────────────

  function _pad(n) { return String(n).padStart(2, '0'); }

  function _b64enc(str) {
    return btoa(unescape(encodeURIComponent(str)))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }

  function _b64dec(b64) {
    try {
      return decodeURIComponent(escape(atob(b64.replace(/-/g, '+').replace(/_/g, '/'))));
    } catch (_) { return null; }
  }

  // ── Formatting utilities ───────────────────────────────────────────────────

  /**
   * Format seconds as HH:MM:SS or MM:SS.
   * @param {number} sec
   * @returns {string}
   */
  function formatHMS(sec) {
    if (sec < 0) sec = 0;
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = Math.floor(sec % 60);
    if (h > 0) return `${_pad(h)}:${_pad(m)}:${_pad(s)}`;
    return `${_pad(m)}:${_pad(s)}`;
  }

  /**
   * Format a Date or timestamp as "HH:MM:SS UTC".
   * @param {Date|number|string} dt
   * @returns {string}
   */
  function formatUTC(dt) {
    return new Date(dt).toISOString().slice(11, 19) + ' UTC';
  }

  // ── Config management ──────────────────────────────────────────────────────

  /**
   * Upgrade a v1 config (txName/rxName/delay) to v2 schema (nodes[]).
   * v2 configs are returned unchanged.
   * The optional relay field { endpoint, tls_fingerprint, delay_mode } is preserved.
   * @param {object} cfg
   * @param {string}  [cfg.relay.endpoint]        Relay server URL
   * @param {string}  [cfg.relay.tls_fingerprint] Pre-agreed shared secret for frame auth
   * @param {string}  [cfg.relay.delay_mode]      "oneway" or "roundtrip" (default: oneway)
   * @returns {object} v2 config
   */
  function upgradeConfig(cfg) {
    if (cfg.v >= 2 && Array.isArray(cfg.nodes) && cfg.nodes.length) return cfg;
    const remoteLoc = (cfg.rxName || '').toLowerCase().includes('mars') ? 'mars'
      : (cfg.rxName || '').toLowerCase().includes('moon') ? 'moon' : 'earth';
    return {
      ...cfg,
      v: 2,
      nodes: [
        { id: 'N0', name: cfg.txName || 'Earth HQ',    role: 'HOST',        delay: 0,              location: 'earth'     },
        { id: 'N1', name: cfg.rxName || 'Mars Hab-01', role: 'PARTICIPANT',  delay: cfg.delay || 0, location: remoteLoc   },
      ],
    };
  }

  /**
   * Create a new LTX session plan.
   *
   * @param {object} opts
   * @param {string}   [opts.title]            Session title
   * @param {string}   [opts.start]            ISO 8601 UTC start time (default: 5 min from now)
   * @param {number}   [opts.quantum]          Minutes per quantum (default: 3)
   * @param {string}   [opts.mode]             Protocol mode (default: 'LTX')
   * @param {object[]} [opts.nodes]            Explicit node list (overrides hostName/remoteName)
   * @param {string}   [opts.hostName]         Host node name (default: 'Earth HQ')
   * @param {string}   [opts.hostLocation]     Host location key (default: 'earth')
   * @param {string}   [opts.remoteName]       Participant node name (default: 'Mars Hab-01')
   * @param {string}   [opts.remoteLocation]   Participant location key (default: 'mars')
   * @param {number}   [opts.delay]            One-way signal delay in seconds (default: 0)
   * @param {object[]} [opts.segments]         Segment template (default: DEFAULT_SEGMENTS)
   * @returns {object} LTX plan config (v2)
   */
  function createPlan(opts) {
    opts = opts || {};
    const now = new Date();
    now.setSeconds(0, 0);
    now.setMinutes(now.getMinutes() + 5);

    const nodes = opts.nodes || [
      { id: 'N0', name: opts.hostName   || 'Earth HQ',    role: 'HOST',        delay: 0,             location: opts.hostLocation   || 'earth' },
      { id: 'N1', name: opts.remoteName || 'Mars Hab-01', role: 'PARTICIPANT',  delay: opts.delay || 0, location: opts.remoteLocation || 'mars'  },
    ];

    return {
      v:        2,
      title:    opts.title    || 'LTX Session',
      start:    opts.start    || now.toISOString(),
      quantum:  opts.quantum  || DEFAULT_QUANTUM,
      mode:     opts.mode     || 'LTX',
      segments: opts.segments ? opts.segments.slice() : DEFAULT_SEGMENTS.slice(),
      nodes,
    };
  }

  // ── Segment computation ────────────────────────────────────────────────────

  /**
   * Compute the timed segment array for a plan config.
   *
   * @param {object} cfg  LTX plan config (v1 or v2)
   * @returns {Array<{type:string, q:number, start:Date, end:Date, durMin:number}>}
   */
  function computeSegments(cfg) {
    const c   = upgradeConfig(cfg);
    const qMs = c.quantum * 60 * 1000;
    let t = new Date(c.start).getTime();
    return c.segments.map(s => {
      const durMs = s.q * qMs;
      const seg = { type: s.type, q: s.q, start: new Date(t), end: new Date(t + durMs), durMin: s.q * c.quantum };
      t += durMs;
      return seg;
    });
  }


  /**
   * Compute timed segments for a multi-party (N>2) plan.
   * SPEAK segments cycle round-robin through all nodes.
   * RELAY segments are assigned to the next speaker (receiver).
   * REST/BUFFER/PAD/other segments are assigned to the host node.
   * Falls back to computeSegments() for 2-node plans.
   *
   * @param {object} plan  LTX plan config (v1 or v2)
   * @returns {Array<{segType:string, nodeId:string, startMs:number, endMs:number, durationMs:number}>}
   */
  function computeSegmentsMulti(plan) {
    const c = upgradeConfig(plan);
    if (c.nodes.length <= 2) {
      // Fall back to normal 2-node computeSegments, wrapped in multi format
      return computeSegments(c).map(s => ({
        segType:    s.type,
        nodeId:     c.nodes[0].id,
        startMs:    s.start.getTime(),
        endMs:      s.end.getTime(),
        durationMs: s.end.getTime() - s.start.getTime(),
      }));
    }
    const qMs = c.quantum * 60 * 1000;
    let cursor = new Date(c.start).getTime();
    const segments = [];
    let speakerIdx = 0;

    for (const tpl of c.segments) {
      const durMs = tpl.q * qMs;
      let nodeId;
      if (tpl.type === 'SPEAK' || tpl.type === 'TX') {
        nodeId = c.nodes[speakerIdx % c.nodes.length].id;
      } else if (tpl.type === 'RELAY' || tpl.type === 'RX') {
        nodeId = c.nodes[speakerIdx % c.nodes.length].id;
      } else {
        // REST, BUFFER, PAD, CAUCUS, PLAN_CONFIRM, MERGE etc — shared/host
        nodeId = c.nodes[0].id;
      }
      segments.push({
        segType:    tpl.type,
        nodeId,
        startMs:    cursor,
        endMs:      cursor + durMs,
        durationMs: durMs,
      });
      if (tpl.type === 'SPEAK' || tpl.type === 'TX') speakerIdx++;
      cursor += durMs;
    }
    return segments;
  }

  /**
   * Build a flat delay matrix for all node pairs in a plan.
   * Earth-to-Earth delay = 0.
   * Delay from/to non-host nodes uses that node's configured delay.
   * Delay between two non-host nodes = sum of their individual delays.
   *
   * @param {object} plan  LTX plan config (v1 or v2)
   * @returns {Array<{fromId:string, fromName:string, toId:string, toName:string, delaySeconds:number}>}
   */
  function buildDelayMatrix(plan) {
    const c = upgradeConfig(plan);
    const nodes = c.nodes || [];
    const matrix = [];
    for (let i = 0; i < nodes.length; i++) {
      for (let j = 0; j < nodes.length; j++) {
        if (i === j) continue;
        const from = nodes[i];
        const to   = nodes[j];
        // Delay between two nodes: if one is host (delay=0), use the other's delay.
        // If both are non-host, approximate as max of the two (both relay via host).
        let delaySeconds;
        if (from.delay === 0 || i === 0) {
          delaySeconds = to.delay || 0;
        } else if (to.delay === 0 || j === 0) {
          delaySeconds = from.delay || 0;
        } else {
          // Non-host to non-host: signals route via host, so total = from.delay + to.delay
          delaySeconds = (from.delay || 0) + (to.delay || 0);
        }
        matrix.push({
          fromId:       from.id,
          fromName:     from.name,
          toId:         to.id,
          toName:       to.name,
          delaySeconds,
        });
      }
    }
    return matrix;
  }

  /**
   * Total session duration in minutes.
   * @param {object} cfg
   * @returns {number}
   */
  function totalMin(cfg) {
    return cfg.segments.reduce((a, s) => a + s.q * cfg.quantum, 0);
  }

  // ── Plan ID ────────────────────────────────────────────────────────────────

  /**
   * Compute the deterministic plan ID string for a config.
   * Matches the ID generated by ltx.html and api/ltx.php.
   *
   * @param {object} cfg
   * @returns {string}  e.g. "LTX-20260101-EARTHHQ-MARSHA-v2-a3b2c1d0"
   */
  function makePlanId(cfg) {
    const c      = upgradeConfig(cfg);
    const date   = new Date(c.start).toISOString().slice(0, 10).replace(/-/g, '');
    const nodes  = c.nodes || [];
    const hostStr = (nodes[0]?.name || 'HOST').replace(/\s+/g, '').toUpperCase().slice(0, 8);
    const nodeStr = nodes.length > 1
      ? nodes.slice(1).map(n => n.name.replace(/\s+/g, '').toUpperCase().slice(0, 4)).join('-').slice(0, 16)
      : 'RX';
    const raw = JSON.stringify(c);
    let h = 0;
    for (let i = 0; i < raw.length; i++) h = (Math.imul(31, h) + raw.charCodeAt(i)) >>> 0;
    return `LTX-${date}-${hostStr}-${nodeStr}-v2-${h.toString(16).padStart(8, '0')}`;
  }

  // ── URL hash encoding ──────────────────────────────────────────────────────

  /**
   * Encode a plan config to a URL hash fragment (#l=…).
   * @param {object} cfg
   * @returns {string}
   */
  function encodeHash(cfg) {
    return '#l=' + _b64enc(JSON.stringify(cfg));
  }

  /**
   * Decode a plan config from a URL hash fragment.
   * Accepts "#l=…" or just "l=…" or the raw base64 token.
   * Returns null if the hash is invalid.
   *
   * @param {string} hash
   * @returns {object|null}
   */
  function decodeHash(hash) {
    const str = (hash || '').replace(/^#?l=/, '');
    const json = _b64dec(str);
    if (!json) return null;
    try { return JSON.parse(json); } catch (_) { return null; }
  }

  /**
   * Build perspective URLs for all nodes in a plan.
   *
   * @param {object} cfg      LTX plan config
   * @param {string} baseUrl  Base page URL (e.g. "https://interplanet.live/ltx.html")
   * @returns {Array<{nodeId:string, name:string, role:string, url:string}>}
   */
  function buildNodeUrls(cfg, baseUrl) {
    const c    = upgradeConfig(cfg);
    const hash = '#l=' + _b64enc(JSON.stringify(c));
    const base = (baseUrl || '').replace(/#.*$/, '').replace(/\?.*$/, '');
    return (c.nodes || []).map(node => ({
      nodeId: node.id,
      name:   node.name,
      role:   node.role,
      url:    `${base}?node=${encodeURIComponent(node.id)}${hash}`,
    }));
  }

  // ── ICS generation ─────────────────────────────────────────────────────────

  /**
   * Generate LTX-extended iCalendar (.ics) content for a plan.
   * Includes LTX-NODE, LTX-DELAY, LTX-LOCALTIME extension properties.
   *
   * @param {object} cfg
   * @returns {string}  ICS text
   */
  function generateICS(cfg) {
    const c            = upgradeConfig(cfg);
    const segs         = computeSegments(c);
    const start        = new Date(c.start);
    const end          = segs[segs.length - 1].end;
    const planId       = makePlanId(c);
    const nodes        = c.nodes || [];
    const host         = nodes[0] || { name: 'Earth HQ', role: 'HOST', delay: 0, location: 'earth' };
    const participants = nodes.slice(1);
    const fmtDT        = dt => dt.toISOString().replace(/[-:.]/g, '').slice(0, 15) + 'Z';
    const segTpl       = c.segments.map(s => s.type).join(',');
    const toId         = name => name.replace(/\s+/g, '-').toUpperCase();

    const nodeLines    = nodes.map(n => `LTX-NODE:ID=${toId(n.name)};ROLE=${n.role}`);
    const delayLines   = participants.map(n => {
      const d = n.delay || 0;
      return `LTX-DELAY;NODEID=${toId(n.name)}:ONEWAY-MIN=${d};ONEWAY-MAX=${d + 120};ONEWAY-ASSUMED=${d}`;
    });
    const localTimeLines = nodes
      .filter(n => n.location === 'mars')
      .map(n => `LTX-LOCALTIME:NODE=${toId(n.name)};SCHEME=LMST;PARAMS=LONGITUDE:0E`);

    const hostName  = host.name;
    const partNames = participants.map(p => p.name).join(', ') || 'remote nodes';
    const delayDesc = participants.length
      ? participants.map(p => `${p.name}: ${Math.round((p.delay || 0) / 60)} min one-way`).join(' · ')
      : 'no participant delay configured';

    return [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//InterPlanet//LTX v1.1//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'BEGIN:VEVENT',
      `UID:${planId}@interplanet.live`,
      `DTSTAMP:${fmtDT(new Date())}`,
      `DTSTART:${fmtDT(start)}`,
      `DTEND:${fmtDT(end)}`,
      `SUMMARY:${c.title}`,
      `DESCRIPTION:LTX session — ${hostName} with ${partNames}\\n` +
        `Signal delays: ${delayDesc}\\n` +
        `Mode: ${c.mode} · Segment plan: ${segTpl}\\n` +
        `Generated by InterPlanet (https://interplanet.live)`,
      `LTX:1`,
      `LTX-PLANID:${planId}`,
      `LTX-QUANTUM:PT${c.quantum}M`,
      `LTX-SEGMENT-TEMPLATE:${segTpl}`,
      `LTX-MODE:${c.mode}`,
      ...nodeLines,
      ...delayLines,
      `LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY`,
      ...localTimeLines,
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n');
  }

  // ── REST API client ─────────────────────────────────────────────────────────

  const DEFAULT_API_BASE = 'https://interplanet.live/api/ltx.php';

  /**
   * Store a session plan on the server.
   * @param {object} cfg       LTX plan config
   * @param {string} [apiBase] API base URL (default: interplanet.live)
   * @returns {Promise<{plan_id:string, segments:object[], total_min:number, stored:boolean}>}
   */
  async function storeSession(cfg, apiBase) {
    const url  = (apiBase || DEFAULT_API_BASE);
    const resp = await fetch(`${url}?action=session`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(cfg),
    });
    if (!resp.ok) throw new Error(`LTX API ${resp.status}: ${await resp.text()}`);
    return resp.json();
  }

  /**
   * Retrieve a stored session plan by plan ID.
   * @param {string} planId
   * @param {string} [apiBase]
   * @returns {Promise<{plan_id:string, plan:object, created_at:string, views:number}>}
   */
  async function getSession(planId, apiBase) {
    const url  = (apiBase || DEFAULT_API_BASE);
    const resp = await fetch(`${url}?action=session&plan_id=${encodeURIComponent(planId)}`);
    if (!resp.ok) throw new Error(`LTX API ${resp.status}: ${await resp.text()}`);
    return resp.json();
  }

  /**
   * Download ICS content for a stored plan from the server.
   * @param {string} planId
   * @param {{start:string, duration_min:number}} opts
   * @param {string} [apiBase]
   * @returns {Promise<string>} ICS text
   */
  async function downloadICS(planId, opts, apiBase) {
    const url  = (apiBase || DEFAULT_API_BASE);
    const resp = await fetch(`${url}?action=ics&plan_id=${encodeURIComponent(planId)}`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ start: opts.start, duration_min: opts.duration_min }),
    });
    if (!resp.ok) throw new Error(`LTX API ${resp.status}: ${await resp.text()}`);
    return resp.text();
  }

  /**
   * Submit session feedback.
   * @param {object} payload
   * @param {string} [apiBase]
   * @returns {Promise<{ok:boolean, feedback_id:number}>}
   */
  async function submitFeedback(payload, apiBase) {
    const url  = (apiBase || DEFAULT_API_BASE);
    const resp = await fetch(`${url}?action=feedback`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(payload),
    });
    if (!resp.ok) throw new Error(`LTX API ${resp.status}: ${await resp.text()}`);
    return resp.json();
  }

  // ── Security: Canonical JSON (RFC 8785 / JCS) ──────────────────────────────

  /**
   * Canonical JSON serialisation (RFC 8785 / JCS).
   * Recursively sorts object keys lexicographically (Unicode code-point order).
   * Arrays preserve element order. No optional whitespace.
   *
   * @param {*} obj  Any JSON-serialisable value
   * @returns {string}
   */
  function canonicalJSON(obj) {
    if (obj === null || typeof obj !== 'object') return JSON.stringify(obj);
    if (Array.isArray(obj)) return '[' + obj.map(canonicalJSON).join(',') + ']';
    const keys = Object.keys(obj).sort();
    return '{' + keys.map(k => JSON.stringify(k) + ':' + canonicalJSON(obj[k])).join(',') + '}';
  }

  // ── Security: Node Identity Key (NIK) ─────────────────────────────────────

  // Lazy-load node:crypto so the SDK remains browser-importable (crypto functions
  // will throw if called without it, which is expected in browser environments).
  function _getCrypto() {
    if (typeof require === 'function') {
      try { return require('node:crypto'); } catch (_) {}
      try { return require('crypto'); } catch (_) {}
    }
    throw new Error('NIK functions require Node.js crypto module');
  }

  /**
   * Generate a new Node Identity Key (NIK) record.
   * Uses Ed25519 via Node.js built-in node:crypto.
   *
   * @param {object}  [options]
   * @param {number}  [options.validDays=365]  Key validity period in days
   * @param {string}  [options.nodeLabel='']   Optional human-readable label
   * @returns {{ nik: object, privateKeyB64: string }}
   */
  function generateNIK(options) {
    options = options || {};
    const validDays  = options.validDays  !== undefined ? options.validDays  : 365;
    const nodeLabel  = options.nodeLabel  !== undefined ? options.nodeLabel  : '';

    const crypto = _getCrypto();
    const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519');

    // Export raw 32-byte public key from SPKI DER (last 32 bytes)
    const pubKeyDer = publicKey.export({ type: 'spki', format: 'der' });
    const rawPub    = pubKeyDer.slice(-32);
    const pubKeyB64 = rawPub.toString('base64url');

    // Derive nodeId: base64url of first 16 bytes of SHA-256(raw public key)
    const hash   = crypto.createHash('sha256').update(rawPub).digest();
    const nodeId = hash.slice(0, 16).toString('base64url');

    const now      = new Date();
    const validUntil = new Date(now.getTime() + validDays * 86400000);

    const nik = {
      nodeId,
      publicKey: pubKeyB64,
      algorithm: 'Ed25519',
      validFrom:   now.toISOString(),
      validUntil:  validUntil.toISOString(),
      keyVersion:  1,
    };
    if (nodeLabel) nik.label = nodeLabel;

    // Export private key seed from PKCS8 DER (last 32 bytes)
    const privKeyDer = privateKey.export({ type: 'pkcs8', format: 'der' });
    const rawPriv    = privKeyDer.slice(-32);

    return {
      nik,
      privateKeyB64: rawPriv.toString('base64url'),
    };
  }

  /**
   * Return the full SHA-256 hex fingerprint of a NIK's public key.
   * @param {{ publicKey: string }} nik
   * @returns {string}  64-character lowercase hex string
   */
  function nikFingerprint(nik) {
    const crypto = _getCrypto();
    const rawPub = Buffer.from(nik.publicKey, 'base64url');
    return crypto.createHash('sha256').update(rawPub).digest('hex');
  }

  /**
   * Returns true if the NIK's validUntil timestamp is in the past.
   * @param {{ validUntil: string }} nik
   * @returns {boolean}
   */
  function isNIKExpired(nik) {
    return Date.now() > new Date(nik.validUntil).getTime();
  }

  // ── Security: COSE_Sign1 SessionPlan signing ───────────────────────────────

  /**
   * Sign an LTX session plan using a simplified COSE_Sign1-compatible structure.
   * Uses Ed25519 via Node.js node:crypto.
   *
   * Wire format (JSON envelope):
   *   { plan, coseSign1: { protected, unprotected: { kid }, payload, signature } }
   * All binary fields are base64url strings (no padding).
   *
   * @param {object} plan           LTX plan config
   * @param {string} privateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
   * @returns {{ plan: object, coseSign1: object }}
   */
  function signPlan(plan, privateKeyB64) {
    const crypto = _getCrypto();

    // Build protected header: canonical JSON of { alg: -19 } (-19 = EdDSA in COSE)
    const protectedHeader = canonicalJSON({ alg: -19 });
    const protectedB64 = Buffer.from(protectedHeader, 'utf8').toString('base64url');

    // Build payload: canonical JSON of the plan
    const payloadStr = canonicalJSON(plan);
    const payloadB64 = Buffer.from(payloadStr, 'utf8').toString('base64url');

    // Build Sig_Structure: canonical JSON of the array
    const sigStructure = canonicalJSON(['Signature1', protectedB64, '', payloadB64]);

    // Reconstruct Ed25519 private key from raw 32-byte seed via PKCS8 DER wrapping
    // Ed25519 PKCS8 DER header (RFC 8410): 302e020100300506032b657004220420 (16 bytes) + 32-byte seed
    const rawSeed = Buffer.from(privateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
    const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });

    // Sign using Ed25519 one-shot API (null = use algorithm from key type)
    const sigBytes = crypto.sign(null, Buffer.from(sigStructure, 'utf8'), privKey);
    const sigB64 = sigBytes.toString('base64url');

    // Derive NIK nodeId from public key to use as kid.
    // nodeId = base64url of first 16 bytes of SHA-256(raw public key), same as generateNIK.
    const pubKeyObj = crypto.createPublicKey(privKey);
    const rawPubForKid = pubKeyObj.export({ type: 'spki', format: 'der' }).slice(-32);
    const kidHash = crypto.createHash('sha256').update(rawPubForKid).digest();
    const kid = kidHash.slice(0, 16).toString('base64url');

    return {
      plan,
      coseSign1: {
        protected: protectedB64,
        unprotected: { kid },
        payload: payloadB64,
        signature: sigB64,
      },
    };
  }

  /**
   * Verify a COSE_Sign1-signed session plan envelope.
   *
   * @param {{ plan: object, coseSign1: object }} coseEnvelope  Output from signPlan()
   * @param {Map<string, object>|object} keyCache               Map or plain object of nodeId → NIK
   * @returns {{ valid: boolean, reason?: string }}
   */
  function verifyPlan(coseEnvelope, keyCache) {
    const { coseSign1, plan } = coseEnvelope;
    if (!coseSign1) return { valid: false, reason: 'missing_cose_sign1' };

    const kid = coseSign1.unprotected && coseSign1.unprotected.kid;

    // Look up signer's NIK in keyCache (Map or plain object)
    let signerNIK = null;
    if (keyCache instanceof Map) {
      signerNIK = keyCache.get(kid) ||
        [...keyCache.values()].find(n => n.nodeId && n.nodeId.startsWith(kid));
    } else if (keyCache && typeof keyCache === 'object') {
      signerNIK = keyCache[kid] ||
        Object.values(keyCache).find(n => n.nodeId && n.nodeId.startsWith(kid));
    }

    if (!signerNIK) return { valid: false, reason: 'key_not_in_cache' };
    if (isNIKExpired(signerNIK)) return { valid: false, reason: 'key_expired' };

    // Reconstruct Sig_Structure
    const sigStructure = canonicalJSON(['Signature1', coseSign1.protected, '', coseSign1.payload]);

    // Reconstruct Ed25519 public key from raw 32 bytes via SubjectPublicKeyInfo DER wrapping
    // Ed25519 SPKI DER header: 302a300506032b6570032100 (12 bytes) + 32-byte key
    const crypto = _getCrypto();
    const rawPub = Buffer.from(signerNIK.publicKey, 'base64url');
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
    const spkiDer = Buffer.concat([spkiHeader, rawPub]);
    const pubKey = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });

    // Verify signature
    const sigBytes = Buffer.from(coseSign1.signature, 'base64url');
    const valid = crypto.verify(null, Buffer.from(sigStructure, 'utf8'), pubKey, sigBytes);

    if (!valid) return { valid: false, reason: 'signature_invalid' };

    // Also verify that the embedded payload matches the plan
    const payloadStr = Buffer.from(coseSign1.payload, 'base64url').toString('utf8');
    const planStr = canonicalJSON(plan);
    if (payloadStr !== planStr) return { valid: false, reason: 'payload_mismatch' };

    return { valid: true };
  }

  // ── Security: Merkle Audit Log (RFC 9162-style) ───────────────────────────

  // Lazy-load node:crypto (same pattern as _getCrypto)
  const _crypto = (function () {
    if (typeof require === 'function') {
      try { return require('node:crypto'); } catch (_) {}
      try { return require('crypto'); } catch (_) {}
    }
    return null;
  }());

  function _leafHash(entryBytes) {
    const buf = Buffer.alloc(1 + entryBytes.length);
    buf[0] = 0x00;
    entryBytes.copy(buf, 1);
    return _crypto.createHash('sha256').update(buf).digest();
  }

  function _nodeHash(left, right) {
    const buf = Buffer.alloc(1 + 32 + 32);
    buf[0] = 0x01;
    left.copy(buf, 1);
    right.copy(buf, 33);
    return _crypto.createHash('sha256').update(buf).digest();
  }

  /**
   * Create an RFC 9162-compatible Merkle audit log.
   *
   * Leaf hash:  SHA-256(0x00 || entry_bytes)
   * Node hash:  SHA-256(0x01 || left || right)
   * Empty root: 32 zero bytes
   *
   * @returns {object} Log instance with append/proof/consistency/sign operations
   */
  function createMerkleLog() {
    const leaves = []; // array of Buffer (leaf hashes)

    function _root(leavesSlice) {
      if (leavesSlice.length === 0) return Buffer.alloc(32);
      if (leavesSlice.length === 1) return leavesSlice[0];
      const mid = Math.pow(2, Math.floor(Math.log2(leavesSlice.length - 1)));
      return _nodeHash(_root(leavesSlice.slice(0, mid)), _root(leavesSlice.slice(mid)));
    }

    function root() { return _root(leaves.slice()); }

    return {
      /**
       * Append an entry (any JSON-serialisable object).
       * @param {*} entry
       * @returns {{ treeSize: number, root: string }}
       */
      append(entry) {
        const entryBytes = Buffer.from(canonicalJSON(entry), 'utf8');
        leaves.push(_leafHash(entryBytes));
        return { treeSize: leaves.length, root: root().toString('hex') };
      },

      /** @returns {number} */
      treeSize() { return leaves.length; },

      /** @returns {string} hex-encoded root hash */
      rootHex() { return root().toString('hex'); },

      /**
       * Inclusion proof for leaf at leafIndex (0-based).
       * @param {number} leafIndex
       * @returns {Array<{side:'left'|'right', hash:string}>}
       */
      inclusionProof(leafIndex) {
        if (leafIndex >= leaves.length) throw new Error('leaf index out of range');
        const proof = [];
        function buildProof(lo, hi, idx) {
          if (hi - lo === 1) return;
          const mid = Math.pow(2, Math.floor(Math.log2((hi - lo) - 1)));
          if (idx < lo + mid) {
            buildProof(lo, lo + mid, idx);
            proof.push({ side: 'right', hash: _root(leaves.slice(lo + mid, hi)).toString('hex') });
          } else {
            buildProof(lo + mid, hi, idx);
            proof.push({ side: 'left', hash: _root(leaves.slice(lo, lo + mid)).toString('hex') });
          }
        }
        buildProof(0, leaves.length, leafIndex);
        return proof;
      },

      /**
       * Verify an inclusion proof for a given entry against a known root.
       * @param {*} entry
       * @param {number} leafIndex
       * @param {Array<{side:string, hash:string}>} proof
       * @param {string} knownRoot  hex string
       * @returns {boolean}
       */
      verifyInclusion(entry, leafIndex, proof, knownRoot) {
        let hash = _leafHash(Buffer.from(canonicalJSON(entry), 'utf8'));
        for (const step of proof) {
          const sibling = Buffer.from(step.hash, 'hex');
          hash = step.side === 'right' ? _nodeHash(hash, sibling) : _nodeHash(sibling, hash);
        }
        return hash.toString('hex') === knownRoot;
      },

      /**
       * Consistency proof: prove the current tree is an extension of a tree of size oldSize.
       * @param {number} oldSize
       * @returns {string[]} array of hex hash strings
       */
      consistencyProof(oldSize) {
        const newSize = leaves.length;
        if (oldSize > newSize) throw new Error('oldSize > newSize');
        if (oldSize === newSize) return [];
        const proof = [];
        function buildConsistency(lo, hi, oldHi, first) {
          if (lo === hi) return;
          if (lo + 1 === hi) {
            if (!first) proof.push(leaves[lo].toString('hex'));
            return;
          }
          const mid = Math.pow(2, Math.floor(Math.log2((hi - lo) - 1)));
          if (oldHi - lo <= mid) {
            proof.push(_root(leaves.slice(lo + mid, hi)).toString('hex'));
            buildConsistency(lo, lo + mid, oldHi, first);
          } else {
            if (!first) proof.push(_root(leaves.slice(lo, lo + mid)).toString('hex'));
            buildConsistency(lo + mid, hi, oldHi, false);
          }
        }
        buildConsistency(0, newSize, oldSize, true);
        return proof;
      },

      /**
       * Sign the current tree head with a NIK private key.
       * @param {string} privateKeyB64  base64url-encoded 32-byte Ed25519 seed
       * @param {string} nodeId         signer's node ID
       * @returns {object} signed tree head
       */
      signTreeHead(privateKeyB64, nodeId) {
        const crypto = _getCrypto();
        const head = {
          sha256RootHash: root().toString('hex'),
          signerNodeId: nodeId,
          timestamp: new Date().toISOString(),
          treeSize: leaves.length,
        };
        const headStr = canonicalJSON(head);
        const rawSeed = Buffer.from(privateKeyB64, 'base64url');
        const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
        const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
        const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
        const sigBytes = crypto.sign(null, Buffer.from(headStr, 'utf8'), privKey);
        return { ...head, treeHeadSig: sigBytes.toString('base64url') };
      },
    };
  }

  /**
   * Verify a signed tree head produced by log.signTreeHead().
   * @param {object} signedHead  Output from signTreeHead()
   * @param {object} nik         NIK record with publicKey
   * @returns {boolean}
   */
  function verifyTreeHead(signedHead, nik) {
    const crypto = _getCrypto();
    const { treeHeadSig, ...head } = signedHead;
    const headStr = canonicalJSON(head);
    const rawPub = Buffer.from(nik.publicKey, 'base64url');
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
    const spkiDer = Buffer.concat([spkiHeader, rawPub]);
    const pubKey = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
    const sigBytes = Buffer.from(treeHeadSig, 'base64url');
    return crypto.verify(null, Buffer.from(headStr, 'utf8'), pubKey, sigBytes);
  }

  // ── Security: Key Distribution (KEY_BUNDLE / KEY_REVOCATION) ─────────────

  /**
   * Create a signed KEY_BUNDLE message containing all node NIKs.
   *
   * @param {string}   planId             Plan identifier
   * @param {object[]} nikArray           Array of NIK records to bundle
   * @param {string}   hostPrivateKeyB64  Base64url-encoded host private key seed
   * @returns {object} KEY_BUNDLE message with bundleSig
   */
  function createKeyBundle(planId, nikArray, hostPrivateKeyB64) {
    const bundle = {
      type: 'KEY_BUNDLE',
      planId,
      keys: nikArray,
      timestamp: new Date().toISOString(),
    };
    const keysStr = canonicalJSON(nikArray);
    const rawSeed = Buffer.from(hostPrivateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
    const crypto = _getCrypto();
    const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
    const sigBytes = crypto.sign(null, Buffer.from(keysStr, 'utf8'), privKey);
    bundle.bundleSig = sigBytes.toString('base64url');
    return bundle;
  }

  /**
   * Verify a KEY_BUNDLE signature against a bootstrap NIK and return a populated KeyCache.
   * Expired NIKs are excluded from the cache.
   *
   * @param {object} keyBundle     KEY_BUNDLE message (from createKeyBundle)
   * @param {object} bootstrapNIK  NIK used to verify the bundle signature
   * @returns {Map<string, object>|null}  Map of nodeId → NIK, or null if invalid
   */
  function verifyAndCacheKeys(keyBundle, bootstrapNIK) {
    if (keyBundle.type !== 'KEY_BUNDLE') return null;

    const keysStr = canonicalJSON(keyBundle.keys);
    const rawPub = Buffer.from(bootstrapNIK.publicKey, 'base64url');
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
    const spkiDer = Buffer.concat([spkiHeader, rawPub]);
    const crypto = _getCrypto();
    const pubKey = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
    const sigBytes = Buffer.from(keyBundle.bundleSig, 'base64url');
    const valid = crypto.verify(null, Buffer.from(keysStr, 'utf8'), pubKey, sigBytes);

    if (!valid) return null;

    const cache = new Map();
    for (const nik of keyBundle.keys) {
      if (!isNIKExpired(nik)) {
        cache.set(nik.nodeId, nik);
      }
    }
    return cache;
  }

  /**
   * Create a signed KEY_REVOCATION message.
   *
   * @param {string} planId             Plan identifier
   * @param {string} revokedNodeId      nodeId of the key to revoke
   * @param {string} reason             Human-readable reason for revocation
   * @param {string} hostPrivateKeyB64  Base64url-encoded host private key seed
   * @returns {object} KEY_REVOCATION message with revocationSig
   */
  function createRevocation(planId, revokedNodeId, reason, hostPrivateKeyB64) {
    const payload = {
      type: 'KEY_REVOCATION',
      planId,
      nodeId: revokedNodeId,
      reason,
      timestamp: new Date().toISOString(),
    };
    const payloadStr = canonicalJSON(payload);
    const rawSeed = Buffer.from(hostPrivateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
    const crypto = _getCrypto();
    const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
    const sigBytes = crypto.sign(null, Buffer.from(payloadStr, 'utf8'), privKey);
    return { ...payload, revocationSig: sigBytes.toString('base64url') };
  }

  /**
   * Apply a KEY_REVOCATION to a key cache, removing the revoked entry.
   *
   * @param {Map<string, object>} cache       Key cache (from verifyAndCacheKeys)
   * @param {object}              revocation  KEY_REVOCATION message
   * @returns {boolean}  true if revocation was applied, false if type mismatch
   */
  function applyRevocation(cache, revocation) {
    if (revocation.type !== 'KEY_REVOCATION') return false;
    cache.delete(revocation.nodeId);
    return true;
  }

  // ── Security: BPSec BIB (RFC 9173) ────────────────────────────────────────

  /**
   * Generate a fresh base64url-encoded 32-byte random key suitable for use
   * as an HMAC-SHA-256 Bundle Integrity Block key.
   *
   * @returns {string}  Base64url-encoded 32-byte key (43 characters, no padding)
   */
  function generateBIBKey() {
    const crypto = _getCrypto();
    return crypto.randomBytes(32).toString('base64url');
  }

  /**
   * Add a BPSec Bundle Integrity Block (Context ID 1, RFC 9173) to a bundle.
   * Computes HMAC-SHA-256 over canonicalJSON of the bundle (with any existing
   * bib field stripped) and returns a new bundle object with a bib field added.
   * Does NOT mutate the input bundle.
   *
   * @param {object} bundle       Any LTX message bundle (plain JS object)
   * @param {string} hmacKeyB64   Base64url-encoded raw 32-byte HMAC-SHA-256 key
   * @returns {object}  New bundle: { ...bundleWithoutBib, bib: { contextId, targetBlockNumber, hmac } }
   */
  function addBIB(bundle, hmacKeyB64) {
    const crypto = _getCrypto();
    // Strip any existing bib field (do not mutate original)
    const { bib: _bib, ...bundleWithoutBib } = bundle;
    const rawKey = Buffer.from(hmacKeyB64, 'base64url');
    const msg = Buffer.from(canonicalJSON(bundleWithoutBib), 'utf8');
    const hmacBytes = crypto.createHmac('sha256', rawKey).update(msg).digest();
    return {
      ...bundleWithoutBib,
      bib: {
        contextId: 1,
        targetBlockNumber: 0,
        hmac: hmacBytes.toString('base64url'),
      },
    };
  }

  /**
   * Verify a BPSec Bundle Integrity Block (Context ID 1, RFC 9173).
   * Extracts the bib field, recomputes HMAC-SHA-256 over canonicalJSON of the
   * remaining bundle fields, and compares with bib.hmac.
   *
   * @param {object} bundle       Bundle object (must contain a bib field)
   * @param {string} hmacKeyB64   Base64url-encoded raw 32-byte HMAC-SHA-256 key
   * @returns {{ valid: boolean, reason?: string }}
   */
  function verifyBIB(bundle, hmacKeyB64) {
    const { bib, ...bundleWithoutBib } = bundle;
    if (!bib || typeof bib.hmac !== 'string') {
      return { valid: false, reason: 'missing_bib' };
    }
    const crypto = _getCrypto();
    const rawKey = Buffer.from(hmacKeyB64, 'base64url');
    const msg = Buffer.from(canonicalJSON(bundleWithoutBib), 'utf8');
    const computed = crypto.createHmac('sha256', rawKey).update(msg).digest();
    const expected = Buffer.from(bib.hmac, 'base64url');
    // Constant-time comparison via crypto.timingSafeEqual (available in Node.js)
    let valid = false;
    try {
      valid = computed.length === expected.length && crypto.timingSafeEqual(computed, expected);
    } catch (_) {
      valid = computed.toString('base64url') === bib.hmac;
    }
    if (!valid) return { valid: false, reason: 'hmac_mismatch' };
    return { valid: true };
  }

  // ── Security: Window Manifests ────────────────────────────────────────────

  /**
   * Compute the SHA-256 hex digest of a string or Buffer.
   * Helper for computing artefact hashes before including in a manifest.
   *
   * @param {string|Buffer} data
   * @returns {string}  64-character lowercase hex string
   */
  function artefactSha256(data) {
    const crypto = _getCrypto();
    const buf = typeof data === 'string' ? Buffer.from(data, 'utf8') : data;
    return crypto.createHash('sha256').update(buf).digest('hex');
  }

  /**
   * Create a signed WINDOW_MANIFEST for a set of artefacts.
   * Uses hedged EdDSA: a random nonceSalt is included in the signed payload,
   * ensuring each call produces a unique signature even for identical inputs.
   *
   * @param {string}   planId         Plan identifier
   * @param {number}   windowSeq      Window sequence number
   * @param {Array<{name:string, sha256:string, sizeBytes:number}>} artefacts
   * @param {object}   treeHead       Signed tree head from merkleLog.signTreeHead()
   * @param {string}   privateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
   * @returns {object} WINDOW_MANIFEST with manifestSig
   */
  function createWindowManifest(planId, windowSeq, artefacts, treeHead, privateKeyB64) {
    const crypto = _getCrypto();

    // Generate random 32-byte nonceSalt (hedged EdDSA)
    const nonceSalt = crypto.randomBytes(32).toString('base64url');

    // Build treeHeadRef from signed tree head fields
    const treeHeadRef = {
      sha256RootHash: treeHead.sha256RootHash,
      signerNodeId:   treeHead.signerNodeId,
      timestamp:      treeHead.timestamp,
      treeHeadSig:    treeHead.treeHeadSig,
      treeSize:       treeHead.treeSize,
    };

    // Build manifest without sig
    const manifestWithoutSig = {
      artefacts,
      nonceSalt,
      planId,
      treeHeadRef,
      type: 'WINDOW_MANIFEST',
      windowSeq,
    };

    // Sign canonicalJSON(manifestWithoutSig) using Ed25519
    const dataToSign = Buffer.from(canonicalJSON(manifestWithoutSig), 'utf8');
    const rawSeed = Buffer.from(privateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
    const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
    const sigBytes = crypto.sign(null, dataToSign, privKey);

    return {
      ...manifestWithoutSig,
      manifestSig: sigBytes.toString('base64url'),
    };
  }

  /**
   * Verify a WINDOW_MANIFEST signature against a key cache.
   *
   * @param {object}                  manifest   WINDOW_MANIFEST (from createWindowManifest)
   * @param {Map<string,object>|object} keyCache  Map or plain object of nodeId → NIK
   * @returns {{ valid: boolean, reason?: string }}
   */
  function verifyWindowManifest(manifest, keyCache) {
    const signerNodeId = manifest.treeHeadRef && manifest.treeHeadRef.signerNodeId;
    if (!signerNodeId) return { valid: false, reason: 'missing_signer_node_id' };

    // Look up signer NIK in keyCache
    let signerNIK = null;
    if (keyCache instanceof Map) {
      signerNIK = keyCache.get(signerNodeId);
    } else if (keyCache && typeof keyCache === 'object') {
      signerNIK = keyCache[signerNodeId];
    }

    if (!signerNIK) return { valid: false, reason: 'key_not_in_cache' };
    if (isNIKExpired(signerNIK)) return { valid: false, reason: 'key_expired' };

    // Extract manifestSig and build manifest without it
    const { manifestSig, ...manifestWithoutSig } = manifest;
    if (!manifestSig) return { valid: false, reason: 'missing_manifest_sig' };

    // Verify Ed25519 signature over canonicalJSON(manifestWithoutSig)
    const crypto = _getCrypto();
    const rawPub = Buffer.from(signerNIK.publicKey, 'base64url');
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
    const spkiDer = Buffer.concat([spkiHeader, rawPub]);
    const pubKey = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
    const sigBytes = Buffer.from(manifestSig, 'base64url');
    const dataToVerify = Buffer.from(canonicalJSON(manifestWithoutSig), 'utf8');
    const valid = crypto.verify(null, dataToVerify, pubKey, sigBytes);

    if (!valid) return { valid: false, reason: 'signature_invalid' };
    return { valid: true };
  }

  /**
   * Hedged EdDSA signing: signs dataBytes with a random nonceSalt included in the payload.
   * Produces a unique signature per call even for identical inputs.
   *
   * @param {Buffer} dataBytes      Data to sign
   * @param {string} privateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
   * @returns {{ signature: string, nonceSalt: string }}
   */
  function hedgedSign(dataBytes, privateKeyB64) {
    const crypto = _getCrypto();
    const nonceSalt = crypto.randomBytes(32).toString('base64url');
    const dataB64 = dataBytes.toString('base64url');
    const payload = canonicalJSON({ data: dataB64, nonceSalt });
    const rawSeed = Buffer.from(privateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
    const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
    const sigBytes = crypto.sign(null, Buffer.from(payload, 'utf8'), privKey);
    return {
      signature: sigBytes.toString('base64url'),
      nonceSalt,
    };
  }

  /**
   * Verify a hedged EdDSA signature produced by hedgedSign().
   *
   * @param {Buffer} dataBytes      Original data that was signed
   * @param {string} signature      Base64url-encoded Ed25519 signature
   * @param {string} nonceSalt      Base64url-encoded nonce salt (from hedgedSign result)
   * @param {string} publicKeyB64   Base64url-encoded raw 32-byte Ed25519 public key
   * @returns {boolean}
   */
  function hedgedVerify(dataBytes, signature, nonceSalt, publicKeyB64) {
    const crypto = _getCrypto();
    const dataB64 = dataBytes.toString('base64url');
    const payload = canonicalJSON({ data: dataB64, nonceSalt });
    const rawPub = Buffer.from(publicKeyB64, 'base64url');
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
    const spkiDer = Buffer.concat([spkiHeader, rawPub]);
    const pubKey = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
    const sigBytes = Buffer.from(signature, 'base64url');
    return crypto.verify(null, Buffer.from(payload, 'utf8'), pubKey, sigBytes);
  }

  // ── Sequence Tracking ─────────────────────────────────────────────────────

  /**
   * Create a sequence tracker for a given plan.
   * Tracks both outbound (nextSeq) and inbound (recordSeq) sequence numbers
   * per nodeId, enabling monotonic-increment enforcement and replay rejection.
   *
   * @param {string} planId   Plan identifier used to namespace storage keys
   * @param {object} [storage] Optional storage adapter with get(key)/set(key,val)
   * @returns {object} Sequence tracker instance
   */
  function createSequenceTracker(planId, storage) {
    // storage: optional object with get(key)/set(key,val) interface
    // Default: in-memory Map (for browser/test); in production, pass a storage adapter
    const mem = new Map();
    const store = storage || {
      get: (k) => mem.get(k),
      set: (k, v) => mem.set(k, v),
    };

    const prefix = `ltx_seq_${planId}_`;

    return {
      // Get the next sequence number for this node (increments internal counter)
      nextSeq(nodeId) {
        const key = prefix + nodeId;
        const current = store.get(key) || 0;
        const next = current + 1;
        store.set(key, next);
        return next;
      },

      // Record an incoming sequence number from a remote node.
      // Returns: { accepted: bool, gap: bool, gapSize: number }
      recordSeq(nodeId, seq) {
        const key = prefix + nodeId + '_rx';
        const last = store.get(key) || 0;

        if (seq <= last) {
          return { accepted: false, gap: false, gapSize: 0, reason: 'replay' };
        }

        const gap = seq > last + 1;
        const gapSize = gap ? seq - last - 1 : 0;
        store.set(key, seq);
        return { accepted: true, gap, gapSize };
      },

      // Get current last-seen seq for a node (for checkpoints)
      lastSeenSeq(nodeId) {
        return store.get(prefix + nodeId + '_rx') || 0;
      },

      // Get current outbound seq for a node
      currentSeq(nodeId) {
        return store.get(prefix + nodeId) || 0;
      },

      // Export state snapshot (for persistence / conjunction checkpoints)
      snapshot() {
        const out = {};
        if (mem.size > 0) {
          for (const [k, v] of mem) out[k] = v;
        }
        return out;
      },
    };
  }

  /**
   * Add a seq field to a bundle object using the tracker's next sequence number.
   * @param {object} bundle       Bundle object to stamp
   * @param {object} tracker      Sequence tracker (from createSequenceTracker)
   * @param {string} nodeId       Sending node ID
   * @returns {object}  New bundle with seq field added
   */
  function addSeq(bundle, tracker, nodeId) {
    return { ...bundle, seq: tracker.nextSeq(nodeId) };
  }

  /**
   * Check an incoming bundle's seq field against the tracker.
   * @param {object} bundle         Incoming bundle (must have .seq)
   * @param {object} tracker        Sequence tracker (from createSequenceTracker)
   * @param {string} senderNodeId   Node ID of the sender
   * @returns {{ accepted: boolean, gap: boolean, gapSize: number, reason?: string }}
   */
  function checkSeq(bundle, tracker, senderNodeId) {
    if (typeof bundle.seq !== 'number') {
      return { accepted: false, gap: false, gapSize: 0, reason: 'missing_seq' };
    }
    return tracker.recordSeq(senderNodeId, bundle.seq);
  }

  // ── Security: EOK / MULTI-AUTH ────────────────────────────────────────────

  /**
   * Create an Emergency Override Key (EOK).
   * Same structure as a NIK but with keyType: 'eok'.
   *
   * @param {object}  [options]
   * @param {number}  [options.validDays=30]  Key validity period in days (default: 30)
   * @param {string}  [options.nodeLabel='']  Optional human-readable label
   * @returns {{ eok: object, privateKey: string }}
   */
  function createEOK(options) {
    options = options || {};
    const validDays = options.validDays !== undefined ? options.validDays : 30;
    const nodeLabel = options.nodeLabel !== undefined ? options.nodeLabel : '';

    const crypto = _getCrypto();
    const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519');

    // Export raw 32-byte public key from SPKI DER (last 32 bytes)
    const pubKeyDer = publicKey.export({ type: 'spki', format: 'der' });
    const rawPub    = pubKeyDer.slice(-32);
    const pubKeyB64 = rawPub.toString('base64url');

    // Derive eokId: base64url of first 16 bytes of SHA-256(raw public key)
    const hash  = crypto.createHash('sha256').update(rawPub).digest();
    const eokId = hash.slice(0, 16).toString('base64url');

    const now        = new Date();
    const validUntil = new Date(now.getTime() + validDays * 86400000);

    const eok = {
      eokId,
      publicKey: pubKeyB64,
      algorithm: 'Ed25519',
      keyType:   'eok',
      validFrom:  now.toISOString(),
      validUntil: validUntil.toISOString(),
    };
    if (nodeLabel) eok.label = nodeLabel;

    // Export private key seed from PKCS8 DER (last 32 bytes)
    const privKeyDer = privateKey.export({ type: 'pkcs8', format: 'der' });
    const rawPriv    = privKeyDer.slice(-32);

    return {
      eok,
      privateKey: rawPriv.toString('base64url'),
    };
  }

  /**
   * Create a signed EMERGENCY_OVERRIDE bundle.
   *
   * @param {string} planId             Plan identifier
   * @param {string} action             Action to override (e.g. 'ABORT', 'EXTEND')
   * @param {string} eokPrivateKeyB64   Base64url-encoded raw 32-byte Ed25519 private seed
   * @param {string} eokId              ID of the EOK (from createEOK)
   * @returns {object} EMERGENCY_OVERRIDE bundle with overrideSig
   */
  function createEmergencyOverride(planId, action, eokPrivateKeyB64, eokId) {
    const timestamp = new Date().toISOString();
    const payload = {
      type: 'EMERGENCY_OVERRIDE',
      planId,
      action,
      timestamp,
      eokId,
    };
    const payloadBytes = Buffer.from(canonicalJSON(payload), 'utf8');

    const crypto = _getCrypto();
    const rawSeed    = Buffer.from(eokPrivateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const pkcs8Der   = Buffer.concat([pkcs8Header, rawSeed]);
    const privKey    = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
    const sigBytes   = crypto.sign(null, payloadBytes, privKey);

    return {
      ...payload,
      overrideSig: sigBytes.toString('base64url'),
    };
  }

  /**
   * Verify an EMERGENCY_OVERRIDE bundle against an EOK cache.
   *
   * @param {object}                  overrideBundle  Output from createEmergencyOverride()
   * @param {Map<string,object>|object} eokCache       Map or plain object of eokId → eok
   * @returns {{ valid: boolean, reason?: string }}
   */
  function verifyEmergencyOverride(overrideBundle, eokCache) {
    const { eokId, overrideSig } = overrideBundle;

    // Look up EOK in cache (Map or plain object)
    let eok = null;
    if (eokCache instanceof Map) {
      eok = eokCache.get(eokId);
    } else if (eokCache && typeof eokCache === 'object') {
      eok = eokCache[eokId];
    }

    if (!eok) return { valid: false, reason: 'key_not_in_cache' };

    // Check expiry
    if (Date.now() > new Date(eok.validUntil).getTime()) {
      return { valid: false, reason: 'key_expired' };
    }

    // Reconstruct payload (without overrideSig)
    const { overrideSig: _sig, ...payloadFields } = overrideBundle;
    const payload = {
      type:      payloadFields.type,
      planId:    payloadFields.planId,
      action:    payloadFields.action,
      timestamp: payloadFields.timestamp,
      eokId:     payloadFields.eokId,
    };
    const payloadBytes = Buffer.from(canonicalJSON(payload), 'utf8');

    // Reconstruct Ed25519 public key from raw 32 bytes via SPKI DER
    const crypto = _getCrypto();
    const rawPub     = Buffer.from(eok.publicKey, 'base64url');
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
    const spkiDer    = Buffer.concat([spkiHeader, rawPub]);
    const pubKey     = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });

    const sigBytes = Buffer.from(overrideSig, 'base64url');
    const valid    = crypto.verify(null, payloadBytes, pubKey, sigBytes);

    if (!valid) return { valid: false, reason: 'invalid_signature' };
    return { valid: true };
  }

  /**
   * Create an ACTION_COSIG bundle for multi-person authorisation.
   *
   * @param {string} entryId           Entry identifier to co-sign
   * @param {string} planId            Plan identifier
   * @param {string} cosigNodeId       Node ID of the co-signer
   * @param {string} cosigPrivateKeyB64 Base64url-encoded raw 32-byte Ed25519 private seed
   * @param {object} cosigNIK          NIK of the co-signer (used for cosigNodeId derivation)
   * @returns {object} ACTION_COSIG bundle with cosigSig
   */
  function createCoSig(entryId, planId, cosigNodeId, cosigPrivateKeyB64, cosigNIK) {
    const cosigTime = new Date().toISOString();
    const nodeId    = cosigNIK ? cosigNIK.nodeId : cosigNodeId;

    const payload = {
      type:       'ACTION_COSIG',
      entryId,
      planId,
      cosigNodeId: nodeId,
      cosigTime,
    };
    const payloadBytes = Buffer.from(canonicalJSON(payload), 'utf8');

    const crypto = _getCrypto();
    const rawSeed    = Buffer.from(cosigPrivateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const pkcs8Der   = Buffer.concat([pkcs8Header, rawSeed]);
    const privKey    = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
    const sigBytes   = crypto.sign(null, payloadBytes, privKey);

    return {
      ...payload,
      cosigSig: sigBytes.toString('base64url'),
    };
  }

  /**
   * Check multi-person authorisation by verifying co-signature bundles.
   *
   * @param {object[]}                    cosigBundles   Array of ACTION_COSIG bundles
   * @param {string}                      entryId        Entry identifier to match
   * @param {string}                      planId         Plan identifier to match
   * @param {Map<string,object>|object}   keyCache       Map or plain object of nodeId → NIK
   * @param {number}                      requiredCount  Minimum valid signatures required
   * @returns {{ authorised: boolean, validSigCount: number, invalidCount: number }}
   */
  function checkMultiAuth(cosigBundles, entryId, planId, keyCache, requiredCount) {
    const crypto = _getCrypto();
    let validSigCount = 0;
    let invalidCount  = 0;

    for (const bundle of cosigBundles) {
      // Must match entryId and planId
      if (bundle.entryId !== entryId || bundle.planId !== planId) {
        invalidCount++;
        continue;
      }

      // Look up signer NIK in keyCache
      const nodeId = bundle.cosigNodeId;
      let nik = null;
      if (keyCache instanceof Map) {
        nik = keyCache.get(nodeId);
      } else if (keyCache && typeof keyCache === 'object') {
        nik = keyCache[nodeId];
      }

      if (!nik) {
        invalidCount++;
        continue;
      }

      // Verify signature
      const payload = {
        type:        bundle.type,
        entryId:     bundle.entryId,
        planId:      bundle.planId,
        cosigNodeId: bundle.cosigNodeId,
        cosigTime:   bundle.cosigTime,
      };
      const payloadBytes = Buffer.from(canonicalJSON(payload), 'utf8');

      try {
        const rawPub     = Buffer.from(nik.publicKey, 'base64url');
        const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
        const spkiDer    = Buffer.concat([spkiHeader, rawPub]);
        const pubKey     = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
        const sigBytes   = Buffer.from(bundle.cosigSig, 'base64url');
        const valid      = crypto.verify(null, payloadBytes, pubKey, sigBytes);
        if (valid) {
          validSigCount++;
        } else {
          invalidCount++;
        }
      } catch (_) {
        invalidCount++;
      }
    }

    return {
      authorised:   validSigCount >= requiredCount,
      validSigCount,
      invalidCount,
    };
  }

  // ── Security: Conjunction Checkpoints ─────────────────────────────────────

  /**
   * Create a signed CONJUNCTION_CHECKPOINT bundle.
   * Captures Merkle root, tree size, and last sequence numbers at the start
   * of a communication blackout (conjunction) period.
   *
   * @param {string} planId              Plan identifier
   * @param {string} signerNodeId        Node ID of the signer (from nik.nodeId)
   * @param {{ conjunctionStart: string, conjunctionEnd: string }} conjunctionInfo
   * @param {string} merkleRoot          Hex string from merkleLog.rootHex()
   * @param {number} treeSize            Number from merkleLog.treeSize()
   * @param {object} lastSeqPerNode      Plain object { nodeId: lastSeenSeq, ... }
   * @param {string} privateKeyB64       Base64url raw 32-byte Ed25519 seed
   * @returns {object} Complete CONJUNCTION_CHECKPOINT bundle
   */
  function createConjunctionCheckpoint(planId, signerNodeId, conjunctionInfo, merkleRoot, treeSize, lastSeqPerNode, privateKeyB64) {
    const checkpointWithoutSig = {
      type: 'CONJUNCTION_CHECKPOINT',
      planId,
      checkpointSignerNodeId: signerNodeId,
      checkpointTime: new Date().toISOString(),
      conjunctionStart: conjunctionInfo.conjunctionStart,
      conjunctionEnd: conjunctionInfo.conjunctionEnd,
      merkleRoot,
      treeSize,
      lastSeqPerNode,
    };

    const msgBytes = Buffer.from(canonicalJSON(checkpointWithoutSig), 'utf8');
    const crypto = _getCrypto();
    const rawSeed = Buffer.from(privateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
    const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
    const sigBytes = crypto.sign(null, msgBytes, privKey);

    return { ...checkpointWithoutSig, checkpointSig: sigBytes.toString('base64url') };
  }

  /**
   * Verify a CONJUNCTION_CHECKPOINT bundle.
   *
   * @param {object} checkpoint          CONJUNCTION_CHECKPOINT bundle
   * @param {Map<string,object>|object} keyCache  nodeId → NIK
   * @returns {{ valid: boolean, reason?: string }}
   */
  function verifyConjunctionCheckpoint(checkpoint, keyCache) {
    const { checkpointSig, ...checkpointWithoutSig } = checkpoint;
    if (!checkpointSig) return { valid: false, reason: 'missing_signature' };

    // Find the signer NIK by checkpointSignerNodeId, or try all keys
    const signerNodeId = checkpoint.checkpointSignerNodeId;
    let candidates = [];

    if (signerNodeId) {
      let signerNIK = null;
      if (keyCache instanceof Map) {
        signerNIK = keyCache.get(signerNodeId);
      } else if (keyCache && typeof keyCache === 'object') {
        signerNIK = keyCache[signerNodeId];
      }
      if (signerNIK) {
        candidates = [signerNIK];
      } else {
        return { valid: false, reason: 'key_not_in_cache' };
      }
    } else {
      candidates = keyCache instanceof Map ? [...keyCache.values()] : Object.values(keyCache || {});
    }

    if (candidates.length === 0) return { valid: false, reason: 'key_not_in_cache' };

    const msgBytes = Buffer.from(canonicalJSON(checkpointWithoutSig), 'utf8');
    const sigBuf = Buffer.from(checkpointSig, 'base64url');
    const crypto = _getCrypto();
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');

    for (const nik of candidates) {
      if (isNIKExpired(nik)) continue;
      try {
        const rawPub = Buffer.from(nik.publicKey, 'base64url');
        const spkiDer = Buffer.concat([spkiHeader, rawPub]);
        const pubKey = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
        const valid = crypto.verify(null, msgBytes, pubKey, sigBuf);
        if (valid) return { valid: true };
      } catch (_) {
        // continue
      }
    }

    return { valid: false, reason: 'signature_invalid' };
  }

  /**
   * Create a post-conjunction queue for holding bundles during a blackout period.
   * Bundles queued during the conjunction are processed via drain() after contact resumes.
   *
   * @returns {{ enqueue, size, drain, getQueue }}
   */
  function createPostConjunctionQueue() {
    const queue = [];

    return {
      /**
       * Add a bundle to the queue.
       * @param {object} bundle
       * @returns {number} new queue size
       */
      enqueue(bundle) {
        queue.push(bundle);
        return queue.length;
      },

      /** @returns {number} current queue size */
      size() { return queue.length; },

      /**
       * Process all queued bundles through verifyFn.
       * @param {function(object): { valid: boolean, reason?: string }} verifyFn
       * @returns {{ cleared: number, rejected: number, rejectedBundles: object[] }}
       */
      drain(verifyFn) {
        let cleared = 0;
        let rejected = 0;
        const rejectedBundles = [];
        const items = queue.splice(0);
        for (const bundle of items) {
          const result = verifyFn(bundle);
          if (result && result.valid) {
            cleared++;
          } else {
            rejected++;
            rejectedBundles.push(bundle);
          }
        }
        return { cleared, rejected, rejectedBundles };
      },

      /** @returns {object[]} copy of current queue */
      getQueue() { return queue.slice(); },
    };
  }

  /**
   * Create a signed POST_CONJUNCTION_CLEAR bundle.
   * Signals that the conjunction period has ended and queued bundles have been processed.
   *
   * @param {string} planId          Plan identifier
   * @param {number} queueProcessed  Number of queued bundles that were processed
   * @param {string} privateKeyB64   Base64url raw 32-byte Ed25519 seed
   * @returns {object} Complete POST_CONJUNCTION_CLEAR bundle
   */
  function createPostConjunctionClear(planId, queueProcessed, privateKeyB64) {
    const clearWithoutSig = {
      type: 'POST_CONJUNCTION_CLEAR',
      planId,
      clearedAt: new Date().toISOString(),
      queueProcessed,
    };

    const msgBytes = Buffer.from(canonicalJSON(clearWithoutSig), 'utf8');
    const crypto = _getCrypto();
    const rawSeed = Buffer.from(privateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
    const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
    const sigBytes = crypto.sign(null, msgBytes, privKey);

    return { ...clearWithoutSig, clearSig: sigBytes.toString('base64url') };
  }

  /**
   * Verify a POST_CONJUNCTION_CLEAR bundle.
   * Since the clear bundle has no signer ID field, tries each NIK in the cache.
   *
   * @param {object} clearBundle                     POST_CONJUNCTION_CLEAR bundle
   * @param {Map<string,object>|object} keyCache      nodeId → NIK
   * @returns {{ valid: boolean, signerNodeId?: string, reason?: string }}
   */
  function verifyPostConjunctionClear(clearBundle, keyCache) {
    const { clearSig, ...clearWithoutSig } = clearBundle;
    if (!clearSig) return { valid: false, reason: 'missing_signature' };

    const msgBytes = Buffer.from(canonicalJSON(clearWithoutSig), 'utf8');
    const sigBuf = Buffer.from(clearSig, 'base64url');
    const crypto = _getCrypto();
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');

    const niks = keyCache instanceof Map ? [...keyCache.values()] : Object.values(keyCache || {});
    if (niks.length === 0) return { valid: false, reason: 'key_not_in_cache' };

    for (const nik of niks) {
      if (isNIKExpired(nik)) continue;
      try {
        const rawPub = Buffer.from(nik.publicKey, 'base64url');
        const spkiDer = Buffer.concat([spkiHeader, rawPub]);
        const pubKey = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
        const valid = crypto.verify(null, msgBytes, pubKey, sigBuf);
        if (valid) return { valid: true, signerNodeId: nik.nodeId };
      } catch (_) {
        // continue
      }
    }

    return { valid: false, reason: 'signature_invalid' };
  }


  // ── Security: Release Manifests ───────────────────────────────────────────

  /**
   * Generate an Ed25519 Release Signing Key (RSK) pair.
   * Returns base64url-encoded PKCS8 DER private key and SPKI DER public key.
   *
   * @returns {{ privateKeyB64: string, publicKeyB64: string }}
   */
  function generateRSK() {
    const crypto = _getCrypto();
    const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519', {
      privateKeyEncoding: { type: 'pkcs8', format: 'der' },
      publicKeyEncoding:  { type: 'spki',  format: 'der' },
    });
    return {
      privateKeyB64: privateKey.toString('base64url'),
      publicKeyB64:  publicKey.toString('base64url'),
    };
  }

  /**
   * Compute SHA-256 hex digest of a Buffer.
   * @param {Buffer} buf
   * @returns {string} hex string
   */
  function _sha256hex(buf) {
    const crypto = _getCrypto();
    return crypto.createHash('sha256').update(buf).digest('hex');
  }

  /**
   * Derive the SPKI DER base64url public key from a PKCS8 DER base64url private key.
   * @param {string} privateKeyB64
   * @returns {string} base64url public key
   */
  function _derivePublicKey(privateKeyB64) {
    const crypto = _getCrypto();
    const privKeyObj = crypto.createPrivateKey({
      key: Buffer.from(privateKeyB64, 'base64url'),
      format: 'der',
      type: 'pkcs8',
    });
    const pubKeyObj = crypto.createPublicKey(privKeyObj);
    return pubKeyObj.export({ type: 'spki', format: 'der' }).toString('base64url');
  }

  /**
   * Create a signed release manifest for a package.
   *
   * @param {string}   packageName     Package name (e.g. 'ltx-sdk')
   * @param {string}   version         Version string (e.g. '1.0.0')
   * @param {Array<{ path: string, content: Buffer }>} files  Files to include in manifest
   * @param {string}   privateKeyB64   Base64url-encoded PKCS8 DER Ed25519 private key (from generateRSK)
   * @returns {object} Signed manifest object with manifestSig field
   */
  function createManifest(packageName, version, files, privateKeyB64) {
    const crypto = _getCrypto();
    const body = {
      package: packageName,
      version,
      releaseDate: new Date().toISOString(),
      files: files.map(f => ({ path: f.path, sha256: _sha256hex(f.content) })),
      signerPublicKey: _derivePublicKey(privateKeyB64),
    };
    const payload = Buffer.from(canonicalJSON(body), 'utf8');
    const privKeyObj = crypto.createPrivateKey({
      key: Buffer.from(privateKeyB64, 'base64url'),
      format: 'der',
      type: 'pkcs8',
    });
    const sig = crypto.sign(null, payload, privKeyObj);
    return { ...body, manifestSig: sig.toString('base64url') };
  }

  /**
   * Verify a signed release manifest.
   *
   * @param {object} manifest       Manifest object (from createManifest)
   * @param {string} rskPublicKey   Base64url-encoded SPKI DER Ed25519 public key (from generateRSK)
   * @returns {{ valid: boolean, files?: Array, reason?: string }}
   */
  function verifyManifest(manifest, rskPublicKey) {
    if (manifest.signerPublicKey !== rskPublicKey) {
      return { valid: false, reason: 'key_mismatch' };
    }
    const { manifestSig, ...body } = manifest;
    const payload = Buffer.from(canonicalJSON(body), 'utf8');
    const crypto = _getCrypto();
    const pubKeyObj = crypto.createPublicKey({
      key: Buffer.from(rskPublicKey, 'base64url'),
      format: 'der',
      type: 'spki',
    });
    try {
      const ok = crypto.verify(null, payload, pubKeyObj, Buffer.from(manifestSig, 'base64url'));
      return ok ? { valid: true, files: manifest.files } : { valid: false, reason: 'bad_signature' };
    } catch (e) {
      return { valid: false, reason: 'bad_signature' };
    }
  }


  // ── Security: BPSec BCB (AES-256-GCM Confidentiality) ─────────────────────

  /**
   * Generate a fresh 32-byte AES-256 session key.
   * @returns {Buffer} 32 random bytes
   */
  function generateSessionKey() {
    const crypto = _getCrypto();
    return crypto.randomBytes(32);
  }

  /**
   * Encrypt a payload object using AES-256-GCM (BPSec BCB).
   * Returns a BCB bundle with base64url-encoded nonce, ciphertext, and auth tag.
   *
   * @param {object} payload      Plain JS object to encrypt (will be JSON-serialised)
   * @param {Buffer} sessionKey   32-byte AES-256 key (from generateSessionKey)
   * @returns {{ type: 'BCB', nonce: string, ciphertext: string, tag: string }}
   */
  function encryptWindow(payload, sessionKey) {
    const crypto = _getCrypto();
    const nonce = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', sessionKey, nonce);
    const ct = Buffer.concat([cipher.update(JSON.stringify(payload), 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    const b64url = (buf) => buf.toString('base64url');
    return {
      type: 'BCB',
      nonce: b64url(nonce),
      ciphertext: b64url(ct),
      tag: b64url(tag),
    };
  }

  /**
   * Decrypt a BCB bundle using AES-256-GCM.
   * Verifies the AEAD authentication tag; returns { valid: false } on failure.
   *
   * @param {object} bundle       BCB bundle ({ type, nonce, ciphertext, tag })
   * @param {Buffer} sessionKey   32-byte AES-256 key
   * @returns {{ valid: boolean, plaintext?: object, reason?: string }}
   */
  function decryptWindow(bundle, sessionKey) {
    if (bundle.type !== 'BCB') {
      return { valid: false, reason: 'not_bcb' };
    }
    const crypto = _getCrypto();
    const nonce = Buffer.from(bundle.nonce, 'base64url');
    const ct    = Buffer.from(bundle.ciphertext, 'base64url');
    const tag   = Buffer.from(bundle.tag, 'base64url');
    const decipher = crypto.createDecipheriv('aes-256-gcm', sessionKey, nonce);
    decipher.setAuthTag(tag);
    try {
      const pt = Buffer.concat([decipher.update(ct), decipher.final()]);
      return { valid: true, plaintext: JSON.parse(pt.toString('utf8')) };
    } catch (_) {
      return { valid: false, reason: 'tag_mismatch' };
    }
  }

  // ── Public exports ─────────────────────────────────────────────────────────

  return {
    VERSION,
    SEG_TYPES,
    DEFAULT_QUANTUM,
    DEFAULT_SEGMENTS,
    // Config
    createPlan,
    upgradeConfig,
    // Computation
    computeSegments,
    computeSegmentsMulti,
    buildDelayMatrix,
    totalMin,
    makePlanId,
    // URL
    encodeHash,
    decodeHash,
    buildNodeUrls,
    // ICS
    generateICS,
    // Formatting
    formatHMS,
    formatUTC,
    // REST client
    storeSession,
    getSession,
    downloadICS,
    submitFeedback,
    // Security
    canonicalJSON,
    generateNIK,
    nikFingerprint,
    isNIKExpired,
    signPlan,
    verifyPlan,
    // Key Distribution
    createKeyBundle,
    verifyAndCacheKeys,
    createRevocation,
    applyRevocation,
    // Sequence tracking
    createSequenceTracker,
    addSeq,
    checkSeq,
    // Merkle Audit Log
    createMerkleLog,
    verifyTreeHead,
    // BPSec BIB
    addBIB,
    verifyBIB,
    generateBIBKey,
    // EOK / MULTI-AUTH
    createEOK,
    createEmergencyOverride,
    verifyEmergencyOverride,
    createCoSig,
    checkMultiAuth,
    // Conjunction Checkpoints
    createConjunctionCheckpoint,
    verifyConjunctionCheckpoint,
    createPostConjunctionQueue,
    createPostConjunctionClear,
    verifyPostConjunctionClear,
    // Window Manifests
    artefactSha256,
    createWindowManifest,
    verifyWindowManifest,
    hedgedSign,
    hedgedVerify,
    // BPSec BCB
    generateSessionKey,
    encryptWindow,
    decryptWindow,
    // Release Manifests
    generateRSK,
    createManifest,
    verifyManifest,
  };
}));
