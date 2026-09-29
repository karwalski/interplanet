'use strict';

/**
 * ltx-protocol-templates.js — Structured message templates for LTX registers
 * Story IP-R1 (Refs #18) — protocol templates and training mode
 *
 * Templates for four message kinds (question, action, status update,
 * acknowledgement). Each template:
 *   - declares its fields and which of them are required,
 *   - renders to plain text with render(templateId, values),
 *   - is checked by validate(templateId, values), which flags missing
 *     structural parts (for example no context restatement),
 *   - carries a training-mode explanation string,
 *   - maps to an LTX register entry (question, action, action_update or
 *     question_response) whose content is accepted by the SDK reducers
 *     reduceQuestions / reduceActions.
 *
 * The structure is informed by the published approach of Fischer & Mosier
 * (context restatement, numbered questions and items, explicit
 * acknowledgement or readback, an explicit request for a response with an
 * expected reply time). It does not reproduce their protocols and implies no
 * endorsement. See docs/LTX-PROTOCOL-TEMPLATES.md for citations.
 *
 * No dependencies beyond ltx-sdk.js (only needed for createEntry()).
 */

const TEMPLATE_VERSION = 1;

const ACTION_STATUSES = ['PROPOSED', 'ACCEPTED', 'REJECTED', 'DONE'];
const URGENCIES = ['routine', 'priority', 'urgent'];

// ── Template definitions ─────────────────────────────────────────────────────
//
// Field kinds: 'text' (non-empty string), 'list' (non-empty array of
// non-empty strings), 'time' (ISO 8601 UTC string), 'enum' (one of values),
// 'bool'. The `part` tag names the structural protocol element a field
// supplies, so validate() can report which element is missing.

