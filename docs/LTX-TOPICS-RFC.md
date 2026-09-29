# LTX Topics RFC (experimental extension)

```
Status:        Draft, experimental extension. NOT FOR PRODUCTION.
Capability:    "topics/0"
Extends:       LTX v1.1 (docs/LTX-SPECIFICATION.md), v3 plans only (§4.4)
Stories:       IP-T2 (#15). Implementation: IP-T3 (#16), IP-T4 (#17)
Gate:          Patent record review, IP-T1 (#14)
Research:      docs/research/2026-09-29-discoverability-and-ltx-topics.md §3.4, §4
```

> **EXPERIMENTAL.** This document is a design draft. Nothing here is part of the
> normative LTX specification, and no conforming implementation is required to
> support it. It must not be used in production, promoted, or shipped in a
> published package until the patent record review in issue #14 (IP-T1) is
> complete and a qualified professional has answered the questions in section
> 3.6 of the research note. The boundaries in section 12 (Deferred behaviours)
> are part of this draft, not suggestions.

The key words MUST, MUST NOT, SHOULD and MAY are used as in RFC 2119, but only
within the scope of this experimental extension.

---

## 1. Purpose and scope

LTX already records questions, actions and decisions in one signed,
append-only register log (spec §8 to §10). Participants in long-delay sessions
also need a place to keep several lines of discussion going without waiting for
a live turn. This RFC adds **topics**: persistent, named places for
contributions that any authorised participant can read, draft into and submit
to at any time.

It covers candidates A (persistent topic board) and C (asynchronous topic
batches) from the research decision record (§4.4). Candidate B (agenda-linked
topics) is included **only** as advisory `topicRefs[]` metadata on segments.

Out of scope: any behaviour that gates, cycles or times topic input. See
section 12.

## 2. Definitions

These terms are defined separately and MUST NOT be conflated.

- **Topic.** A persistent organisational object with a stable `id`, a `title`,
  an optional participant list and a status (`open` or `closed`). A topic is
  not tied to time, to a segment, or to a speaker. It exists from the moment it
  is declared until the end of the session record.
- **Contribution.** One signed register entry of type `contribution` that
  belongs to exactly one topic and MAY reply to one earlier contribution in the
  same topic. The author is the signing node.
- **Thread.** The reply tree of contributions inside one topic. A thread is
  **derived data** computed from the log (section 7.4). It is never stored,
  never scheduled and never a unit of input control.
- **Segment.** An existing LTX timed window (spec §3.4). A segment MAY
  *reference* topics through `topicRefs[]` (section 4.2). A segment never
  *owns* a topic, and the segment schedule never affects whether a topic can be
  read, drafted or submitted to.
- **Stream.** Reserved by spec §3.5 and §7 for branch and parallel streams.
  **Topics MUST NOT populate `streams[]`.** A topics-capable node MUST leave
  `streams[]` exactly as it found it (absent or empty).

## 3. Capability flag

A plan that carries topic fields MUST declare the capability string
`"topics/0"` in an optional v3 `caps[]` array:

```json
{ "v": 3, "caps": ["topics/0"], "topics": [ ... ] }
```

- `caps[]` is a sorted array of unique strings. The `/0` suffix is the
  experimental revision; a future stable revision would use a new string.
- Because `caps[]` and `topics[]` are v3 fields, they are part of the RFC 8785
  canonical JSON and therefore of the v3 SHA-256 planId (spec §4.5). Adding or
  removing them produces a different plan with a different planId.
- A node advertises support for the capability out of band (for example in its
  key bundle or session join message). This RFC does not define that channel.

## 4. Plan fields (v3 only)

### 4.1 `topics[]`

Optional. An array of topic seeds.

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | string | yes | Stable topic id, unique within the plan. Matches `^[A-Za-z0-9._-]{1,64}$`. |
| `title` | string | yes | Human-readable title, 1 to 200 characters. |
| `participants` | string[] | no | Node ids (plan `nodes[].id`) invited to the topic. Absent means every plan node. Advisory for display and notification only; see section 9. |
| `status` | `"open"` \| `"closed"` | no | Initial status. Default `"open"`. |

Plan seeds are advisory in the same way as question seeds (spec §9.2). A
topic becomes part of the record when a node emits a signed `topic` entry for
it (section 5.1). Nodes SHOULD re-emit plan seeds as `topic` entries at plan
lock.

### 4.2 Per-segment `topicRefs[]`

Optional. An array of topic ids on any segment:

```json
{ "type": "TX", "q": 3, "speaker": "N0", "label": "Habitat status", "topicRefs": ["T1"] }
```

