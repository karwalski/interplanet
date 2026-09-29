# LTX Protocol Templates

**Status:** experimental, 2026-09-29 (story IP-R1, issue #18)
**Module:** `javascript/ltx/ltx-protocol-templates.js`
**Tests:** `javascript/ltx/tests/protocol-templates.js`

## Purpose

Under signal delay, a message that needs clarification costs at least one extra
round trip. Protocol templates give LTX question and action entries a fixed
structure so that each message can be understood on its own and each reply can
be checked against what was asked.

The templates are **informed by** the published approach of Fischer and Mosier
(see [Evidence](#evidence)). That approach uses context restatement, numbered
questions or items, explicit acknowledgement or readback, and an explicit
request for a response with an expected reply time. InterPlanet does not
reproduce the Fischer and Mosier protocols, and it does not claim that its
templates match their content. No endorsement by the authors, their
institutions or NASA is implied.

## Templates

| Template | Register entry | Required parts | Optional parts |
| --- | --- | --- | --- |
| `question` | `question` | context restatement, numbered questions, reply-by time | urgency, intended window, what was already tried |
| `action` | `action` | context restatement, numbered steps, owner, due time | acknowledge-by time, origin window |
| `status` | `action_update` | action id, context restatement, register status, completed or remaining steps | next update time, version |
| `acknowledgement` | `question_response` (for a question) or `action_update` (for an action) | reference type and id, readback; numbered answers when acknowledging a question | accept (actions only, default true), follow-up time, version |

All times are ISO 8601 UTC strings ending in `Z`.

## API

```js
const pt = require('./ltx-protocol-templates');

pt.validate('question', values);
// { valid: false, issues: [{ field: 'context', code: 'missing',
//   part: 'context_restatement', message: 'Context is required (context restatement).' }] }

pt.render('question', values);        // plain text, numbered
pt.trainingText('question');          // training-mode explanation plus field help
pt.toEntryContent('question', values); // { type: 'question', content, text }
pt.createEntry('question', values, { sessionId, nodeId, seq, timestamp, privateKeyB64 });
pt.protocolOf(entry);                 // structured values back from a signed entry, or null
```

`validate()` reports each missing structural part with a `part` code:
`context_restatement`, `numbered_items`, `reply_request`, `readback`, `owner`,
`reference` or `status`. A user interface can use these codes to prompt for the
missing element before sending.

`toEntryContent()` throws on invalid values unless `{ strict: false }` is passed.

## Register compatibility

The module requires `ltx-sdk.js` and does not change it. It produces entry
content that the existing reducers already understand:

- `question`: `content.text` is the rendered template; `urgency` and
  `intendedWindow` are copied when present.
- `action`: `content.description` is the rendered template; `owner`,
  `dueTimeUTC` and `originWindow` are copied.
- `status` and action acknowledgements: `action_update` with `aid`, `status`
  and optional `version`.
- question acknowledgements: `question_response` with `qid` and `response`
  (the rendered readback and numbered answers).

Every entry also carries `content.protocol = { template, templateVersion, fields }`
with the structured values. `reduceQuestions` and `reduceActions` ignore this
field, so nodes without template support still see a readable question or
action. The field is part of the signed content, so it cannot be changed
without invalidating the signature.

Note that an acknowledgement and a later status update for the same action are
both `action_update` entries. Under the SDK conflict rule the later version
wins and the earlier update is listed in `superseded`. The acknowledgement is
still in the signed log.

## Training mode

Each template has a `training` string that explains why each part exists, and
`trainingText()` appends the help text for each field. A client can show this
text next to the form in a training session and hide it in normal use. Protocol
training was the manipulated variable in Mosier and Fischer (2023), which is why
the explanation is kept separate from the template itself.

## Evidence

The research summary is in
`docs/research/2026-09-29-discoverability-and-ltx-topics.md`, section 3.2.

- Fischer, U. and Mosier, K. (2014). The impact of communication delay and
  medium on team performance and communication in distributed teams.
  *Proceedings of the Human Factors and Ergonomics Society Annual Meeting*
  58(1). doi:10.1177/1541931214581025. 24 teams of three (two crew members and
  one flight controller) worked on simulated spacecraft life-support failures.
  Medium (text or voice) was varied between groups and delay presence within
  groups. Under delay, no differences were found between voice and text.
- Fischer, U. and Mosier, K. (2015). Communication protocols to support
  collaboration in distributed teams under asynchronous conditions.
  *Proceedings of the HFES Annual Meeting*. doi:10.1177/1541931215591001.
- Fischer, U. and Mosier, K. (2016). Protocols for asynchronous communication
  in space operations. NASA Human Research Program task report. Describes
  structured communication templates, with participants trained before analog
  missions that included 2 to 4 days of delayed communication.
- Mosier, K. and Fischer, U. (2023). Meeting the challenge of transmission
  delay: communication protocols for space operations. *Human Factors*
  65(6):1235-1250. doi:10.1177/00187208211047085. 24 teams of three, voice or
  text, with protocol training as a between-groups variable. The authors
  describe the protocols as feasible, usable and effective, and state that they
  were adopted for training in NASA analog simulations.

## Limitations

- The evidence above was read at abstract level. The InterPlanet templates have
  not been evaluated. `research/replication-kit/` provides materials for such an
  evaluation.
- The templates are not integrated into the demo UI yet.