const TEMPLATES = {
  question: {
    id: 'question',
    title: 'Question',
    entryType: 'question',
    fields: [
      { name: 'context',    kind: 'text', required: true,  part: 'context_restatement',
        label: 'Context', help: 'Restate the situation the question is about, so it can be understood without earlier messages.' },
      { name: 'questions',  kind: 'list', required: true,  part: 'numbered_items',
        label: 'Questions', help: 'One question per entry. They are numbered so the reply can answer each by number.' },
      { name: 'replyBy',    kind: 'time', required: true,  part: 'reply_request',
        label: 'Reply needed by (UTC)', help: 'When you need the answer. Allow for the round-trip signal delay.' },
      { name: 'urgency',    kind: 'enum', required: false, values: URGENCIES,
        label: 'Urgency' },
      { name: 'intendedWindow', kind: 'text', required: false,
        label: 'Intended window', help: 'Optional LTX segment or window in which the answer is expected.' },
      { name: 'attempted',  kind: 'text', required: false,
        label: 'Already tried', help: 'What has already been done or ruled out, to avoid a wasted round trip.' },
    ],
    training:
      'Question template. Under signal delay the reader cannot ask what you meant, ' +
      'and a clarifying round trip can cost the whole reply window. Start by restating ' +
      'the context (what is happening, what you observed, what you already tried) so the ' +
      'message stands on its own. Number each question so the reply can answer them one ' +
      'by one and nothing is silently skipped. Finish by saying explicitly that you need ' +
      'a reply and by when, allowing for the round-trip delay.',
  },

  action: {
    id: 'action',
    title: 'Action request',
    entryType: 'action',
    fields: [
      { name: 'context',    kind: 'text', required: true,  part: 'context_restatement',
        label: 'Context', help: 'Why the action is needed, restated in full.' },
      { name: 'items',      kind: 'list', required: true,  part: 'numbered_items',
        label: 'Steps', help: 'One step per entry, in order. They are numbered for readback.' },
      { name: 'owner',      kind: 'text', required: true,  part: 'owner',
        label: 'Owner', help: 'Who is expected to carry out the action.' },
      { name: 'dueTimeUTC', kind: 'time', required: true,  part: 'reply_request',
        label: 'Due (UTC)', help: 'When the action should be complete, or when a status report is expected.' },
      { name: 'ackBy',      kind: 'time', required: false,
        label: 'Acknowledge by (UTC)', help: 'When a readback acknowledgement is expected.' },
      { name: 'originWindow', kind: 'text', required: false,
        label: 'Origin window' },
    ],
    training:
      'Action template. Restate why the action is needed so the receiver can judge it ' +
      'without the earlier conversation. List the steps as numbered items so the receiver ' +
      'can read them back and report progress by number. Name one owner and give an ' +
      'explicit due time. The template always asks for an acknowledgement with a readback, ' +
      'because under delay silence cannot be read as agreement.',
  },

  status: {
    id: 'status',
    title: 'Status update',
    entryType: 'action_update',
    fields: [
      { name: 'aid',        kind: 'text', required: true,  part: 'reference',
        label: 'Action id', help: 'The entryId of the action this update refers to.' },
      { name: 'context',    kind: 'text', required: true,  part: 'context_restatement',
        label: 'Context', help: 'Restate the action in one sentence, so the update makes sense on its own.' },
      { name: 'status',     kind: 'enum', required: true,  values: ACTION_STATUSES, part: 'status',
        label: 'Status' },
      { name: 'completed',  kind: 'list', required: false, part: 'numbered_items',
        label: 'Completed steps' },
      { name: 'remaining',  kind: 'list', required: false, part: 'numbered_items',
        label: 'Remaining steps' },
      { name: 'nextUpdateBy', kind: 'time', required: false, part: 'reply_request',
        label: 'Next update by (UTC)' },
      { name: 'version',    kind: 'int',  required: false,
        label: 'Version', help: 'Register version for the conflict rule; defaults to previous + 1.' },
    ],
    training:
      'Status update template. Refer to the action by its id and restate it briefly, ' +
      'because the receiver may be reading several delayed messages at once. Give the ' +
      'register status, list completed and remaining steps by number, and say when the ' +
      'next update will come so the other side knows how long silence is expected.',
  },

  acknowledgement: {
    id: 'acknowledgement',
    title: 'Acknowledgement',
    entryType: null, // question_response or action_update, chosen by refType
    fields: [
      { name: 'refType',    kind: 'enum', required: true,  values: ['question', 'action'], part: 'reference',
        label: 'Acknowledges a' },
      { name: 'refId',      kind: 'text', required: true,  part: 'reference',
        label: 'Reference id', help: 'The entryId of the question or action being acknowledged.' },
      { name: 'readback',   kind: 'text', required: true,  part: 'readback',
        label: 'Readback', help: 'Restate in your own words what you received and understood.' },
      { name: 'answers',    kind: 'list', required: false, part: 'numbered_items',
        label: 'Numbered answers', help: 'For a question: one answer per numbered question, in order.' },
      { name: 'accept',     kind: 'bool', required: false,
        label: 'Accept action', help: 'For an action: true accepts, false rejects. Defaults to true.' },
      { name: 'followUpBy', kind: 'time', required: false, part: 'reply_request',
        label: 'Follow-up by (UTC)' },
      { name: 'version',    kind: 'int',  required: false,
        label: 'Version' },
    ],
    training:
      'Acknowledgement template. Say which question or action you are answering, then ' +
      'read back what you understood in your own words. A readback lets the sender catch ' +
      'a misunderstanding one round trip earlier than they otherwise would. When answering ' +
      'a question, answer each numbered question with the same number, and say so ' +
      'explicitly if a question cannot be answered yet.',
  },
};

const TEMPLATE_IDS = Object.keys(TEMPLATES);

// ── Helpers ──────────────────────────────────────────────────────────────────

const ISO_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?Z$/;

function _getTemplate(templateOrId) {
  const t = typeof templateOrId === 'string' ? TEMPLATES[templateOrId] : templateOrId;
  if (!t || !t.id || !TEMPLATES[t.id]) {
    throw new Error(`Unknown protocol template: ${JSON.stringify(templateOrId)}`);
  }
  return t;
}

function _isBlank(v) {
  return v === undefined || v === null || (typeof v === 'string' && v.trim() === '');
}

function _cleanList(v) {
  if (!Array.isArray(v)) return [];
  return v.map(x => (x === undefined || x === null ? '' : String(x).trim())).filter(x => x !== '');
}

function _numbered(list) {
  return list.map((item, i) => `${i + 1}. ${item}`).join('\n');
}

// ── Validation ───────────────────────────────────────────────────────────────

/**
 * Check values against a template.
 * @param {string|object} templateOrId
 * @param {object} values
 * @returns {{ valid: boolean, issues: Array<{field:string, code:string, part?:string, message:string}> }}
 */
