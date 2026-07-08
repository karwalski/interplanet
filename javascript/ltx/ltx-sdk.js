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

  const VERSION = '1.1.0';

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

  // Delay-matrix violation thresholds in seconds (LTX-SPECIFICATION.md §5.4)
  const DELAY_VIOLATION_WARN_S    = 120;
  const DELAY_VIOLATION_DEGRADE_S = 300;

  // Plan-lock timeout factor (LTX-SPECIFICATION.md §5.1)
  const LOCK_TIMEOUT_FACTOR = 2;

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
   * Explicitly upgrade a plan to v3 (LTX-SPECIFICATION.md §4.4).
   * NEVER automatic: v3 fields must not be injected into a v2 plan, because the
   * frozen v2 planId hash is insertion-order-sensitive — the upgraded plan is a
   * NEW plan with a new (v3) planId. The input is not mutated.
   *
   * @param {object} cfg               LTX plan config (v1 or v2)
   * @param {object} [extras]          v3 fields to merge (e.g. { delays, planVersion })
   * @param {object} [extras.delays]   Pair delay matrix { 'A|B': seconds } (sorted-id keys)
   * @param {number} [extras.planVersion]  Plan version counter (default 1)
   * @returns {object} New v3 plan config
   */
  function upgradePlanToV3(cfg, extras) {
    extras = extras || {};
    const c = upgradeConfig(cfg);
    return {
      ...c,
      ...extras,
      v: 3,
      planVersion: extras.planVersion !== undefined ? extras.planVersion : 1,
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
   * One-way delay in seconds between two nodes (LTX-SPECIFICATION.md §3.7).
   * A v3 pair matrix (plan.delays, sorted-id 'A|B' keys) is authoritative where
   * present; otherwise the conservative fallback: HOST pairs use the node's
   * declared delay, non-HOST pairs the sum of both HOST-relative delays
   * (a safe upper bound via the HOST vertex).
   *
   * @param {object} cfg      LTX plan config (v1, v2 or v3)
   * @param {string} nodeIdA
   * @param {string} nodeIdB
   * @returns {number} one-way delay in seconds
   */
  function pairDelay(cfg, nodeIdA, nodeIdB) {
    const c = upgradeConfig(cfg);
    if (nodeIdA === nodeIdB) return 0;
    const delays = c.delays;
    const key = [nodeIdA, nodeIdB].sort().join('|');
    if (delays && typeof delays[key] === 'number') return delays[key];
    const a = c.nodes.find(n => n.id === nodeIdA);
    const b = c.nodes.find(n => n.id === nodeIdB);
    if (!a || !b) throw new Error(`pairDelay: unknown node ${!a ? nodeIdA : nodeIdB}`);
    const hostId = c.nodes[0].id;
    if (nodeIdA === hostId) return b.delay || 0;
    if (nodeIdB === hostId) return a.delay || 0;
    return (a.delay || 0) + (b.delay || 0);
  }

  /**
   * Compute the timed segment array from viewer V's perspective
   * (LTX-SPECIFICATION.md §14.3): a segment attributed to speaker S starts for
   * V at segStart + pairDelay(S, V). Unattributed segments keep their times.
   *
   * @param {object} cfg           LTX plan config (v1, v2 or v3)
   * @param {string} viewerNodeId  Node id of the viewing attendee
   * @returns {Array<{type:string, q:number, start:Date, end:Date, durMin:number,
   *   speaker?:string, label?:string, perspective:'transmit'|'receive'|'neutral',
   *   arrivalOffsetS:number}>}
   */
  function computeSegmentsFor(cfg, viewerNodeId) {
    const c = upgradeConfig(cfg);
    if (!c.nodes.some(n => n.id === viewerNodeId)) {
      throw new Error(`computeSegmentsFor: unknown viewer ${viewerNodeId}`);
    }
    const base = computeSegments(c);
    return base.map((seg, i) => {
      const tpl = c.segments[i];
      const speaker = tpl.speaker;
      if (!speaker || (tpl.type !== 'TX' && tpl.type !== 'SPEAK')) {
        return {
          ...seg,
          ...(speaker ? { speaker } : {}),
          ...(tpl.label ? { label: tpl.label } : {}),
          perspective: 'neutral',
          arrivalOffsetS: 0,
        };
      }
      if (speaker === viewerNodeId) {
        return {
          ...seg, speaker,
          ...(tpl.label ? { label: tpl.label } : {}),
          perspective: 'transmit',
          arrivalOffsetS: 0,
        };
      }
      const shiftS = pairDelay(c, speaker, viewerNodeId);
      return {
        ...seg,
        start: new Date(seg.start.getTime() + shiftS * 1000),
        end: new Date(seg.end.getTime() + shiftS * 1000),
        speaker,
        ...(tpl.label ? { label: tpl.label } : {}),
        perspective: 'receive',
        arrivalOffsetS: shiftS,
      };
    });
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
    if (c.v >= 3) {
      // v3: SHA-256 over RFC 8785 canonical JSON (LTX-SPECIFICATION.md §4.5).
      const digest = _getCrypto().createHash('sha256')
        .update(canonicalJSON(c), 'utf8').digest('hex');
      return `LTX-${date}-${hostStr}-${nodeStr}-v3-${digest.slice(0, 8)}`;
    }
    // FROZEN v2 path (LTX-SPECIFICATION.md §4.3) — do not modify.
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
   * With options.viewerNodeId, emits the per-attendee form (§14.5): one VEVENT
   * per segment at that viewer's local arrival times.
   *
   * @param {object} cfg
   * @param {object} [options]
   * @param {string} [options.viewerNodeId]  Per-attendee export viewer node id
   * @returns {string}  ICS text
   */
  function generateICS(cfg, options) {
    options = options || {};
    if (options.viewerNodeId) return _generateViewerICS(cfg, options.viewerNodeId);
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

  /**
   * v3 pair-delay properties (LTX-SPECIFICATION.md §3.7.2).
   * Emits one LTX-DELAY;PAIR line per entry of the v3 delays map, sorted by key.
   *
   * @param {object} c  Upgraded plan config
   * @returns {string[]}
   */
  function _pairDelayLines(c) {
    const delays = c.delays;
    if (!delays) return [];
    return Object.keys(delays).sort().map(
      pair => `LTX-DELAY;PAIR=${pair}:ONEWAY-ASSUMED=${delays[pair]}`,
    );
  }

  /**
   * Per-attendee export (§14.5): one VEVENT per segment at the viewer's local
   * arrival times. Attributed segments are shifted by pairDelay(speaker, viewer);
   * summaries name the speaker and agenda label.
   *
   * @param {object} cfg           LTX plan config (v1, v2 or v3)
   * @param {string} viewerNodeId  Node id of the viewing attendee
   * @returns {string}  ICS text
   */
  function _generateViewerICS(cfg, viewerNodeId) {
    const c       = upgradeConfig(cfg);
    const segs    = computeSegmentsFor(c, viewerNodeId);
    const planId  = makePlanId(c);
    const nodes   = c.nodes || [];
    const viewer  = nodes.find(n => n.id === viewerNodeId);
    const fmtDT   = dt => dt.toISOString().replace(/[-:.]/g, '').slice(0, 15) + 'Z';
    const dtstamp = fmtDT(new Date());
    const nameOf  = id => (nodes.find(n => n.id === id) || {}).name || id;

    const events = segs.map((seg, i) => {
      const base = seg.label || seg.type;
      let summary;
      if (seg.perspective === 'transmit') {
        summary = `${base} — you present`;
      } else if (seg.perspective === 'receive') {
        summary = `${base} — ${nameOf(seg.speaker)}, arriving after ${Math.round(seg.arrivalOffsetS / 60)} min light-time`;
      } else {
        summary = `${base} (${c.title})`;
      }
      return [
        'BEGIN:VEVENT',
        `UID:${planId}-${viewerNodeId}-${i}@interplanet.live`,
        `DTSTAMP:${dtstamp}`,
        `DTSTART:${fmtDT(seg.start)}`,
        `DTEND:${fmtDT(seg.end)}`,
        `SUMMARY:${summary}`,
        `DESCRIPTION:LTX ${seg.type} segment of "${c.title}" from the perspective of ${viewer ? viewer.name : viewerNodeId}`,
        'LTX:1',
        `LTX-PLANID:${planId}`,
        `LTX-VIEWER:${viewerNodeId}`,
        ...(seg.speaker ? [`LTX-SPEAKER:${seg.speaker}`] : []),
        'END:VEVENT',
      ].join('\r\n');
    });

    return [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//InterPlanet//LTX v1.1//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      ...events,
      ..._pairDelayLines(c),
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
   * @param {object}   [freshness]        Global-scope freshness fields (Story 70.4,
   *                                      LTX-SECURITY.md §11.1): { senderNodeId, seq,
   *                                      issuedAt? }. When present, issuedAt and seq
   *                                      are covered by bundleSig; legacy bundles
   *                                      without them sign the keys array only.
   * @returns {object} KEY_BUNDLE message with bundleSig
   */
  function createKeyBundle(planId, nikArray, hostPrivateKeyB64, freshness) {
    const rawSeed = Buffer.from(hostPrivateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
    const crypto = _getCrypto();
    const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });

    if (freshness) {
      // Global-scope form (Story 70.4): issuedAt and seq are signature-covered.
      const issuedAt = freshness.issuedAt !== undefined ? freshness.issuedAt : new Date().toISOString();
      const signedPayload = canonicalJSON({
        issuedAt,
        keys: nikArray,
        planId,
        senderNodeId: freshness.senderNodeId,
        seq: freshness.seq,
      });
      const sigBytes = crypto.sign(null, Buffer.from(signedPayload, 'utf8'), privKey);
      return {
        type: 'KEY_BUNDLE',
        planId,
        keys: nikArray,
        timestamp: issuedAt,
        issuedAt,
        seq: freshness.seq,
        senderNodeId: freshness.senderNodeId,
        bundleSig: sigBytes.toString('base64url'),
      };
    }

    // Legacy form: signature covers the keys array only.
    const bundle = {
      type: 'KEY_BUNDLE',
      planId,
      keys: nikArray,
      timestamp: new Date().toISOString(),
    };
    const keysStr = canonicalJSON(nikArray);
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
   * @param {object} [freshness]   Global-scope freshness enforcement (Story 70.4,
   *                               LTX-SECURITY.md §11): { tracker, nowMs, maxAgeDays? }
   *                               where tracker is from createGlobalSequenceTracker().
   * @returns {Map<string, object>|null}  Map of nodeId → NIK, or null if invalid
   */
  function verifyAndCacheKeys(keyBundle, bootstrapNIK, freshness) {
    if (keyBundle.type !== 'KEY_BUNDLE') return null;

    const signedPayload = keyBundle.issuedAt !== undefined
      ? canonicalJSON({
          issuedAt: keyBundle.issuedAt,
          keys: keyBundle.keys,
          planId: keyBundle.planId,
          senderNodeId: keyBundle.senderNodeId,
          seq: keyBundle.seq,
        })
      : canonicalJSON(keyBundle.keys); // legacy form
    const rawPub = Buffer.from(bootstrapNIK.publicKey, 'base64url');
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
    const spkiDer = Buffer.concat([spkiHeader, rawPub]);
    const crypto = _getCrypto();
    const pubKey = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
    const sigBytes = Buffer.from(keyBundle.bundleSig, 'base64url');
    const valid = crypto.verify(null, Buffer.from(signedPayload, 'utf8'), pubKey, sigBytes);

    if (!valid) return null;

    // Global-scope freshness enforcement (Story 70.4, LTX-SECURITY.md §11).
    if (freshness) {
      if (keyBundle.issuedAt === undefined ||
          keyBundle.seq === undefined ||
          keyBundle.senderNodeId === undefined) {
        return null; // freshness demanded but bundle lacks the covered fields
      }
      const age = checkIssuedAt(keyBundle.issuedAt, freshness.maxAgeDays !== undefined
        ? { nowMs: freshness.nowMs, maxAgeDays: freshness.maxAgeDays }
        : { nowMs: freshness.nowMs });
      if (!age.accepted) return null;
      const seqRes = freshness.tracker.recordSeq(
        keyBundle.senderNodeId, 'KEY_BUNDLE', keyBundle.seq);
      if (!seqRes.accepted) return null;
    }

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
    if (!bib) return { valid: false, reason: 'missing_bib' };
    if (bib.securityContext === 'ltx-ed25519') {
      // Context-confusion defence: an Ed25519 BIB must not pass HMAC verification.
      return { valid: false, reason: 'context_mismatch' };
    }
    if (typeof bib.hmac !== 'string') {
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

  // ── LTX-native Ed25519 BIB (Story 70.3 · LTX-SECURITY.md §8.2) ────────────

  /**
   * Add an LTX-native Ed25519 BIB (LTX-SECURITY.md §8.2): the bundle is signed
   * with the originating node's NIK, giving per-bundle non-repudiation without
   * a pre-shared pairwise key. The input bundle is not mutated.
   *
   * @param {object} bundle         Any LTX message bundle (plain JS object)
   * @param {string} privateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
   * @returns {object}  New bundle: { ...bundleWithoutBib, bib: { securityContext, targetBlockNumber, sig } }
   */
  function addBIBEd25519(bundle, privateKeyB64) {
    const crypto = _getCrypto();
    const { bib: _bib, ...bundleWithoutBib } = bundle;
    const rawSeed = Buffer.from(privateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const privKey = crypto.createPrivateKey({
      key: Buffer.concat([pkcs8Header, rawSeed]), format: 'der', type: 'pkcs8',
    });
    const msg = Buffer.from(canonicalJSON(bundleWithoutBib), 'utf8');
    const sig = crypto.sign(null, msg, privKey).toString('base64url');
    return {
      ...bundleWithoutBib,
      bib: { securityContext: 'ltx-ed25519', targetBlockNumber: 0, sig },
    };
  }

  /**
   * Verify an LTX-native Ed25519 BIB against the sender's NIK.
   * Rejects HMAC-context BIBs (context-confusion defence).
   *
   * @param {object} bundle  Bundle containing an Ed25519 bib field
   * @param {object} nik     Sender's NIK record with publicKey
   * @returns {{ valid: boolean, reason?: string }}
   */
  function verifyBIBEd25519(bundle, nik) {
    const { bib, ...bundleWithoutBib } = bundle;
    if (!bib) return { valid: false, reason: 'missing_bib' };
    if (bib.securityContext !== 'ltx-ed25519' || typeof bib.sig !== 'string') {
      return { valid: false, reason: 'context_mismatch' };
    }
    const crypto = _getCrypto();
    const rawPub = Buffer.from(nik.publicKey, 'base64url');
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
    const pubKey = crypto.createPublicKey({
      key: Buffer.concat([spkiHeader, rawPub]), format: 'der', type: 'spki',
    });
    const msg = Buffer.from(canonicalJSON(bundleWithoutBib), 'utf8');
    const ok = crypto.verify(null, msg, pubKey, Buffer.from(bib.sig, 'base64url'));
    return ok ? { valid: true } : { valid: false, reason: 'signature_invalid' };
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

  // ── Global freshness scope (Story 70.4 · LTX-SECURITY.md §11.1) ───────────

  /** Default issuedAt max age: 30 days (exceeds the longest conjunction blackout). */
  const ISSUED_AT_MAX_AGE_DAYS = 30;

  /**
   * Create a global-scope sequence tracker keyed (senderNodeId, msgType).
   * Session-independent bundles (KEY_BUNDLE, KEY_REVOCATION, release manifests)
   * exist outside any planId; this scope closes cross-session replay.
   *
   * @param {object} [storage]  Optional storage adapter with get(key)/set(key,val)
   * @returns {object} Global sequence tracker instance
   */
  function createGlobalSequenceTracker(storage) {
    const mem = new Map();
    const store = storage || {
      get: (k) => mem.get(k),
      set: (k, v) => mem.set(k, v),
    };
    const key = (senderNodeId, msgType) => `ltx_gseq_${senderNodeId}_${msgType}`;

    return {
      // Increment and return the next outbound seq for (senderNodeId, msgType)
      nextSeq(senderNodeId, msgType) {
        const k = key(senderNodeId, msgType);
        const next = (store.get(k) || 0) + 1;
        store.set(k, next);
        return next;
      },

      // Record an inbound seq; returns { accepted, gap, gapSize, reason? }
      recordSeq(senderNodeId, msgType, seq) {
        const k = key(senderNodeId, msgType) + '_rx';
        const last = store.get(k) || 0;
        if (seq <= last) return { accepted: false, gap: false, gapSize: 0, reason: 'replay' };
        const gap = seq > last + 1;
        store.set(k, seq);
        return { accepted: true, gap, gapSize: gap ? seq - last - 1 : 0 };
      },

      // Last accepted inbound seq (0 if none seen)
      lastSeenSeq(senderNodeId, msgType) {
        return store.get(key(senderNodeId, msgType) + '_rx') || 0;
      },

      // Export in-memory state snapshot (for persistence)
      snapshot() {
        const out = {};
        for (const [k, v] of mem) out[k] = v;
        return out;
      },
    };
  }

  /**
   * Enforce the issuedAt max-age window for global-scope bundles
   * (LTX-SECURITY.md §11.2). `nowMs` is injected for determinism.
   *
   * @param {string} issuedAt  ISO 8601 timestamp from the bundle
   * @param {{ nowMs: number, maxAgeDays?: number }} opts
   * @returns {{ accepted: boolean, reason?: string }}
   */
  function checkIssuedAt(issuedAt, opts) {
    const issued = Date.parse(issuedAt);
    if (Number.isNaN(issued)) return { accepted: false, reason: 'invalid_issued_at' };
    const maxAgeMs = (opts.maxAgeDays !== undefined ? opts.maxAgeDays : ISSUED_AT_MAX_AGE_DAYS) * 86400000;
    if (opts.nowMs - issued > maxAgeMs) return { accepted: false, reason: 'expired' };
    if (issued - opts.nowMs > 86400000) return { accepted: false, reason: 'future_dated' };
    return { accepted: true };
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

  // ── Session State Machine (Epic 68 · LTX-SPECIFICATION.md §5) ─────────────
  //
  // Pure and time-injected: every event carries nowMs; transition() never reads
  // a clock and returns side-effects as data. Mirrors typescript/ltx/src/session.ts.

  function _participants(plan) {
    return plan.nodes.filter(n => n.role === 'PARTICIPANT');
  }

  /** 2 × one-way delay to the furthest node, in ms (§5.1). */
  function lockTimeoutMs(plan) {
    const maxDelayS = plan.nodes.reduce((m, n) => Math.max(m, n.delay || 0), 0);
    return LOCK_TIMEOUT_FACTOR * maxDelayS * 1000;
  }

  function _quorumCount(plan, quorum) {
    const total = _participants(plan).length;
    if (quorum === 'majority') return Math.floor(total / 2) + 1;
    if (typeof quorum === 'number') return Math.min(Math.max(quorum, 1), total);
    return total; // 'all' (default)
  }

  function _confirmedSubset(ctx) {
    const host = ctx.plan.nodes[0];
    const confirmed = _participants(ctx.plan)
      .filter(n => ctx.confirmations[n.id] === ctx.planId)
      .sort((a, b) => (a.delay || 0) - (b.delay || 0))
      .map(n => n.id);
    return [host.id].concat(confirmed);
  }

  function _fullLockReached(ctx) {
    return _participants(ctx.plan).every(n => ctx.confirmations[n.id] === ctx.planId);
  }

  function _quorumReached(ctx) {
    const confirmed = _participants(ctx.plan)
      .filter(n => ctx.confirmations[n.id] === ctx.planId).length;
    return confirmed >= ctx.quorumThreshold;
  }

  function _declaredDelayS(plan, nodeId) {
    const node = plan.nodes.find(n => n.id === nodeId);
    if (!node) return null;
    if (plan.delays) {
      const hostId = plan.nodes[0].id;
      const key = [hostId, nodeId].sort().join('|');
      if (typeof plan.delays[key] === 'number') return plan.delays[key];
    }
    return node.delay || 0;
  }

  /**
   * Create a session context in DRAFT state.
   * @param {object} plan     v2/v3 plan config
   * @param {string} planId   makePlanId(plan) — supplied so this stays pure
   * @param {object} [options]  { quorum: 'all' | 'majority' | number }
   */
  function createSession(plan, planId, options = {}) {
    return {
      state: 'DRAFT',
      plan,
      planId,
      sessionRootPlanId: planId,
      planVersion: plan.planVersion || 1,
      lock: null,
      lockStartedAtMs: null,
      lockTimeoutMs: lockTimeoutMs(plan),
      confirmations: {},
      mismatched: [],
      quorumThreshold: _quorumCount(plan, options.quorum),
      subset: null,
      degradedReasons: [],
      resumeState: null,
      pendingAmendment: null,
    };
  }

  function _moved(ctx, to, event, effects, detail) {
    const entry = {
      type: 'state_transition',
      from: ctx.state,
      to,
      event: event.type,
      atMs: event.nowMs,
    };
    if (detail) entry.detail = detail;
    return {
      ctx: Object.assign({}, ctx, { state: to }),
      effects: [{ kind: 'audit', entry }].concat(effects),
    };
  }

  function _unchanged(ctx, effects = []) {
    return { ctx, effects };
  }

  function _invalidEvent(ctx, event) {
    return {
      kind: 'notify', level: 'warn', code: 'INVALID_EVENT',
      detail: `${event.type} ignored in state ${ctx.state}`,
    };
  }

  function _degrade(ctx, event, reason, extra = []) {
    const next = Object.assign({}, ctx, {
      degradedReasons: ctx.degradedReasons.concat([reason]),
    });
    const effects = [
      { kind: 'notify', level: 'warn', code: 'DEGRADED', detail: reason },
      { kind: 'escalate', code: 'DEGRADED', detail: reason },
    ].concat(extra);
    if (ctx.state === 'DEGRADED') return _unchanged(next, effects.slice(0, 1));
    return _moved(next, 'DEGRADED', event, effects, reason);
  }

  /**
   * Advance the session state machine (pure).
   * @param {object} ctx    Session context from createSession()/transition()
   * @param {object} event  { type, nowMs, ... }
   * @returns {{ctx: object, effects: object[]}}
   */
  function transition(ctx, event) {
    switch (event.type) {
      case 'START_LOCK': {
        if (ctx.state !== 'DRAFT') return _unchanged(ctx, [_invalidEvent(ctx, event)]);
        const hostId = ctx.plan.nodes[0].id;
        const next = Object.assign({}, ctx, {
          lockStartedAtMs: event.nowMs,
          confirmations: Object.assign({}, ctx.confirmations, { [hostId]: ctx.planId }),
        });
        return _moved(next, 'LOCKING', event, []);
      }

      case 'PLAN_CONFIRM': {
        if (ctx.state !== 'LOCKING' && ctx.state !== 'DEGRADED') {
          return _unchanged(ctx, [_invalidEvent(ctx, event)]);
        }
        const next = Object.assign({}, ctx, {
          confirmations: Object.assign({}, ctx.confirmations, { [event.nodeId]: event.planId }),
        });
        if (event.planId !== ctx.planId) {
          next.mismatched = ctx.mismatched.filter(id => id !== event.nodeId).concat([event.nodeId]);
          return _unchanged(next, [{
            kind: 'notify', level: 'warn', code: 'PLANID_MISMATCH',
            detail: `${event.nodeId} confirmed ${event.planId}, expected ${ctx.planId} (resolve per §5.5)`,
          }]);
        }
        next.mismatched = ctx.mismatched.filter(id => id !== event.nodeId);
        if (_fullLockReached(next)) {
          const locked = Object.assign({}, next, { lock: 'FULL', subset: null });
          return _moved(locked, 'LOCKED', event, [
            { kind: 'notify', level: 'info', code: 'LOCKED', detail: 'full lock achieved' },
          ]);
        }
        return _unchanged(next);
      }

      case 'TICK': {
        if (ctx.state !== 'LOCKING') return _unchanged(ctx);
        if (ctx.lockStartedAtMs === null) return _unchanged(ctx);
        if (event.nowMs - ctx.lockStartedAtMs < ctx.lockTimeoutMs) return _unchanged(ctx);
        if (_quorumReached(ctx)) {
          const subset = _confirmedSubset(ctx);
          const next = Object.assign({}, ctx, { lock: 'QUORUM', subset });
          const missing = _participants(ctx.plan)
            .filter(n => ctx.confirmations[n.id] !== ctx.planId).map(n => n.id);
          return _degrade(next, event,
            `quorum lock with subset [${subset.join(',')}]; unconfirmed: [${missing.join(',')}]`);
        }
        return _degrade(ctx, event, 'plan-lock timeout without quorum');
      }

      case 'SESSION_START': {
        if (ctx.state === 'LOCKED') return _moved(ctx, 'ACTIVE', event, []);
        if (ctx.state === 'DEGRADED' && ctx.lock !== null) {
          return _unchanged(ctx, [{
            kind: 'escalate', code: 'DEGRADED_START',
            detail: 'session start requested while DEGRADED; HOST decision required',
          }]);
        }
        return _unchanged(ctx, [_invalidEvent(ctx, event)]);
      }

      case 'DELAY_MEASURED': {
        if (ctx.state !== 'ACTIVE' && ctx.state !== 'LOCKED' && ctx.state !== 'DEGRADED') {
          return _unchanged(ctx);
        }
        const declared = _declaredDelayS(ctx.plan, event.nodeId);
        if (declared === null) return _unchanged(ctx, [_invalidEvent(ctx, event)]);
        const deviation = Math.abs(event.measuredDelayS - declared);
        if (deviation > DELAY_VIOLATION_DEGRADE_S) {
          return _degrade(ctx, event,
            `delay violation ${event.nodeId}: measured ${event.measuredDelayS}s vs declared ${declared}s (>${DELAY_VIOLATION_DEGRADE_S}s)`);
        }
        if (deviation > DELAY_VIOLATION_WARN_S) {
          return _unchanged(ctx, [{
            kind: 'notify', level: 'warn', code: 'DELAY_VIOLATION',
            detail: `${event.nodeId}: measured ${event.measuredDelayS}s vs declared ${declared}s`,
          }]);
        }
        return _unchanged(ctx);
      }

      case 'EOK_OVERRIDE': {
        if (ctx.state === 'COMPLETE' || ctx.state === 'ABORTED') return _unchanged(ctx);
        if (!event.verified) {
          return _unchanged(ctx, [{
            kind: 'notify', level: 'error', code: 'OVERRIDE_REJECTED',
            detail: event.reason || 'override failed verification',
          }]);
        }
        if (ctx.state === 'EMERGENCY_HOLD') return _unchanged(ctx);
        const next = Object.assign({}, ctx, { resumeState: ctx.state });
        return _moved(next, 'EMERGENCY_HOLD', event, [
          { kind: 'notify', level: 'error', code: 'EMERGENCY_HOLD', detail: event.reason || 'verified EOK override' },
        ]);
      }

      case 'AMENDMENT_PROPOSED': {
        if (ctx.state !== 'ACTIVE' && ctx.state !== 'LOCKED' && ctx.state !== 'DEGRADED') {
          return _unchanged(ctx, [_invalidEvent(ctx, event)]);
        }
        if (event.planVersion !== ctx.planVersion + 1) {
          return _unchanged(ctx, [{
            kind: 'notify', level: 'error', code: 'AMENDMENT_REJECTED',
            detail: `planVersion ${event.planVersion} != ${ctx.planVersion} + 1`,
          }]);
        }
        const affected = ctx.plan.nodes.filter(n => event.affectedNodeIds.includes(n.id));
        const maxDelayS = affected.reduce((m, n) => Math.max(m, n.delay || 0), 0);
        const pending = {
          planId: event.planId,
          planVersion: event.planVersion,
          affectedNodeIds: event.affectedNodeIds,
          confirmed: [],
          proposedAtMs: event.nowMs,
          timeoutMs: LOCK_TIMEOUT_FACTOR * maxDelayS * 1000,
        };
        return _unchanged(Object.assign({}, ctx, { pendingAmendment: pending }), [{
          kind: 'notify', level: 'info', code: 'AMENDMENT_PROPOSED',
          detail: `plan ${event.planId} v${event.planVersion}; awaiting [${event.affectedNodeIds.join(',')}]`,
        }]);
      }

      case 'AMENDMENT_CONFIRMED': {
        const pa = ctx.pendingAmendment;
        if (!pa || event.planId !== pa.planId) return _unchanged(ctx, [_invalidEvent(ctx, event)]);
        if (!pa.affectedNodeIds.includes(event.nodeId)) return _unchanged(ctx);
        const confirmed = pa.confirmed.filter(id => id !== event.nodeId).concat([event.nodeId]);
        if (confirmed.length < pa.affectedNodeIds.length) {
          return _unchanged(Object.assign({}, ctx, {
            pendingAmendment: Object.assign({}, pa, { confirmed }),
          }));
        }
        const next = Object.assign({}, ctx, {
          planId: pa.planId,
          planVersion: pa.planVersion,
          pendingAmendment: null,
        });
        return _unchanged(next, [{
          kind: 'notify', level: 'info', code: 'AMENDMENT_APPLIED',
          detail: `plan ${pa.planId} v${pa.planVersion} in effect (root ${ctx.sessionRootPlanId})`,
        }]);
      }

      case 'HOST_DECISION': {
        if (event.decision === 'abort') {
          if (ctx.state === 'COMPLETE' || ctx.state === 'ABORTED') return _unchanged(ctx);
          return _moved(ctx, 'ABORTED', event, []);
        }
        if (event.decision === 'resume' && ctx.state === 'EMERGENCY_HOLD') {
          const back = ctx.resumeState || 'ACTIVE';
          return _moved(Object.assign({}, ctx, { resumeState: null }), back, event, []);
        }
        if (event.decision === 'continue' && ctx.state === 'DEGRADED') {
          return _moved(ctx, 'ACTIVE', event, [{
            kind: 'notify', level: 'warn', code: 'CONTINUE_DEGRADED',
            detail: ctx.subset
              ? `continuing with subset [${ctx.subset.join(',')}]`
              : 'continuing despite degraded condition',
          }]);
        }
        return _unchanged(ctx, [_invalidEvent(ctx, event)]);
      }

      case 'SESSION_END': {
        if (ctx.state === 'ACTIVE' || ctx.state === 'DEGRADED') {
          return _moved(ctx, 'COMPLETE', event, []);
        }
        return _unchanged(ctx, [_invalidEvent(ctx, event)]);
      }

      default:
        return _unchanged(ctx, [_invalidEvent(ctx, event)]);
    }
  }

  // ── Plan Amendments (Epic 68.3 · LTX-SPECIFICATION.md §6.4) ────────────────

  /** SHA-256 hex of the RFC 8785 canonical JSON of a plan. */
  function planHash(plan) {
    return _getCrypto().createHash('sha256')
      .update(canonicalJSON(plan), 'utf8').digest('hex');
  }

  /**
   * Create a signed amendment of signedPlan with `changes` applied.
   * Successor is always v3: planVersion+1, prevPlanHash = SHA-256(canonicalJSON
   * of predecessor) — never the legacy v2 polynomial hash (LTX-SECURITY §7.6).
   */
  function createAmendment(signedPlan, changes, privateKeyB64) {
    const prev = signedPlan.plan;
    const prevVersion = prev.planVersion || 1;
    const successor = Object.assign({}, prev, changes, {
      v: 3,
      planVersion: prevVersion + 1,
      prevPlanHash: planHash(prev),
    });
    return signPlan(successor, privateKeyB64);
  }

  /**
   * Verify an amendment chain: chain[0] is the root, each later element a
   * successive amendment (signature, planVersion +1, prevPlanHash match).
   */
  function verifyAmendmentChain(chain, keyCache) {
    if (!Array.isArray(chain) || chain.length === 0) {
      return { valid: false, reason: 'empty_chain' };
    }
    for (let i = 0; i < chain.length; i++) {
      const sig = verifyPlan(chain[i], keyCache);
      if (!sig.valid) return { valid: false, reason: `link_${i}_${sig.reason}` };
    }
    const root = chain[0].plan;
    if (root.prevPlanHash !== undefined) {
      return { valid: false, reason: 'root_has_prev_hash' };
    }
    let prevPlan = root;
    let prevVersion = root.planVersion || 1;
    for (let i = 1; i < chain.length; i++) {
      const p = chain[i].plan;
      if (p.v !== 3) return { valid: false, reason: `link_${i}_not_v3` };
      if ((p.planVersion || 0) !== prevVersion + 1) {
        return { valid: false, reason: `link_${i}_version_gap` };
      }
      if (p.prevPlanHash !== planHash(prevPlan)) {
        return { valid: false, reason: `link_${i}_prev_hash_mismatch` };
      }
      prevPlan = p;
      prevVersion = p.planVersion;
    }
    return { valid: true };
  }

  /**
   * §6.2 drift response: amend by inserting a BUFFER segment after segment
   * index afterIndex (append with -1). Elapsed segments must not be touched.
   */
  function insertBufferViaAmendment(signedPlan, options, privateKeyB64) {
    const prev = signedPlan.plan;
    const segments = prev.segments.slice();
    const at = options.afterIndex < 0 ? segments.length : options.afterIndex + 1;
    segments.splice(at, 0, { type: 'BUFFER', q: options.q });
    return createAmendment(signedPlan, { segments }, privateKeyB64);
  }

  // ── Registers (Epic 69.1 · LTX-SPECIFICATION.md §9/§10) ────────────────────
  //
  // Registers are deterministic reductions over the signed append-only audit
  // log. Mirrors typescript/ltx/src/registers.ts.

  const ENTRY_PREFIX = {
    question: 'QST', question_response: 'QST',
    action: 'ACT', action_update: 'ACT',
    amendment: 'AMD', state_transition: 'STA',
    merge_snapshot: 'MRG', decision: 'DEC',
  };

  function _regSign(dataStr, privateKeyB64) {
    const crypto = _getCrypto();
    const rawSeed = Buffer.from(privateKeyB64, 'base64url');
    const pkcs8Der = Buffer.concat([
      Buffer.from('302e020100300506032b657004220420', 'hex'), rawSeed,
    ]);
    const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
    return crypto.sign(null, Buffer.from(dataStr, 'utf8'), privKey).toString('base64url');
  }

  function _regVerify(dataStr, sigB64, nik) {
    const crypto = _getCrypto();
    const rawPub = Buffer.from(nik.publicKey, 'base64url');
    const spkiDer = Buffer.concat([
      Buffer.from('302a300506032b6570032100', 'hex'), rawPub,
    ]);
    const pubKey = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
    return crypto.verify(null, Buffer.from(dataStr, 'utf8'), pubKey, Buffer.from(sigB64, 'base64url'));
  }

  /**
   * Create a signed register entry (LTX-SECURITY.md §9.5).
   * @param {string} type     One of ENTRY_PREFIX keys
   * @param {object} content
   * @param {object} opts     { sessionId, nodeId, seq, timestamp, privateKeyB64, entryId? }
   */
  function createRegisterEntry(type, content, opts) {
    const entryId = opts.entryId || `${ENTRY_PREFIX[type]}-${opts.nodeId}-${opts.seq}`;
    const unsigned = {
      entryId,
      sessionId: opts.sessionId,
      nodeId: opts.nodeId,
      seq: opts.seq,
      type,
      content,
      timestamp: opts.timestamp,
    };
    const sig = _regSign(canonicalJSON(unsigned), opts.privateKeyB64);
    return Object.assign({}, unsigned, { sig });
  }

  /** Verify a register entry against keyCache[entry.nodeId] → NIK. */
  function verifyRegisterEntry(entry, keyCache) {
    if (!entry || !entry.sig) return { valid: false, reason: 'missing_sig' };
    const nik = keyCache instanceof Map ? keyCache.get(entry.nodeId) : keyCache[entry.nodeId];
    if (!nik) return { valid: false, reason: 'key_not_in_cache' };
    const unsigned = Object.assign({}, entry);
    delete unsigned.sig;
    const ok = _regVerify(canonicalJSON(unsigned), entry.sig, nik);
    return ok ? { valid: true } : { valid: false, reason: 'signature_invalid' };
  }

  /** Total order (timestamp, nodeId, seq) — LTX-SPECIFICATION.md §8.2. */
  function compareEntries(a, b) {
    if (a.timestamp !== b.timestamp) return a.timestamp < b.timestamp ? -1 : 1;
    if (a.nodeId !== b.nodeId) return a.nodeId < b.nodeId ? -1 : 1;
    return a.seq - b.seq;
  }

  /** De-duplicate by (nodeId, seq) and sort into the §8.2 total order. */
  function orderEntries(entries) {
    const seen = new Map();
    for (const e of entries) {
      const key = `${e.nodeId} ${e.seq}`;
      if (!seen.has(key)) seen.set(key, e);
    }
    return [...seen.values()].sort(compareEntries);
  }

  function _conflictWins(incoming, current) {
    if (incoming.version !== current.version) return incoming.version > current.version;
    return incoming.editor < current.editor;
  }

  /** Reduce question register state (LTX-SPECIFICATION.md §9.4). Pure. */
  function reduceQuestions(entries) {
    const byId = {}, winners = {}, superseded = [];
    for (const e of orderEntries(entries)) {
      if (e.type === 'question') {
        const qid = e.entryId;
        if (byId[qid]) { superseded.push(e.entryId); continue; }
        winners[qid] = { version: 1, editor: e.nodeId, entryId: e.entryId };
        byId[qid] = Object.assign(
          { qid, text: String(e.content.text ?? ''), submitter: e.nodeId },
          e.content.urgency !== undefined ? { urgency: String(e.content.urgency) } : {},
          e.content.intendedWindow !== undefined ? { intendedWindow: String(e.content.intendedWindow) } : {},
          { status: 'OPEN', version: 1 },
        );
      } else if (e.type === 'question_response') {
        const qid = String(e.content.qid ?? '');
        const q = byId[qid];
        if (!q) { superseded.push(e.entryId); continue; }
        const version = Number(e.content.version ?? q.version + 1);
        const incoming = { version, editor: e.nodeId, entryId: e.entryId };
        const current = winners[qid];
        if (current && !_conflictWins(incoming, current)) { superseded.push(e.entryId); continue; }
        if (current && current.entryId !== q.qid) superseded.push(current.entryId);
        winners[qid] = incoming;
        byId[qid] = Object.assign({}, q,
          { status: e.content.status === 'WITHDRAWN' ? 'WITHDRAWN' : 'ANSWERED' },
          e.content.response !== undefined ? { response: String(e.content.response) } : {},
          { responder: e.nodeId, version },
        );
      }
    }
    return { byId, superseded };
  }

  const _ACTION_STATUSES = ['PROPOSED', 'ACCEPTED', 'REJECTED', 'DONE'];

  /** Reduce action register state (LTX-SPECIFICATION.md §10.2). Pure. */
  function reduceActions(entries) {
    const byId = {}, winners = {}, superseded = [];
    for (const e of orderEntries(entries)) {
      if (e.type === 'action') {
        const aid = e.entryId;
        if (byId[aid]) { superseded.push(e.entryId); continue; }
        winners[aid] = { version: 1, editor: e.nodeId, entryId: e.entryId };
        byId[aid] = Object.assign(
          { aid, description: String(e.content.description ?? '') },
          e.content.owner !== undefined ? { owner: String(e.content.owner) } : {},
          e.content.dueTimeUTC !== undefined ? { dueTimeUTC: String(e.content.dueTimeUTC) } : {},
          e.content.originWindow !== undefined ? { originWindow: String(e.content.originWindow) } : {},
          { status: 'PROPOSED', version: 1 },
        );
      } else if (e.type === 'action_update') {
        const aid = String(e.content.aid ?? '');
        const a = byId[aid];
        if (!a) { superseded.push(e.entryId); continue; }
        const version = Number(e.content.version ?? a.version + 1);
        const incoming = { version, editor: e.nodeId, entryId: e.entryId };
        const current = winners[aid];
        if (current && !_conflictWins(incoming, current)) { superseded.push(e.entryId); continue; }
        if (current && current.entryId !== a.aid) superseded.push(current.entryId);
        winners[aid] = incoming;
        byId[aid] = Object.assign({}, a,
          { status: _ACTION_STATUSES.includes(e.content.status) ? e.content.status : a.status },
          e.content.description !== undefined ? { description: String(e.content.description) } : {},
          e.content.owner !== undefined ? { owner: String(e.content.owner) } : {},
          e.content.dueTimeUTC !== undefined ? { dueTimeUTC: String(e.content.dueTimeUTC) } : {},
          { version },
        );
      }
    }
    return { byId, superseded };
  }

  /** Re-emit v3 plan question seeds as signed log entries at lock (§9.2). */
  function emitQuestionSeeds(seeds, opts) {
    let seq = opts.startSeq !== undefined ? opts.startSeq : opts.seq;
    return seeds.map(seed => {
      const entry = createRegisterEntry('question', seed,
        Object.assign({}, opts, { seq }));
      seq += 1;
      return entry;
    });
  }

  // ── Merge + partition recovery (Epic 69.2 · LTX-SPECIFICATION.md §8) ───────

  /**
   * Deterministic merge of two entry logs (§8.2): verify, union de-duplicated
   * by (nodeId, seq), order totally. Symmetric by construction.
   */
  function mergeLogs(entriesA, entriesB, keyCache) {
    const rejected = [], verified = [];
    for (const entry of entriesA.concat(entriesB)) {
      const v = verifyRegisterEntry(entry, keyCache);
      if (v.valid) verified.push(entry);
      else rejected.push({ entry, reason: v.reason || 'invalid' });
    }
    return { entries: orderEntries(verified), rejected };
  }

  /** Merkle root over an ordered entry list (leaves in log order). */
  function entriesRoot(entries) {
    const log = createMerkleLog();
    for (const e of entries) log.append(e);
    return log.rootHex();
  }

  /** MERGE segment (§8.4): merge + HOST-signed merge_snapshot entry. */
  function runMergeSegment(localEntries, remoteEntries, keyCache, opts) {
    const merged = mergeLogs(localEntries, remoteEntries, keyCache);
    const questions = reduceQuestions(merged.entries);
    const actions = reduceActions(merged.entries);
    const snapshot = createRegisterEntry('merge_snapshot', {
      mergedRoot: entriesRoot(merged.entries),
      entryCount: merged.entries.length,
      rejectedCount: merged.rejected.length,
      questionRegister: questions.byId,
      actionRegister: actions.byId,
      superseded: questions.superseded.concat(actions.superseded),
    }, opts);
    return { merged, snapshot };
  }

  /**
   * Partition recovery (§8.3 / LTX-SECURITY §9.4): verify remote tree head,
   * accept verified prefix extension, else deterministic merge, else flag
   * divergence.
   */
  function recoverPartition(localEntries, remoteEntries, remoteHead, remoteNik, keyCache) {
    if (!verifyTreeHead(remoteHead, remoteNik)) {
      return { action: 'divergent', reason: 'tree_head_signature_invalid' };
    }
    if (remoteHead.treeSize !== remoteEntries.length ||
        entriesRoot(remoteEntries) !== remoteHead.sha256RootHash) {
      return { action: 'divergent', reason: 'remote_entries_do_not_match_head' };
    }
    if (localEntries.length <= remoteEntries.length) {
      const isPrefix = localEntries.every(
        (e, i) => canonicalJSON(e) === canonicalJSON(remoteEntries[i]));
      if (isPrefix) return { action: 'accept_extension', entries: remoteEntries.slice() };
    }
    const merged = mergeLogs(localEntries, remoteEntries, keyCache);
    return { action: 'merged', entries: merged.entries, rejected: merged.rejected };
  }

  // ── CBOR (Epic 70.1 · RFC 8949 deterministic subset) ───────────────────────
  //
  // Supported: unsigned/negative integers, byte strings, text strings, arrays,
  // maps, booleans, null, and tags. Encoding follows the RFC 8949 §4.2.1 core
  // deterministic profile: definite lengths only, shortest-form integer heads,
  // map keys sorted bytewise by their encoded form.
  //
  // Values map JS ⇄ CBOR: number (integer only) ⇄ major 0/1, Uint8Array/Buffer
  // ⇄ major 2, string ⇄ major 3, Array ⇄ major 4, plain object or Map ⇄ major 5,
  // CborTag ⇄ major 6, true/false/null ⇄ major 7. Mirrors typescript/ltx/src/cbor.ts.

  /** Tagged value wrapper (major type 6). */
  class CborTag {
    constructor(tag, value) {
      this.tag = tag;
      this.value = value;
    }
  }

  function _encodeCborHead(major, arg) {
    if (!Number.isSafeInteger(arg) || arg < 0) throw new Error('cbor: invalid length/argument');
    if (arg < 24) return Buffer.from([(major << 5) | arg]);
    if (arg < 0x100) return Buffer.from([(major << 5) | 24, arg]);
    if (arg < 0x10000) {
      const b = Buffer.alloc(3);
      b[0] = (major << 5) | 25;
      b.writeUInt16BE(arg, 1);
      return b;
    }
    if (arg < 0x100000000) {
      const b = Buffer.alloc(5);
      b[0] = (major << 5) | 26;
      b.writeUInt32BE(arg, 1);
      return b;
    }
    const b = Buffer.alloc(9);
    b[0] = (major << 5) | 27;
    b.writeBigUInt64BE(BigInt(arg), 1);
    return b;
  }

  /**
   * Encode a value to deterministic CBOR bytes.
   * Floats are rejected (integers only); map keys sort bytewise by encoded form.
   *
   * @param {*} value  Value to encode (see supported types above)
   * @returns {Buffer}
   */
  function encodeCbor(value) {
    if (value === null) return Buffer.from([0xf6]);
    if (value === true) return Buffer.from([0xf5]);
    if (value === false) return Buffer.from([0xf4]);

    if (typeof value === 'number') {
      if (!Number.isSafeInteger(value)) throw new Error('cbor: only integers supported');
      return value >= 0 ? _encodeCborHead(0, value) : _encodeCborHead(1, -value - 1);
    }

    if (typeof value === 'string') {
      const bytes = Buffer.from(value, 'utf8');
      return Buffer.concat([_encodeCborHead(3, bytes.length), bytes]);
    }

    if (value instanceof Uint8Array) {
      const bytes = Buffer.from(value);
      return Buffer.concat([_encodeCborHead(2, bytes.length), bytes]);
    }

    if (value instanceof CborTag) {
      return Buffer.concat([_encodeCborHead(6, value.tag), encodeCbor(value.value)]);
    }

    if (Array.isArray(value)) {
      const parts = value.map(encodeCbor);
      return Buffer.concat([_encodeCborHead(4, value.length)].concat(parts));
    }

    if (value instanceof Map || (typeof value === 'object' && value !== null)) {
      const entries = value instanceof Map
        ? [...value.entries()]
        : Object.entries(value).map(([k, v]) => {
            // COSE header labels are integers; encode numeric-looking keys as ints.
            const n = Number(k);
            return [Number.isSafeInteger(n) && String(n) === k ? n : k, v];
          });
      // Deterministic: sort by encoded key bytes (RFC 8949 §4.2.1).
      const encoded = entries.map(([k, v]) => [encodeCbor(k), encodeCbor(v)]);
      encoded.sort((a, b) => Buffer.compare(a[0], b[0]));
      const flat = [];
      for (const [k, v] of encoded) { flat.push(k); flat.push(v); }
      return Buffer.concat([_encodeCborHead(5, encoded.length)].concat(flat));
    }

    throw new Error(`cbor: unsupported type ${typeof value}`);
  }

  function _readCborHead(s) {
    const initial = s.buf[s.pos];
    if (initial === undefined) throw new Error('cbor: truncated');
    s.pos += 1;
    const major = initial >> 5;
    const info = initial & 0x1f;
    if (info < 24) return { major, arg: info };
    if (info === 24) { const v = s.buf[s.pos]; s.pos += 1; return { major, arg: v }; }
    if (info === 25) { const v = s.buf.readUInt16BE(s.pos); s.pos += 2; return { major, arg: v }; }
    if (info === 26) { const v = s.buf.readUInt32BE(s.pos); s.pos += 4; return { major, arg: v }; }
    if (info === 27) {
      const v = s.buf.readBigUInt64BE(s.pos);
      s.pos += 8;
      if (v > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('cbor: integer too large');
      return { major, arg: Number(v) };
    }
    throw new Error('cbor: indefinite lengths not supported');
  }

  function _decodeCborItem(s) {
    const first = s.buf[s.pos];
    if (first === 0xf6) { s.pos += 1; return null; }
    if (first === 0xf5) { s.pos += 1; return true; }
    if (first === 0xf4) { s.pos += 1; return false; }

    const { major, arg } = _readCborHead(s);
    switch (major) {
      case 0: return arg;
      case 1: return -arg - 1;
      case 2: {
        const bytes = s.buf.slice(s.pos, s.pos + arg);
        if (bytes.length !== arg) throw new Error('cbor: truncated bstr');
        s.pos += arg;
        return bytes;
      }
      case 3: {
        const bytes = s.buf.slice(s.pos, s.pos + arg);
        if (bytes.length !== arg) throw new Error('cbor: truncated tstr');
        s.pos += arg;
        return bytes.toString('utf8');
      }
      case 4: {
        const out = [];
        for (let i = 0; i < arg; i++) out.push(_decodeCborItem(s));
        return out;
      }
      case 5: {
        const map = new Map();
        for (let i = 0; i < arg; i++) {
          const k = _decodeCborItem(s);
          map.set(k instanceof Uint8Array ? Buffer.from(k).toString('base64url') : k, _decodeCborItem(s));
        }
        return map;
      }
      case 6: return new CborTag(arg, _decodeCborItem(s));
      default: throw new Error(`cbor: unsupported major type ${major} / simple value`);
    }
  }

  /**
   * Decode deterministic CBOR bytes to a value (maps decode to Map).
   * Byte-string map keys decode to base64url strings; trailing bytes rejected.
   *
   * @param {Uint8Array|Buffer} bytes
   * @returns {*}
   */
  function decodeCbor(bytes) {
    const s = { buf: Buffer.from(bytes), pos: 0 };
    const value = _decodeCborItem(s);
    if (s.pos !== s.buf.length) throw new Error('cbor: trailing bytes');
    return value;
  }

  // ── COSE_Sign1 (Epic 70.2 · RFC 9052) ──────────────────────────────────────
  //
  // Algorithm: Ed25519, COSE algorithm ID -19 (RFC 9864; the polymorphic EdDSA
  // id -8 is deprecated and rejected). Payload: RFC 8785 canonical JSON bytes of
  // the plan. Structure: COSE_Sign1 = tag 18 of
  //   [ protected: bstr .cbor { 1: -19 },
  //     unprotected: { 4: kid-bytes },
  //     payload: bstr,
  //     signature: bstr ]
  // Sig_structure = ["Signature1", protected, external_aad = h'', payload].
  // Mirrors typescript/ltx/src/cose.ts.

  const COSE_SIGN1_TAG = 18;
  const COSE_ALG_ED25519 = -19;

  function _coseSigStructureBytes(protectedBytes, payload) {
    return encodeCbor(['Signature1', protectedBytes, Buffer.alloc(0), payload]);
  }

  /**
   * Sign a plan as a real CBOR COSE_Sign1 (tag 18). The kid (header label 4)
   * is the signer's NIK nodeId — base64url of the first 16 bytes of
   * SHA-256(raw public key), matching generateNIK()/signPlan().
   *
   * @param {object} plan           LTX plan config
   * @param {string} privateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
   * @returns {{ plan: object, coseSign1CborB64: string }}
   */
  function signPlanCose(plan, privateKeyB64) {
    const crypto = _getCrypto();
    const rawSeed = Buffer.from(privateKeyB64, 'base64url');
    const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
    const privKey = crypto.createPrivateKey({
      key: Buffer.concat([pkcs8Header, rawSeed]), format: 'der', type: 'pkcs8',
    });

    const protectedBytes = encodeCbor(new Map([[1, COSE_ALG_ED25519]]));
    const payload = Buffer.from(canonicalJSON(plan), 'utf8');
    const signature = crypto.sign(null, _coseSigStructureBytes(protectedBytes, payload), privKey);

    const pubKeyObj = crypto.createPublicKey(privKey);
    const rawPub = pubKeyObj.export({ type: 'spki', format: 'der' }).slice(-32);
    const kid = crypto.createHash('sha256').update(rawPub).digest().slice(0, 16);

    const coseSign1 = new CborTag(COSE_SIGN1_TAG, [
      protectedBytes,
      new Map([[4, kid]]),
      payload,
      signature,
    ]);
    return { plan, coseSign1CborB64: encodeCbor(coseSign1).toString('base64url') };
  }

  /**
   * Verify a CBOR COSE_Sign1 plan envelope against the key cache.
   * Rejects non-Ed25519 algorithms (including the deprecated -8) and payloads
   * that do not match the accompanying plan object.
   *
   * @param {{ plan: object, coseSign1CborB64: string }} envelope  Output from signPlanCose()
   * @param {Map<string,object>|object} keyCache                  nodeId → NIK
   * @returns {{ valid: boolean, reason?: string }}
   */
  function verifyPlanCose(envelope, keyCache) {
    if (!envelope || typeof envelope.coseSign1CborB64 !== 'string') {
      return { valid: false, reason: 'missing_cose_sign1' };
    }

    let decoded;
    try {
      decoded = decodeCbor(Buffer.from(envelope.coseSign1CborB64, 'base64url'));
    } catch (_) {
      return { valid: false, reason: 'cbor_decode_failed' };
    }
    if (!(decoded instanceof CborTag) || decoded.tag !== COSE_SIGN1_TAG) {
      return { valid: false, reason: 'not_cose_sign1' };
    }
    const arr = decoded.value;
    if (!Array.isArray(arr) || arr.length !== 4) {
      return { valid: false, reason: 'malformed_cose_sign1' };
    }
    const [protectedBytes, unprotected, payload, signature] = arr;

    let protectedMap;
    try {
      protectedMap = decodeCbor(protectedBytes);
    } catch (_) {
      return { valid: false, reason: 'protected_decode_failed' };
    }
    if (!(protectedMap instanceof Map) || protectedMap.get(1) !== COSE_ALG_ED25519) {
      return { valid: false, reason: 'unsupported_alg' };
    }

    const kidRaw = unprotected instanceof Map ? unprotected.get(4) : undefined;
    const kid = kidRaw instanceof Uint8Array
      ? Buffer.from(kidRaw).toString('base64url')
      : typeof kidRaw === 'string' ? kidRaw : '';
    if (!kid) return { valid: false, reason: 'missing_kid' };

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

    const crypto = _getCrypto();
    const rawPub = Buffer.from(signerNIK.publicKey, 'base64url');
    const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
    const pubKey = crypto.createPublicKey({
      key: Buffer.concat([spkiHeader, rawPub]), format: 'der', type: 'spki',
    });
    const ok = crypto.verify(
      null,
      _coseSigStructureBytes(Buffer.from(protectedBytes), Buffer.from(payload)),
      pubKey,
      Buffer.from(signature),
    );
    if (!ok) return { valid: false, reason: 'signature_invalid' };

    if (envelope.plan !== undefined &&
        Buffer.from(payload).toString('utf8') !== canonicalJSON(envelope.plan)) {
      return { valid: false, reason: 'payload_mismatch' };
    }
    return { valid: true };
  }

  /**
   * Verify either envelope form: the CBOR COSE_Sign1 (coseSign1CborB64) or the
   * frozen TRANSITIONAL JSON envelope (coseSign1) — LTX-SECURITY.md §7.5.
   *
   * @param {object} envelope                     Output from signPlanCose() or signPlan()
   * @param {Map<string,object>|object} keyCache  nodeId → NIK
   * @returns {{ valid: boolean, reason?: string }}
   */
  function verifyPlanAny(envelope, keyCache) {
    if (envelope.coseSign1CborB64 !== undefined) {
      return verifyPlanCose(envelope, keyCache);
    }
    if (envelope.coseSign1 !== undefined) {
      return verifyPlan(envelope, keyCache);
    }
    return { valid: false, reason: 'unknown_envelope' };
  }

  // ── Conference mode (Epic 71) ──────────────────────────────────────────────

  /**
   * Build a conference segment template over the presenting nodes
   * (Story 71.2 · LTX-SPECIFICATION.md §14.2).
   * Presenting nodes = every node that is not an OBSERVER.
   * Rotation invariant ('rotate'): across N cycles, each node opens exactly once
   * — cycle c opens with presenting-node index c mod N (§14.4).
   *
   * @param {object[]} nodes                LTX node list
   * @param {object}   [options]
   * @param {number}   [options.cycles=1]   Number of full cycles (each node presents once per cycle)
   * @param {number}   [options.blockQ=3]   Quanta per presenting Block
   * @param {number}   [options.confirmQ=2] Quanta for the PLAN_CONFIRM opener
   * @param {number}   [options.mergeQ=2]   Quanta for the closing MERGE (0 to omit)
   * @param {number}   [options.bufferQ=1]  Quanta for the trailing BUFFER (0 to omit)
   * @param {number}   [options.caucusQ=0]  Insert a CAUCUS of this many quanta between cycles
   * @param {string}   [options.fairness='rotate']  'rotate' or 'fixed' (plan order)
   * @param {object}   [options.labels]     Optional label per node id, e.g. { N1: 'Mars Field Report' }
   * @returns {Array<{type:string, q:number, speaker?:string, label?:string}>}
   */
  function buildConferenceAgenda(nodes, options) {
    options = options || {};
    const presenting = nodes.filter(n => n.role !== 'OBSERVER');
    if (presenting.length === 0) throw new Error('buildConferenceAgenda: no presenting nodes');
    const cycles   = options.cycles   !== undefined ? options.cycles   : 1;
    const blockQ   = options.blockQ   !== undefined ? options.blockQ   : 3;
    const confirmQ = options.confirmQ !== undefined ? options.confirmQ : 2;
    const mergeQ   = options.mergeQ   !== undefined ? options.mergeQ   : 2;
    const bufferQ  = options.bufferQ  !== undefined ? options.bufferQ  : 1;
    const caucusQ  = options.caucusQ  !== undefined ? options.caucusQ  : 0;
    const fairness = options.fairness !== undefined ? options.fairness : 'rotate';
    const labels   = options.labels   || {};

    const segments = [];
    if (confirmQ > 0) segments.push({ type: 'PLAN_CONFIRM', q: confirmQ });

    const n = presenting.length;
    for (let c = 0; c < cycles; c++) {
      if (c > 0 && caucusQ > 0) segments.push({ type: 'CAUCUS', q: caucusQ });
      const offset = fairness === 'rotate' ? c % n : 0;
      for (let i = 0; i < n; i++) {
        const node = presenting[(offset + i) % n];
        segments.push({
          type: 'TX',
          q: blockQ,
          speaker: node.id,
          ...(labels[node.id] ? { label: labels[node.id] } : {}),
        });
      }
    }

    if (mergeQ > 0) segments.push({ type: 'MERGE', q: mergeQ });
    if (bufferQ > 0) segments.push({ type: 'BUFFER', q: bufferQ });
    return segments;
  }

  /**
   * Score per-node slot desirability over a plan's attributed segments (§14.4).
   * Desirability of attributed slot i (of k) = (k - i) / k, so the opening slot
   * scores 1 and the final slot 1/k. Organisers use the report to spot
   * imbalances when deviating from fair rotation.
   *
   * @param {object} cfg  LTX plan config (v1, v2 or v3)
   * @returns {Array<{nodeId:string, slots:number[], openings:number, score:number}>}
   *   sorted by score desc, then nodeId asc
   */
  function primeTimeReport(cfg) {
    const c = upgradeConfig(cfg);
    const attributed = c.segments.filter(s => s.speaker);
    const k = attributed.length;
    const byNode = new Map();
    attributed.forEach((seg, i) => {
      const rec = byNode.get(seg.speaker) || { slots: [], scoreSum: 0 };
      rec.slots.push(i);
      rec.scoreSum += (k - i) / k;
      byNode.set(seg.speaker, rec);
    });
    const n = Math.max(1, byNode.size);
    return [...byNode.entries()]
      .map(([nodeId, rec]) => ({
        nodeId,
        slots: rec.slots,
        // An "opening" is the first slot of each cycle: attributed index ≡ 0 (mod N).
        openings: rec.slots.filter(s => s % n === 0).length,
        score: rec.slots.length ? rec.scoreSum / rec.slots.length : 0,
      }))
      .sort((a, b) => b.score - a.score || (a.nodeId < b.nodeId ? -1 : 1));
  }

  // ── Public exports ─────────────────────────────────────────────────────────

  return {
    VERSION,
    SEG_TYPES,
    DEFAULT_QUANTUM,
    DEFAULT_SEGMENTS,
    DELAY_VIOLATION_WARN_S,
    DELAY_VIOLATION_DEGRADE_S,
    LOCK_TIMEOUT_FACTOR,
    // Config
    createPlan,
    upgradeConfig,
    upgradePlanToV3,
    // Computation
    computeSegments,
    computeSegmentsMulti,
    buildDelayMatrix,
    pairDelay,
    computeSegmentsFor,
    totalMin,
    makePlanId,
    // URL
    encodeHash,
    decodeHash,
    buildNodeUrls,
    // ICS
    generateICS,
    // Conference mode (Epic 71)
    buildConferenceAgenda,
    primeTimeReport,
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
    // Global freshness scope (Story 70.4)
    createGlobalSequenceTracker,
    checkIssuedAt,
    ISSUED_AT_MAX_AGE_DAYS,
    // Merkle Audit Log
    createMerkleLog,
    verifyTreeHead,
    // BPSec BIB
    addBIB,
    verifyBIB,
    generateBIBKey,
    // LTX-native Ed25519 BIB (Story 70.3)
    addBIBEd25519,
    verifyBIBEd25519,
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
    // Session State Machine (Epic 68)
    createSession,
    transition,
    lockTimeoutMs,
    // Plan Amendments (Epic 68.3)
    planHash,
    createAmendment,
    verifyAmendmentChain,
    insertBufferViaAmendment,
    // Registers (Epic 69.1)
    createRegisterEntry,
    verifyRegisterEntry,
    compareEntries,
    orderEntries,
    reduceQuestions,
    reduceActions,
    emitQuestionSeeds,
    // Merge + partition recovery (Epic 69.2)
    mergeLogs,
    entriesRoot,
    runMergeSegment,
    recoverPartition,
    // CBOR (Epic 70.1)
    CborTag,
    encodeCbor,
    decodeCbor,
    // COSE_Sign1 (Epic 70.2)
    COSE_SIGN1_TAG,
    COSE_ALG_ED25519,
    signPlanCose,
    verifyPlanCose,
    verifyPlanAny,
  };
}));
