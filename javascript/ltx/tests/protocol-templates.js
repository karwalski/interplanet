'use strict';
/**
 * protocol-templates.js — Unit tests for ltx-protocol-templates.js
 * Story IP-R1 (Refs #18)
 * No external test framework. Run with: node tests/protocol-templates.js
 */

const ltx = require('../ltx-sdk');
const pt = require('../ltx-protocol-templates');

let passed = 0;
let failed = 0;

function check(name, cond) {
  if (cond) { passed++; }
  else { failed++; console.log('FAIL:', name); }
}

function throws(fn) {
  try { fn(); return false; } catch (e) { return e; }
}

const Q = {
  context: 'CO2 scrubber B shows 4.1 mmHg ppCO2 and rising since 14:02 UTC. Scrubber A is offline for maintenance.',
  questions: ['Should we bring scrubber A back online early?', 'Is the ppCO2 sensor on B known to drift?'],
  replyBy: '2026-10-01T15:30:00Z',
  urgency: 'urgent',
  attempted: 'Power-cycled scrubber B once at 14:10 UTC.',
};

const A = {
  context: 'ppCO2 rising in module 2 with scrubber B degraded.',
  items: ['Close hatch to module 2', 'Swap scrubber B cartridge', 'Report ppCO2 every 10 minutes'],
  owner: 'Crew 1',
  dueTimeUTC: '2026-10-01T16:00:00Z',
  ackBy: '2026-10-01T15:20:00Z',
};

// ── Definitions ────────────────────────────────────────────────────────────

console.log('\n── Protocol templates: definitions ──────────');
check('four templates', pt.TEMPLATE_IDS.length === 4);
for (const id of ['question', 'action', 'status', 'acknowledgement']) {
  const t = pt.TEMPLATES[id];
  check(`${id} defined`, t && t.id === id);
  check(`${id} has fields`, Array.isArray(t.fields) && t.fields.length > 0);
  check(`${id} has training text`, typeof t.training === 'string' && t.training.length > 80);
  check(`${id} trainingText includes field help`, pt.trainingText(id).includes('(required)'));
  check(`${id} training text has no em dash`, !pt.trainingText(id).includes('—'));
}
check('unknown template throws', throws(() => pt.render('nope', {})));
check('question requires context', pt.TEMPLATES.question.fields.find(f => f.name === 'context').required);
check('question requires reply time', pt.TEMPLATES.question.fields.find(f => f.name === 'replyBy').required);

// ── Validation ─────────────────────────────────────────────────────────────

console.log('\n── Protocol templates: validate ─────────────');
check('complete question valid', pt.validate('question', Q).valid);
const noCtx = pt.validate('question', Object.assign({}, Q, { context: '  ' }));
check('blank context flagged', !noCtx.valid);
check('missing context names part',
  noCtx.issues.some(i => i.field === 'context' && i.part === 'context_restatement'));
const noQs = pt.validate('question', Object.assign({}, Q, { questions: ['', '  '] }));
check('empty question list flagged', noQs.issues.some(i => i.part === 'numbered_items'));
const noReply = pt.validate('question', Object.assign({}, Q, { replyBy: undefined }));
check('missing reply time flagged', noReply.issues.some(i => i.part === 'reply_request'));
check('bad time flagged',
  pt.validate('question', Object.assign({}, Q, { replyBy: 'tomorrow' })).issues.some(i => i.code === 'bad_time'));
check('bad urgency flagged',
  pt.validate('question', Object.assign({}, Q, { urgency: 'asap' })).issues.some(i => i.code === 'bad_value'));
check('questions must be a list',
  pt.validate('question', Object.assign({}, Q, { questions: 'one' })).issues.some(i => i.code === 'not_a_list'));
check('complete action valid', pt.validate('action', A).valid);
check('action without owner flagged',
  pt.validate('action', Object.assign({}, A, { owner: '' })).issues.some(i => i.part === 'owner'));
check('status without steps flagged',
  !pt.validate('status', { aid: 'ACT-x-1', context: 'Swap cartridge', status: 'ACCEPTED' }).valid);
check('status with remaining steps valid',
  pt.validate('status', { aid: 'ACT-x-1', context: 'Swap cartridge', status: 'ACCEPTED', remaining: ['Swap'] }).valid);
check('status bad enum flagged',
  !pt.validate('status', { aid: 'a', context: 'c', status: 'MAYBE', remaining: ['x'] }).valid);
check('question ack without answers flagged',
  pt.validate('acknowledgement', { refType: 'question', refId: 'QST-a-1', readback: 'You asked about B.' })
    .issues.some(i => i.field === 'answers'));
check('ack without readback flagged',
  pt.validate('acknowledgement', { refType: 'action', refId: 'ACT-a-1' })
    .issues.some(i => i.part === 'readback'));
check('accept on question ack flagged',
  pt.validate('acknowledgement', { refType: 'question', refId: 'q', readback: 'r', answers: ['a'], accept: true })
    .issues.some(i => i.code === 'not_applicable'));

// ── Rendering ──────────────────────────────────────────────────────────────