`topicRefs[]` is **advisory only**. A client MAY show a "recommended focus"
label for the current segment. A client MUST NOT use `topicRefs[]` to:

- lock, disable, hide or collapse any topic or draft;
- move keyboard focus, scroll position or the selected topic;
- change which topic is shown, automatically or on a timer.

A `topicRefs[]` entry that names an unknown topic id is ignored for display.

### 4.3 Compatibility rules

1. **v2 plans are never changed.** Topic fields MUST NOT be added to a v2 plan
   object. The frozen v2 planId (spec §4.3) hashes `JSON.stringify` in
   insertion order, so any added field would change it.
2. **No silent upgrade.** A topics-capable client MUST NOT upgrade a v2 plan to
   v3 in order to attach topics. Upgrading is an explicit, user-initiated
   operation (`upgradePlanToV3()`) that produces a new plan with a new planId,
   and the client SHOULD show both planIds to the user before confirming.
3. **Unsupported-field treatment.** A node that does not implement
   `"topics/0"`:
   - MUST render the plan without topics (ignore `topics[]`, `caps[]` and
     every `topicRefs[]`);
   - MUST NOT remove, reorder or rewrite those fields, and MUST NOT re-sign or
     re-hash a modified copy of the plan;
   - MUST compute the planId over the plan exactly as received;
   - MUST keep `topic`, `topic_update` and `contribution` entries in its log
     and relay them unchanged, even though it does not reduce them.
4. **Reserved fields.** `streams[]` MUST stay absent or empty (spec §4.4).
   Topics are never streams.

## 5. Register entry types

All three types are ordinary register entries (LTX-SECURITY §9.5): the
envelope is `{ entryId, sessionId, nodeId, seq, type, content, timestamp, sig }`
and the signature covers the canonical JSON of the envelope without `sig`.
`nodeId` is the author. `timestamp` is ISO 8601 UTC.

### 5.1 `topic` (entryId prefix `TOP-`)

```json
{ "topicId": "T1", "title": "Water recycler", "participants": ["N0", "N1"] }
```

Declares a topic. `participants` is optional. The first `topic` entry for a
`topicId` in the total order (section 6.2) is the creation; later `topic`
entries for the same id are superseded (they remain in the log).

### 5.2 `topic_update` (entryId prefix `TOP-`)

```json
{ "topicId": "T1", "version": 2, "status": "closed", "title": "Water recycler (resolved)" }
```

Changes `status`, `title` or `participants`. `version` is the object version
(creation is version 1). Conflicts resolve with the spec §8.2 rule: **highest
version wins; at equal versions the lexicographically lowest editor nodeId
wins.** This is the same rule as `reduceQuestions` and `reduceActions`.

### 5.3 `contribution` (entryId prefix `CTB-`)

```json
{
  "topicId": "T1",
  "contributionId": "CTB-N1-7",
  "replyTo": "CTB-N0-3",
  "body": "Filter pressure is back to nominal after the swap."
}
```

| Field | Location | Notes |
| --- | --- | --- |
| `topicId` | content | Required. |
| `contributionId` | content | Required. Defaults to the entryId. Unique per session. |
| `replyTo` | content | Optional contributionId of the parent. |
| `body` | content | Required plain text, at most 16 KiB UTF-8. Clients MUST render it as text, never as HTML. |
| author | envelope `nodeId` | The signing node. |
| `seq` | envelope | Per-node sequence number. |
| `timestamp` | envelope | Author's clock at submission. Used for ordering only, never for gating. |

Contributions are immutable. Editing or retracting is out of scope for
revision 0; a follow-up contribution replying to the original is the
supported pattern.

### 5.4 Batch envelope (candidate C)

A batch is a **transport envelope**, not a register entry. It lets a node
compose contributions across several topics and send them together over a
long-delay link.

```json
{
  "type": "topic_batch",
  "v": 0,
  "batchId": "BAT-N1-7-9",
  "sessionId": "...",
  "nodeId": "N1",
  "createdAt": "2026-09-29T10:00:00.000Z",
  "entries": [ { "...signed entry..." }, { "...signed entry..." } ],
  "batchSig": { "signature": "...", "nonceSalt": "..." }
}
```

- Every entry in `entries[]` MUST be signed by, and carry the `nodeId` of, the
  batch sender. A node batches only its own entries.
- `batchSig` is a hedged Ed25519 signature (LTX-SECURITY hedged EdDSA) over the
  canonical JSON of the envelope without `batchSig`. It attests grouping only.
- Entries remain the unit of trust. A receiver verifies each entry
  individually and merges the valid ones into its log as if they had arrived
  separately. A batch adds **no** ordering, timing or release semantics: its
  entries are ordered by section 6.2 like any others, and nothing is held back
  until a batch is complete.
