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

/**
 * Node names for the (c) prefix input (issue #37): the planId HOSTSTR and
 * NODESTR need JS whitespace removal (U+3000, U+00A0), the full Unicode
 * upper-case mapping of toUpperCase (ß to SS, ﬁ/ﬂ to FI/FL, ΐ to three code
 * points, σ and ς to Σ, dotless ı, Cyrillic, astral Deseret letters) and
 * UTF-16 slicing. No cut splits a surrogate pair, so the id is valid UTF-8
 * in every port (spec/golden/plan-id-prefixes.json covers the split cases).
 */
const PREFIX_NODES = [
  { id: 'N0', name: 'Größe\u3000σς',  role: 'HOST',        delay: 0,   location: 'earth' },
  { id: 'N1', name: 'ﬁx ﬂy',          role: 'PARTICIPANT', delay: 840, location: 'mars'  },
  { id: 'N2', name: 'ΐλη',            role: 'PARTICIPANT', delay: 2,   location: 'moon'  },
  { id: 'N3', name: '𐐨𐐩x',           role: 'PARTICIPANT', delay: 900, location: 'mars'  },
  { id: 'N4', name: 'ıi\u00a0İzmir', role: 'PARTICIPANT', delay: 5,   location: 'earth' },
];

module.exports = { REP, V3_EXTRAS, PREFIX_NODES };