function validate(templateOrId, values) {
  const t = _getTemplate(templateOrId);
  const v = values || {};
  const issues = [];

  for (const f of t.fields) {
    const val = v[f.name];
    if (f.kind === 'list') {
      if (val !== undefined && !Array.isArray(val)) {
        issues.push({ field: f.name, code: 'not_a_list', message: `${f.label} must be a list.` });
        continue;
      }
      if (f.required && _cleanList(val).length === 0) {
        issues.push({ field: f.name, code: 'missing', part: f.part,
          message: `${f.label} is required (${f.part.replace(/_/g, ' ')}).` });
      }
      continue;
    }
    if (_isBlank(val)) {
      if (f.required) {
        issues.push({ field: f.name, code: 'missing', part: f.part,
          message: `${f.label} is required (${f.part.replace(/_/g, ' ')}).` });
      }
      continue;
    }
    if (f.kind === 'time' && !ISO_UTC.test(String(val))) {
      issues.push({ field: f.name, code: 'bad_time', message: `${f.label} must be an ISO 8601 UTC time ending in Z.` });
    } else if (f.kind === 'enum' && !f.values.includes(val)) {
      issues.push({ field: f.name, code: 'bad_value', message: `${f.label} must be one of: ${f.values.join(', ')}.` });
    } else if (f.kind === 'bool' && typeof val !== 'boolean') {
      issues.push({ field: f.name, code: 'bad_value', message: `${f.label} must be true or false.` });
    } else if (f.kind === 'int' && !(Number.isInteger(val) && val >= 1)) {
      issues.push({ field: f.name, code: 'bad_value', message: `${f.label} must be a positive integer.` });
    }
  }

  // Cross-field checks.
  if (t.id === 'status' && !_isBlank(v.context) && _cleanList(v.completed).length === 0
      && _cleanList(v.remaining).length === 0 && v.status !== 'REJECTED') {
    issues.push({ field: 'completed', code: 'missing', part: 'numbered_items',
      message: 'List completed or remaining steps so progress can be tracked by number.' });
  }
  if (t.id === 'acknowledgement' && v.refType === 'question' && _cleanList(v.answers).length === 0) {
    issues.push({ field: 'answers', code: 'missing', part: 'numbered_items',
      message: 'Answer each numbered question, or state that it cannot be answered yet.' });
  }
  if (t.id === 'acknowledgement' && v.refType === 'question' && v.accept !== undefined) {
    issues.push({ field: 'accept', code: 'not_applicable', message: 'Accept applies to actions only.' });
  }

  return { valid: issues.length === 0, issues };
}

// ── Rendering ────────────────────────────────────────────────────────────────

/**
 * Render a template to plain text. Missing optional parts are omitted.
 * Rendering does not require validity; call validate() first to enforce it.
 * @param {string|object} templateOrId
 * @param {object} values
 * @returns {string}
 */
function render(templateOrId, values) {
  const t = _getTemplate(templateOrId);
  const v = values || {};
  const lines = [];
  const push = (label, val) => { if (!_isBlank(val)) lines.push(`${label}: ${String(val).trim()}`); };

  if (t.id === 'question') {
    lines.push(`QUESTION${v.urgency ? ` [${String(v.urgency).toUpperCase()}]` : ''}`);
    push('Context', v.context);
    push('Already tried', v.attempted);
    const qs = _cleanList(v.questions);
    if (qs.length) lines.push('Questions:', _numbered(qs));
    if (!_isBlank(v.replyBy)) {
      lines.push(`Reply requested by ${v.replyBy}${qs.length > 1 ? `, answering each question by number (1-${qs.length})` : ''}.`);
    }
    push('Intended window', v.intendedWindow);
  } else if (t.id === 'action') {
    lines.push('ACTION REQUEST');
    push('Context', v.context);
    push('Owner', v.owner);
    const items = _cleanList(v.items);
    if (items.length) lines.push('Steps:', _numbered(items));
    push('Due', v.dueTimeUTC);
    push('Origin window', v.originWindow);
    lines.push(`Please acknowledge with a readback of the steps${_isBlank(v.ackBy) ? '' : ` by ${v.ackBy}`}.`);
  } else if (t.id === 'status') {
    lines.push(`STATUS UPDATE${_isBlank(v.aid) ? '' : ` for ${v.aid}`}`);
    push('Context', v.context);
    push('Status', v.status);
    const done = _cleanList(v.completed);
    if (done.length) lines.push('Completed:', _numbered(done));
    const rem = _cleanList(v.remaining);
    if (rem.length) lines.push('Remaining:', _numbered(rem));
    push('Next update by', v.nextUpdateBy);
  } else if (t.id === 'acknowledgement') {
    lines.push(`ACKNOWLEDGEMENT${_isBlank(v.refId) ? '' : ` of ${v.refType || 'entry'} ${v.refId}`}`);
    push('Readback', v.readback);
    const ans = _cleanList(v.answers);
    if (ans.length) lines.push('Answers:', _numbered(ans));
    if (v.refType === 'action') lines.push(v.accept === false ? 'Action rejected.' : 'Action accepted.');
    push('Follow-up by', v.followUpBy);
  }
  return lines.join('\n');
}