console.log('\n── Protocol templates: render ───────────────');
const qText = pt.render('question', Q);
check('question starts with header', qText.startsWith('QUESTION [URGENT]'));
check('question restates context', qText.includes('Context: CO2 scrubber B'));
check('question numbers items', qText.includes('1. Should we') && qText.includes('2. Is the ppCO2'));
check('question requests reply with time', qText.includes('Reply requested by 2026-10-01T15:30:00Z'));
check('question asks for numbered answers', qText.includes('answering each question by number (1-2)'));
const aText = pt.render('action', A);
check('action numbers steps', aText.includes('3. Report ppCO2 every 10 minutes'));
check('action requests readback', aText.includes('Please acknowledge with a readback of the steps by 2026-10-01T15:20:00Z.'));
const sText = pt.render('status', { aid: 'ACT-n-2', context: 'Swap cartridge', status: 'DONE', completed: ['a', 'b'] });
check('status renders completed list', sText.includes('Completed:\n1. a\n2. b'));
const kText = pt.render('acknowledgement', { refType: 'action', refId: 'ACT-n-2', readback: 'Close hatch, swap, report.', accept: false });
check('action ack renders rejection', kText.includes('Action rejected.'));
check('render omits missing optional parts', !pt.render('question', { context: 'x', questions: ['y'] }).includes('Reply requested'));

// ── Register integration ───────────────────────────────────────────────────

console.log('\n── Protocol templates: register entries ─────');
check('invalid values throw in strict mode', throws(() => pt.toEntryContent('question', { questions: ['x'] })).issues);
check('non-strict does not throw', pt.toEntryContent('question', { questions: ['x'] }, { strict: false }).type === 'question');

const { nik: crewNik, privateKeyB64: crewPriv } = ltx.generateNIK({ nodeLabel: 'Crew' });
const { nik: fcNik, privateKeyB64: fcPriv } = ltx.generateNIK({ nodeLabel: 'Flight controller' });
const keyCache = { [crewNik.nodeId]: crewNik, [fcNik.nodeId]: fcNik };
const base = { sessionId: 'sess-r1' };
const crewOpts = (seq, ts) => Object.assign({}, base, { nodeId: crewNik.nodeId, seq, timestamp: ts, privateKeyB64: crewPriv });
const fcOpts = (seq, ts) => Object.assign({}, base, { nodeId: fcNik.nodeId, seq, timestamp: ts, privateKeyB64: fcPriv });

const qEntry = pt.createEntry('question', Q, crewOpts(1, '2026-10-01T15:00:00.000Z'), ltx);
check('question entry type', qEntry.type === 'question');
check('question entry id prefix', qEntry.entryId.startsWith('QST-'));
check('question entry verifies', ltx.verifyRegisterEntry(qEntry, keyCache).valid);
check('question entry carries protocol', pt.protocolOf(qEntry).template === 'question');
check('protocol keeps structured questions', pt.protocolOf(qEntry).fields.questions.length === 2);

const ackQ = pt.createEntry('acknowledgement', {
  refType: 'question', refId: qEntry.entryId,
  readback: 'You see ppCO2 4.1 on B with A offline and ask about A and the B sensor.',
  answers: ['Yes, bring A online now.', 'No known drift on B.'],
}, fcOpts(1, '2026-10-01T15:25:00.000Z'), ltx);
check('question ack is question_response', ackQ.type === 'question_response');

const aEntry = pt.createEntry('action', A, fcOpts(2, '2026-10-01T15:26:00.000Z'), ltx);
check('action entry id prefix', aEntry.entryId.startsWith('ACT-'));
const ackA = pt.createEntry('acknowledgement', {
  refType: 'action', refId: aEntry.entryId, readback: 'Close hatch, swap cartridge, report every 10 min.',
}, crewOpts(2, '2026-10-01T15:40:00.000Z'), ltx);
check('action ack is action_update', ackA.type === 'action_update' && ackA.content.status === 'ACCEPTED');
const stA = pt.createEntry('status', {
  aid: aEntry.entryId, context: 'Scrubber B cartridge swap.', status: 'DONE',
  completed: A.items, nextUpdateBy: '2026-10-01T17:00:00Z',
}, crewOpts(3, '2026-10-01T16:05:00.000Z'), ltx);

const all = [qEntry, ackQ, aEntry, ackA, stA];
check('all template entries verify', all.every(e => ltx.verifyRegisterEntry(e, keyCache).valid));
const qs = ltx.reduceQuestions(all);
const qState = qs.byId[qEntry.entryId];
check('reducer sees question', !!qState);
check('reducer question text is rendered template', qState.text === pt.render('question', Q));
check('reducer keeps urgency', qState.urgency === 'urgent');
check('reducer marks answered', qState.status === 'ANSWERED');
check('reducer response has numbered answers', qState.response.includes('2. No known drift on B.'));
const as = ltx.reduceActions(all);
const aState = as.byId[aEntry.entryId];
check('reducer sees action', !!aState);
check('reducer action owner', aState.owner === 'Crew 1');
check('reducer action due', aState.dueTimeUTC === '2026-10-01T16:00:00Z');
check('reducer action DONE after status update', aState.status === 'DONE' && aState.version === 3);
check('no superseded questions', qs.superseded.length === 0);
check('ack update superseded by later status update (SDK rule)',
  as.superseded.length === 1 && as.superseded[0] === ackA.entryId);
check('protocolOf returns null for plain entry', pt.protocolOf({ content: { text: 'x' } }) === null);

// ── Summary ────────────────────────────────────────────────────────────────

console.log('\n══════════════════════════════════════════');
console.log(`${passed} passed  ${failed} failed`);
if (failed > 0) process.exit(1);
