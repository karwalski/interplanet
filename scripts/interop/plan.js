'use strict';
/**
 * The representative plan every interop driver builds with its port's typed
 * API. Non-ASCII title and labels (including astral characters, which are
 * surrogate pairs in UTF-16), three nodes (one name with punctuation inside
 * the first four characters, which the planId NODESTR must keep: 'L-1G'),
 * and segments with speaker/label.
 * Drivers hard-code these values; keep them in sync.
 */
const REP = {
  title: 'Réunion Mars 🚀',
  start: '2026-03-15T14:00:00.000Z',
  quantum: 3,
  mode: 'LTX-ASYNC',
  nodes: [
    { id: 'N0', name: 'Earth HQ',     role: 'HOST',        delay: 0,   location: 'earth' },
    { id: 'N1', name: 'Mars Hab-01',  role: 'PARTICIPANT', delay: 840, location: 'mars'  },
    { id: 'N2', name: 'L-1 Gateway',  role: 'PARTICIPANT', delay: 2,   location: 'moon'  },
  ],
  segments: [
    { type: 'PLAN_CONFIRM', q: 2 },
    { type: 'TX', q: 3, speaker: 'N0', label: 'Ouverture: état de la mission' },
    { type: 'RX', q: 3 },
    { type: 'TX', q: 2, speaker: 'N1', label: 'Réponse 🔴' },
    { type: 'BUFFER', q: 1 },
  ],
};

/** Extra v3 fields for the JS upgradePlanToV3 input to (c). */
const V3_EXTRAS = { delays: { 'N1|N2': 842 } };

module.exports = { REP, V3_EXTRAS };