- If `batchSig` fails, the receiver reports the batch as invalid but still
  merges each entry that verifies on its own.

## 6. Deterministic handling

### 6.1 Merge

Topic entries use the spec §8.2 merge unchanged:

1. **Verify** each entry signature against the key cache.
2. **Union** verified entries, de-duplicated by `(nodeId, seq)`.
3. **Order** by `(timestamp, nodeId, seq)` ascending.
4. **Reduce** (section 7).

### 6.2 Late, duplicate and out-of-order entries

- **Late.** A valid entry that arrives after later-sequenced entries from the
  same node MUST be merged, not dropped. The transport replay check
  (`createSequenceTracker().recordSeq`, which rejects `seq <= last`) is a
  per-link freshness filter for live frames and MUST NOT be applied to register
  entries delivered by merge or batch. This is the distinction tracked as
  IP-L4.
- **Duplicate.** Two copies of the same `(nodeId, seq)` with identical signed
  content collapse to one.
- **Equivocation.** Two *different* signed entries with the same
  `(nodeId, seq)` are an equivocation by that node. To stay independent of
  arrival order, the entry whose canonical JSON sorts lowest is kept, and the
  pair is reported for human review. The discarded entry is never silently
  lost from the report.
- **Out of order.** Arrival order never matters. The reduced state is a pure
  function of the set of verified entries, so any delivery order, including
  partitioned delivery that later heals, converges to identical state on every
  node that holds the same set.

### 6.3 Concurrent replies

Two or more replies to the same parent are all kept. Siblings are ordered by
the total order of section 6.1. There is no "winning" reply.

### 6.4 Parent resolution

A reply attaches to its parent only if the parent is a contribution **in the
same topic** that **precedes it in the total order**. Otherwise the reply is
shown at the root of its topic with `parentUnresolved: true`. This makes
reply cycles impossible and keeps the tree deterministic. If a missing parent
later arrives and precedes the reply, the next reduction attaches it.

### 6.5 Contributions before their topic

A contribution whose `topicId` has no `topic` entry yet is kept as an
**orphan** and re-evaluated on every reduction. It appears in its topic as soon
as the `topic` entry is merged, wherever the two fall in the total order.

### 6.6 Close and reopen

`status` is changed only by `topic_update` under the section 5.2 conflict
rule. Closing a topic is an **organisational label**, not a lock:

- A closed topic stays readable, draftable and submittable.
- A contribution recorded after the winning close (in total order) is kept
  and flagged `afterClose: true` for display. It is never rejected.
- Reopening is a later `topic_update` with a higher version and
  `status: "open"`. Concurrent close and reopen at the same version resolve to
  the entry from the lowest editor nodeId.

## 7. Reduced state

### 7.1 Topic register

`reduceTopics(entries)` returns, per topicId:
`{ topicId, title, participants?, status, version, creator, editor, contributionCount }`,
plus `orphans[]` (contributions whose topic is unknown) and `superseded[]`
(entryIds that lost a conflict or duplicated a creation).

### 7.2 Contributions

Each contribution is reduced to
`{ contributionId, topicId, replyTo?, body, author, seq, timestamp, entryId, afterClose }`.
A second contribution reusing an existing `contributionId` is superseded.

### 7.3 Determinism

Implementations MUST produce identical reduced state from identical sets of
verified entries. This is a conformance requirement in the same sense as spec
§9.4.

### 7.4 Threads

`buildThreads(topicId)` returns the forest of reply trees for one topic, roots
and siblings in total order, applying section 6.4.

## 8. Interaction with questions, actions and decisions

- Topics sit next to the existing registers in the same log. They do not
  change the question, action or decision reducers.
- A `question`, `action` or `decision` entry MAY carry an optional
  `topicId` in its content to say where it was discussed. Existing reducers
  ignore unknown content fields, so this needs no reducer change. The topic
  board MAY list linked items under the topic.
- A contribution MAY mention a qid, aid or decision id in its body. That is
  plain text and creates no register link.
- The MERGE segment snapshot (spec §8.4) MAY include a `topicRegister` field
  in a future revision. Revision 0 does not add it, so `merge_snapshot`
  content is unchanged.

## 9. Authorisation and participants

"Authorised" means a node that holds a valid NIK in the session key cache.
Every authorised node can read every topic and submit to every topic.
`participants[]` is used only to decide who is notified and whose name appears
on the topic card. It MUST NOT be used to hide a topic from, or refuse a
contribution by, another authorised node in revision 0. Restricted topics are
future work and would need their own review.

## 10. Topologies

### 10.1 Two nodes

