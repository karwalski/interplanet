/**
 * ltx-topics.js: EXPERIMENTAL LTX topics extension ("topics/0")
 * Story IP-T3 (#16). Design: docs/LTX-TOPICS-RFC.md (Draft).
 *
 * EXPERIMENTAL. NOT FOR PRODUCTION. Not published in the interplanet-ltx
 * package. Pending the patent record review (IP-T1, #14).
 *
 * Scope boundaries (RFC §12), enforced by design:
 *   - no input gating: nothing here decides whether a topic can be read,
 *     drafted or submitted to; closing a topic is a label, never a lock;
 *   - no cycling, rotation or timer-driven focus of any kind;
 *   - no interval derived from light-time, pair delay or ephemeris
 *     (this module never reads delay values);
 *   - topics never populate the reserved streams[] field;
 *   - v2 plans are never modified and never upgraded here.
 *
 * Built on the ltx-sdk.js register primitives (createRegisterEntry,
 * verifyRegisterEntry, orderEntries, compareEntries, canonicalJSON,
 * hedgedSign / hedgedVerify). No other dependencies.
 */

(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = factory(require('./ltx-sdk'));
  } else if (typeof window !== 'undefined') {
    window.LtxTopics = factory(window.LtxSdk);
  }
}(typeof globalThis !== 'undefined' ? globalThis : this, function (ltx) {
  'use strict';

  const EXPERIMENTAL = true;
  const TOPICS_CAP = 'topics/0';
  const BATCH_TYPE = 'topic_batch';
  const BATCH_VERSION = 0;

  const TOPIC_ENTRY_PREFIX = {
    topic: 'TOP', topic_update: 'TOP', contribution: 'CTB',
  };
  const TOPIC_ENTRY_TYPES = Object.keys(TOPIC_ENTRY_PREFIX);
  const TOPIC_STATUSES = ['open', 'closed'];
  const TOPIC_ID_RE = /^[A-Za-z0-9._-]{1,64}$/;
  const MAX_BODY_BYTES = 16 * 1024;

  // ── Validation helpers ────────────────────────────────────────────────────

  function _isNonEmptyString(s) { return typeof s === 'string' && s.length > 0; }

  function _utf8Bytes(s) {
    return typeof Buffer !== 'undefined'
      ? Buffer.byteLength(s, 'utf8')
      : new TextEncoder().encode(s).length;
  }

  function _checkTopicId(topicId) {
    if (typeof topicId !== 'string' || !TOPIC_ID_RE.test(topicId)) {
      throw new Error(`ltx-topics: invalid topicId ${JSON.stringify(topicId)}`);
    }
  }

  function _checkParticipants(p) {
    if (p === undefined) return;
    if (!Array.isArray(p) || !p.every(_isNonEmptyString)) {
      throw new Error('ltx-topics: participants must be an array of node ids');
    }
  }

  function _entryOpts(type, opts) {
    if (!opts || !_isNonEmptyString(opts.nodeId) || !Number.isInteger(opts.seq)) {
      throw new Error('ltx-topics: opts.nodeId and integer opts.seq are required');
    }
    return Object.assign({}, opts, {
      entryId: opts.entryId || `${TOPIC_ENTRY_PREFIX[type]}-${opts.nodeId}-${opts.seq}`,
    });
  }

  // ── Entry builders (RFC §5) ───────────────────────────────────────────────

  /**
   * Create a signed `topic` register entry.
   * @param {{topicId:string, title:string, participants?:string[]}} topic
   * @param {object} opts  { sessionId, nodeId, seq, timestamp, privateKeyB64, entryId? }
   */
  function createTopic(topic, opts) {
    _checkTopicId(topic.topicId);
    if (!_isNonEmptyString(topic.title)) throw new Error('ltx-topics: title required');
    _checkParticipants(topic.participants);
    const content = { topicId: topic.topicId, title: topic.title };
    if (topic.participants !== undefined) content.participants = topic.participants.slice();
    return ltx.createRegisterEntry('topic', content, _entryOpts('topic', opts));
  }

  /**
   * Create a signed `topic_update` entry. version >= 2 (creation is version 1).
   * @param {{topicId:string, version:number, status?:string, title?:string, participants?:string[]}} update
   * @param {object} opts
   */
  function updateTopic(update, opts) {
    _checkTopicId(update.topicId);
    if (!Number.isInteger(update.version) || update.version < 2) {
      throw new Error('ltx-topics: topic_update version must be an integer >= 2');
    }
    if (update.status !== undefined && !TOPIC_STATUSES.includes(update.status)) {
      throw new Error('ltx-topics: status must be "open" or "closed"');
    }
    _checkParticipants(update.participants);
    const content = { topicId: update.topicId, version: update.version };
    if (update.status !== undefined) content.status = update.status;
    if (update.title !== undefined) content.title = String(update.title);
    if (update.participants !== undefined) content.participants = update.participants.slice();
    return ltx.createRegisterEntry('topic_update', content, _entryOpts('topic_update', opts));
  }

  /**
   * Create a signed `contribution` entry. The author is opts.nodeId.
   * No status check is made: a contribution to a closed or unknown topic is
   * always accepted (RFC §6.5, §6.6).
   * @param {{topicId:string, body:string, replyTo?:string, contributionId?:string}} c
   * @param {object} opts
   */
  function createContribution(c, opts) {
    _checkTopicId(c.topicId);
    if (typeof c.body !== 'string' || !c.body.length) throw new Error('ltx-topics: body required');
    if (_utf8Bytes(c.body) > MAX_BODY_BYTES) throw new Error('ltx-topics: body exceeds 16 KiB');
    const o = _entryOpts('contribution', opts);
    const content = {
      topicId: c.topicId,
      contributionId: c.contributionId || o.entryId,
      body: c.body,
    };
    if (c.replyTo !== undefined) content.replyTo = String(c.replyTo);
    return ltx.createRegisterEntry('contribution', content, o);
  }

  // ── Batch envelope (RFC §5.4, candidate C) ────────────────────────────────

  function _batchBody(batch) {
    const body = Object.assign({}, batch);
    delete body.batchSig;
    return body;
  }

  /**
   * Wrap a node's own signed entries in a signed batch transport envelope.
   * The batch carries no ordering, timing or release semantics.
   * @param {object[]} entries  Signed entries, all with nodeId === opts.nodeId
   * @param {object} opts       { sessionId, nodeId, createdAt, privateKeyB64, batchId? }
   */
  function createBatch(entries, opts) {
    if (!Array.isArray(entries) || !entries.length) throw new Error('ltx-topics: empty batch');
    for (const e of entries) {
      if (e.nodeId !== opts.nodeId) throw new Error('ltx-topics: a batch may only carry the sender\'s own entries');
    }
    const seqs = entries.map(e => e.seq);
    const batch = {
      type: BATCH_TYPE,
      v: BATCH_VERSION,
      batchId: opts.batchId || `BAT-${opts.nodeId}-${Math.min(...seqs)}-${Math.max(...seqs)}`,
      sessionId: opts.sessionId,
      nodeId: opts.nodeId,
      createdAt: opts.createdAt,
      entries: entries.slice(),
    };
    const data = Buffer.from(ltx.canonicalJSON(_batchBody(batch)), 'utf8');
    batch.batchSig = ltx.hedgedSign(data, opts.privateKeyB64);
    return batch;
  }

  function _lookup(keyCache, nodeId) {
    if (!keyCache) return undefined;
    return keyCache instanceof Map ? keyCache.get(nodeId) : keyCache[nodeId];
  }

  /**
   * Verify a batch. Entries are the unit of trust: each is verified on its own
   * and reported in `entries` (valid) or `rejected`, whatever the batch
   * signature result.
   * @returns {{valid:boolean, reason?:string, entries:object[], rejected:object[]}}
   */
  function verifyBatch(batch, keyCache) {
    const entries = [], rejected = [];
    for (const e of (batch && Array.isArray(batch.entries) ? batch.entries : [])) {
      if (e.nodeId !== batch.nodeId) { rejected.push({ entry: e, reason: 'foreign_entry_in_batch' }); continue; }
      const v = ltx.verifyRegisterEntry(e, keyCache);
      if (v.valid) entries.push(e);
      else rejected.push({ entry: e, reason: v.reason || 'invalid' });
    }
    let result = { valid: true };
    if (!batch || batch.type !== BATCH_TYPE) result = { valid: false, reason: 'not_a_batch' };
    else if (!batch.batchSig) result = { valid: false, reason: 'missing_batch_sig' };
    else {
      const nik = _lookup(keyCache, batch.nodeId);
      if (!nik) result = { valid: false, reason: 'key_not_in_cache' };
      else {
        const data = Buffer.from(ltx.canonicalJSON(_batchBody(batch)), 'utf8');
        const ok = ltx.hedgedVerify(data, batch.batchSig.signature, batch.batchSig.nonceSalt, nik.publicKey);
        if (!ok) result = { valid: false, reason: 'batch_signature_invalid' };
      }
    }
    return Object.assign(result, { entries, rejected });
  }

  // ── Merge (RFC §6.1, §6.2) ────────────────────────────────────────────────

  /**
   * Deterministic merge of any number of logs. Each log is an array whose items
   * are signed entries or batch envelopes. Steps (spec §8.2):
   *   verify (when keyCache given) → dedupe by (nodeId, seq) → total order.
   * Identical duplicates collapse. Different entries sharing (nodeId, seq) are
   * equivocations: the one with the lowest canonical JSON is kept, so the
   * result never depends on arrival order. The late-entry path deliberately
   * does NOT use the transport replay filter (recordSeq); see RFC §6.2.
   *
   * @param {Array<Array<object>>} logs
   * @param {Map|object} [keyCache]  Omit only for unsigned local simulation.
   * @returns {{entries:object[], rejected:object[], equivocations:object[], invalidBatches:object[]}}
   */
  function mergeTopicLogs(logs, keyCache) {
    const rejected = [], invalidBatches = [], candidates = [];
    for (const log of logs) {
      for (const item of (log || [])) {
        if (item && item.type === BATCH_TYPE) {
          if (keyCache) {
            const vb = verifyBatch(item, keyCache);
            if (!vb.valid) invalidBatches.push({ batchId: item.batchId, reason: vb.reason });
            candidates.push(...vb.entries);
            rejected.push(...vb.rejected);
          } else {
            candidates.push(...(item.entries || []));
          }
          continue;
        }
        if (keyCache) {
          const v = ltx.verifyRegisterEntry(item, keyCache);
          if (!v.valid) { rejected.push({ entry: item, reason: v.reason || 'invalid' }); continue; }
        }
        candidates.push(item);
      }
    }

    const byKey = new Map(), equivocations = [];
    for (const e of candidates) {
      const key = `${e.nodeId} ${e.seq}`;
      const cur = byKey.get(key);
      if (!cur) { byKey.set(key, { entry: e, json: ltx.canonicalJSON(e) }); continue; }
      const json = ltx.canonicalJSON(e);
      if (json === cur.json) continue;
      const keep = json < cur.json ? { entry: e, json } : cur;
      const drop = keep === cur ? e : cur.entry;
      equivocations.push({ nodeId: e.nodeId, seq: e.seq, kept: keep.entry.entryId, dropped: drop });
      byKey.set(key, keep);
    }
    equivocations.sort((a, b) => (a.nodeId < b.nodeId ? -1 : a.nodeId > b.nodeId ? 1 : a.seq - b.seq));

    // orderEntries re-applies the (nodeId, seq) dedupe (a no-op here) and
    // sorts into the shared (timestamp, nodeId, seq) total order.
    return {
      entries: ltx.orderEntries([...byKey.values()].map(x => x.entry)),
      rejected, equivocations, invalidBatches,
    };
  }

  // ── Reduce (RFC §6, §7) ───────────────────────────────────────────────────

  function _conflictWins(incoming, current) {
    if (incoming.version !== current.version) return incoming.version > current.version;
    return incoming.editor < current.editor;
  }

  /**
   * Pure reduction of topic state from a set of entries. Non-topic entry types
   * are ignored. Result depends only on the set, not on input order.
   * @returns {{byId:object, contributions:object, orphans:string[], superseded:string[], invalid:string[]}}
   */
  function reduceTopics(entries) {
    const ordered = ltx.orderEntries(entries.filter(e => e && TOPIC_ENTRY_TYPES.includes(e.type)));
    const byId = {}, winners = {}, superseded = [], invalid = [], orphans = [];
    const closedBy = {};

    // Pass 1: creations (first in total order wins).
    for (const e of ordered) {
      if (e.type !== 'topic') continue;
      const c = e.content || {};
      if (typeof c.topicId !== 'string' || !TOPIC_ID_RE.test(c.topicId) || !_isNonEmptyString(c.title)) {
        invalid.push(e.entryId); continue;
      }
      if (byId[c.topicId]) { superseded.push(e.entryId); continue; }
      winners[c.topicId] = { version: 1, editor: e.nodeId, entryId: e.entryId };
      byId[c.topicId] = Object.assign(
        { topicId: c.topicId, title: c.title },
        Array.isArray(c.participants) ? { participants: c.participants.slice() } : {},
        { status: 'open', version: 1, creator: e.nodeId, editor: e.nodeId, contributionCount: 0 },
      );
    }

    // Pass 2: updates, §8.2 conflict rule (highest version, then lowest editor).
    for (const e of ordered) {
      if (e.type !== 'topic_update') continue;
      const c = e.content || {};
      const version = Number(c.version);
      if (typeof c.topicId !== 'string' || !Number.isInteger(version) || version < 2 ||
          (c.status !== undefined && !TOPIC_STATUSES.includes(c.status))) {
        invalid.push(e.entryId); continue;
      }
      const t = byId[c.topicId];
      if (!t) { orphans.push(e.entryId); continue; }
      const incoming = { version, editor: e.nodeId, entryId: e.entryId };
      const current = winners[c.topicId];
      if (!_conflictWins(incoming, current)) { superseded.push(e.entryId); continue; }
      if (current.version > 1) superseded.push(current.entryId);
      winners[c.topicId] = incoming;
      byId[c.topicId] = Object.assign({}, t,
        c.status !== undefined ? { status: c.status } : {},
        c.title !== undefined ? { title: String(c.title) } : {},
        Array.isArray(c.participants) ? { participants: c.participants.slice() } : {},
        { version, editor: e.nodeId },
      );
      if (c.status !== undefined) closedBy[c.topicId] = c.status === 'closed' ? e : null;
    }

    // Pass 3: contributions in total order. A parent must precede its reply
    // in the same topic, which rules out cycles (RFC §6.4).
    const contributions = {};
    for (const e of ordered) {
      if (e.type !== 'contribution') continue;
      const c = e.content || {};
      const cid = typeof c.contributionId === 'string' && c.contributionId ? c.contributionId : e.entryId;
      if (typeof c.topicId !== 'string' || typeof c.body !== 'string') { invalid.push(e.entryId); continue; }
      if (contributions[cid]) { superseded.push(e.entryId); continue; }
      const t = byId[c.topicId];
      if (!t) { orphans.push(e.entryId); continue; }
      const closer = closedBy[c.topicId];
      const rec = {
        contributionId: cid,
        topicId: c.topicId,
        body: c.body,
        author: e.nodeId,
        seq: e.seq,
        timestamp: e.timestamp,
        entryId: e.entryId,
        afterClose: !!(t.status === 'closed' && closer && ltx.compareEntries(e, closer) > 0),
      };
      if (c.replyTo !== undefined) {
        rec.replyTo = String(c.replyTo);
        const parent = contributions[rec.replyTo];
        if (!parent || parent.topicId !== c.topicId) rec.parentUnresolved = true;
      }
      contributions[cid] = rec;
      byId[c.topicId] = Object.assign({}, t, { contributionCount: t.contributionCount + 1 });
    }

    return { byId, contributions, orphans, superseded, invalid };
  }

  /**
   * Derive the reply forest for one topic (RFC §7.4). Accepts reduced state
   * (from reduceTopics) or a raw entry array. Roots and siblings are in the
   * (timestamp, nodeId, seq) total order.
   * @returns {object[]} roots, each { ...contribution, replies: [...] }
   */
  function buildThreads(stateOrEntries, topicId) {
    const state = Array.isArray(stateOrEntries) ? reduceTopics(stateOrEntries) : stateOrEntries;
    const list = Object.values(state.contributions)
      .filter(c => c.topicId === topicId)
      .sort((a, b) => ltx.compareEntries(
        { timestamp: a.timestamp, nodeId: a.author, seq: a.seq },
        { timestamp: b.timestamp, nodeId: b.author, seq: b.seq }));
    const nodes = {}, roots = [];
    for (const c of list) nodes[c.contributionId] = Object.assign({}, c, { replies: [] });
    for (const c of list) {
      const n = nodes[c.contributionId];
      if (c.replyTo !== undefined && !c.parentUnresolved) nodes[c.replyTo].replies.push(n);
      else roots.push(n);
    }
    return roots;
  }

  // ── Plan helpers (RFC §3, §4) ─────────────────────────────────────────────

  function hasTopicsCapability(plan) {
    return !!(plan && plan.v >= 3 && Array.isArray(plan.caps) && plan.caps.includes(TOPICS_CAP));
  }

  function _assertStreamsReserved(plan) {
    if (plan.streams !== undefined && !(Array.isArray(plan.streams) && plan.streams.length === 0)) {
      throw new Error('ltx-topics: streams[] is reserved (spec §3.5) and must be absent or empty');
    }
  }

  /**
   * Return a NEW v3 plan carrying topics[], caps ["topics/0"] and optional
   * advisory topicRefs[] per segment index. Refuses v1/v2 plans: upgrading is
   * an explicit user action (upgradePlanToV3), never done here. streams[] is
   * copied through untouched. The input is not mutated.
   *
   * @param {object} plan              v3 plan
   * @param {object[]} topics          [{ id, title, participants?, status? }]
   * @param {object} [topicRefs]       { [segmentIndex]: string[] }
   */
  function attachTopicsToPlan(plan, topics, topicRefs) {
    if (!plan || plan.v !== 3) {
      throw new Error('ltx-topics: topics require an explicit v3 plan (call upgradePlanToV3 first); v2 plans are never modified');
    }
    _assertStreamsReserved(plan);
    const seen = new Set();
    const cleanTopics = (topics || []).map(t => {
      _checkTopicId(t.id);
      if (seen.has(t.id)) throw new Error(`ltx-topics: duplicate topic id ${t.id}`);
      seen.add(t.id);
      if (!_isNonEmptyString(t.title)) throw new Error('ltx-topics: topic title required');
      _checkParticipants(t.participants);
      if (t.status !== undefined && !TOPIC_STATUSES.includes(t.status)) throw new Error('ltx-topics: bad status');
      const out = { id: t.id, title: t.title };
      if (t.participants !== undefined) out.participants = t.participants.slice();
      if (t.status !== undefined) out.status = t.status;
      return out;
    });
    const refs = topicRefs || {};
    const segments = plan.segments.map((s, i) => {
      if (!refs[i]) return s;
      for (const id of refs[i]) {
        if (!seen.has(id)) throw new Error(`ltx-topics: topicRefs names unknown topic ${id}`);
      }
      return Object.assign({}, s, { topicRefs: refs[i].slice() });
    });
    const caps = Array.from(new Set((plan.caps || []).concat(TOPICS_CAP))).sort();
    return Object.assign({}, plan, { caps, topics: cleanTopics, segments });
  }

  /**
   * Display view for a node WITHOUT the capability (RFC §4.3.3): drops
   * topics[], caps and topicRefs from a copy. The returned object is for
   * rendering only; planIds, signatures and relaying MUST use the original.
   */
  function renderPlanWithoutTopics(plan) {
    const view = Object.assign({}, plan);
    delete view.topics;
    if (Array.isArray(view.caps)) {
      const rest = view.caps.filter(c => c !== TOPICS_CAP);
      if (rest.length) view.caps = rest; else delete view.caps;
    }
    if (Array.isArray(plan.segments)) {
      view.segments = plan.segments.map(s => {
        if (!s || s.topicRefs === undefined) return s;
        const copy = Object.assign({}, s);
        delete copy.topicRefs;
        return copy;
      });
    }
    return view;
  }

  /**
   * Advisory recommended-focus topic ids for a segment (RFC §4.2). Returns ids
   * only. Callers MUST NOT use this to lock, hide or switch anything.
   */
  function recommendedTopics(plan, segmentIndex) {
    if (!hasTopicsCapability(plan)) return [];
    const seg = plan.segments && plan.segments[segmentIndex];
    const known = new Set((plan.topics || []).map(t => t.id));
    return seg && Array.isArray(seg.topicRefs) ? seg.topicRefs.filter(id => known.has(id)) : [];
  }

  return {
    EXPERIMENTAL,
    TOPICS_CAP,
    BATCH_TYPE,
    TOPIC_ENTRY_PREFIX,
    TOPIC_STATUSES,
    // Entries
    createTopic,
    updateTopic,
    createContribution,
    // Batches
    createBatch,
    verifyBatch,
    // Merge + reduce
    mergeTopicLogs,
    reduceTopics,
    buildThreads,
    // Plan helpers
    hasTopicsCapability,
    attachTopicsToPlan,
    renderPlanWithoutTopics,
    recommendedTopics,
  };
}));