// ── Register integration ─────────────────────────────────────────────────────

/**
 * Build { type, content } for an LTX register entry from template values.
 * The content carries the fields the SDK reducers read (text, urgency,
 * intendedWindow for questions; description, owner, dueTimeUTC, originWindow
 * for actions; aid/qid, status, response, version for updates) plus a
 * `protocol` object recording the template id, version and structured values.
 * Reducers ignore `protocol`; it is covered by the entry signature.
 *
 * @param {string|object} templateOrId
 * @param {object} values
 * @param {{ strict?: boolean }} [opts]  strict (default true) throws on invalid values
 * @returns {{ type: string, content: object, text: string }}
 */
function toEntryContent(templateOrId, values, opts) {
  const t = _getTemplate(templateOrId);
  const v = values || {};
  const strict = !opts || opts.strict !== false;
  const check = validate(t, v);
  if (strict && !check.valid) {
    const err = new Error(`Protocol template "${t.id}" is incomplete: ${check.issues.map(i => i.message).join(' ')}`);
    err.issues = check.issues;
    throw err;
  }

  const text = render(t, v);
  const structured = {};
  for (const f of t.fields) {
    if (f.kind === 'list') {
      const l = _cleanList(v[f.name]);
      if (l.length) structured[f.name] = l;
    } else if (!_isBlank(v[f.name])) {
      structured[f.name] = v[f.name];
    }
  }
  const protocol = { template: t.id, templateVersion: TEMPLATE_VERSION, fields: structured };

  let type;
  let content;
  if (t.id === 'question') {
    type = 'question';
    content = { text };
    if (!_isBlank(v.urgency)) content.urgency = String(v.urgency);
    if (!_isBlank(v.intendedWindow)) content.intendedWindow = String(v.intendedWindow);
  } else if (t.id === 'action') {
    type = 'action';
    content = { description: text, owner: String(v.owner ?? ''), dueTimeUTC: String(v.dueTimeUTC ?? '') };
    if (!_isBlank(v.originWindow)) content.originWindow = String(v.originWindow);
  } else if (t.id === 'status') {
    type = 'action_update';
    content = { aid: String(v.aid ?? ''), status: v.status };
    if (v.version !== undefined) content.version = v.version;
  } else {
    if (v.refType === 'action') {
      type = 'action_update';
      content = { aid: String(v.refId ?? ''), status: v.accept === false ? 'REJECTED' : 'ACCEPTED' };
    } else {
      type = 'question_response';
      content = { qid: String(v.refId ?? ''), response: text };
    }
    if (v.version !== undefined) content.version = v.version;
  }
  content.protocol = protocol;
  return { type, content, text };
}

/**
 * Create a signed LTX register entry from a template, via the SDK's
 * createRegisterEntry. `sdk` defaults to require('./ltx-sdk').
 * @param {string|object} templateOrId
 * @param {object} values
 * @param {object} entryOpts  { sessionId, nodeId, seq, timestamp, privateKeyB64, entryId? }
 * @param {object} [sdk]
 */
function createEntry(templateOrId, values, entryOpts, sdk) {
  const lib = sdk || require('./ltx-sdk');
  const { type, content } = toEntryContent(templateOrId, values);
  return lib.createRegisterEntry(type, content, entryOpts);
}

// ── Training mode ────────────────────────────────────────────────────────────

/**
 * Training-mode explanation for a template, with per-field help appended.
 * @param {string|object} templateOrId
 * @returns {string}
 */
function trainingText(templateOrId) {
  const t = _getTemplate(templateOrId);
  const fieldLines = t.fields
    .filter(f => f.help)
    .map(f => `- ${f.label}${f.required ? ' (required)' : ''}: ${f.help}`);
  return [t.training, '', ...fieldLines].join('\n');
}

/** Read back a template's structured values from a register entry, or null. */
function protocolOf(entry) {
  const p = entry && entry.content && entry.content.protocol;
  return p && TEMPLATES[p.template] ? p : null;
}

module.exports = {
  TEMPLATE_VERSION,
  TEMPLATES,
  TEMPLATE_IDS,
  validate,
  render,
  toEntryContent,
  createEntry,
  trainingText,
  protocolOf,
};