Earth (N0) and Mars (N1), one-way delay D. Each node writes contributions
whenever it likes. Entries reach the other node about D later, as batches or
single entries. Each side's board shows its own entries at once and the other
side's when they arrive. After both logs are exchanged, both boards reduce to
the same state. D is shown to the user as an expected-arrival estimate and is
never used to schedule, enable or disable input.

### 10.2 Several nodes with asymmetric delay

Earth (N0), Mars (N1) and a relay or lunar node (N2), with pair delays from
the v3 `delays` matrix (spec §3.7.2), for example N0|N1 = 840 s, N0|N2 = 1.3 s,
N1|N2 = 845 s. Delivery order differs per node: N0 may see N2's reply to an
N1 contribution before N1's contribution itself arrives. Section 6.4 keeps the
reply at the root with `parentUnresolved` until the parent arrives, and
section 6.2 guarantees that once all three logs are exchanged, every node
reduces to identical state. Partitions (for example a conjunction blackout of
N1) delay convergence but do not change the result.

Delay values used for display MUST come from the plan (`nodes[].delay` or
`delays`) as typed by the planner. A topics implementation MUST NOT compute
them from light-time or ephemeris (see section 12).

## 11. Accessibility requirements

A topic board client MUST:

1. Be fully operable by keyboard alone: every control is a native `button`,
   `input`, `textarea` or `select` with a visible label and a visible focus
   indicator.
2. Announce arriving contributions through a polite live region
   (`aria-live="polite"`), naming the topic, the author and both the expected
   and actual arrival time. Announcements MUST NOT move focus.
3. Never move focus, change the selected topic or scroll the view on its own,
   including when a recommended focus (section 4.2) changes or a contribution
   arrives.
4. Never lose a draft. Drafts are kept per topic and survive switching topics,
   closing a topic, reloading the page and a change of recommended focus.
5. Show status (open, closed, recommended focus, parent unresolved,
   after-close) as text, not only by colour or icon.
6. Render thread depth with list semantics (nested `ul`/`li` or `role="tree"`)
   so screen readers report nesting.
7. Respect `prefers-reduced-motion` and avoid auto-advancing or animated
   presentation of topics.

## 12. Deferred behaviours (out of scope pending professional review)

The research note (§3.4, §4.2, §4.4) identifies reported limitations of
US11397521B2 (Braided Communications) whose claim text has not yet been
checked. Until the patent record review in issue #14 and a professional
opinion are complete, the following are **out of scope** for this RFC and for
every implementation of `"topics/0"`:

- **Gated input.** Enabling input for one topic, thread or participant at a
  time; disabling, hiding or queueing drafts or submissions for any topic;
  "your turn" style activation of input.
- **Cyclic presentation.** Presenting topics or threads in a rotating cycle;
  automatically advancing the displayed or focused topic; carousel UI for
  topics or threads (reported dependent claim 8).
- **Latency-timed intervals.** Deriving any topic interval, rotation period,
  focus duration or input window from light-time, pair delay or ephemeris;
  timer-driven changes of topic focus.
- **Spacecraft-coordinate input.** Feeding planet or spacecraft positions
  (for example `planet-time` `lightTravelSeconds`) into topic behaviour.
- **Automatic focus from `topicRefs[]`.** Any use beyond an advisory label.

Delay values MAY be shown as text (expected arrival). That display does not
control anything.

## 13. Security considerations

- Topic entries inherit register signing, merge verification and Merkle
  inclusion from LTX-SECURITY §9. No new key material is introduced.
- Bodies are untrusted text. Clients MUST escape them and MUST NOT follow or
  preview links automatically.
- Equivocation (section 6.2) is detectable because both entries are signed by
  the same NIK. Clients SHOULD surface it.
- Batches do not weaken per-entry verification (section 5.4).

## 14. Evaluation plan

This extension is evaluated before any change to its status:

- IP-R2 replication study kit (research story #19) supplies delay × medium ×
  protocol scenarios and log export.
- IP-R3 comparative evaluation (research story #20) compares threaded
  messaging, LTX, and LTX with topics, using the IP-R2 kit with three
  participants and several topics.
- Conformance: the reference tests in `javascript/ltx/tests/topics.js` cover
  duplicate, out-of-order and partitioned delivery converging on three nodes,
  concurrent replies, close and reopen, unchanged v2 planIds and untouched
  `streams[]`.

## 15. Reference implementation (experimental)

- `javascript/ltx/ltx-topics.js`: entry builders, batch envelope, merge,
  reducer and thread builder, built on `ltx-sdk.js` register primitives.
- `demo/topics.html`: local-only accessible topic board simulation
  (`noindex`).

Neither is published in the `interplanet-ltx` package.
