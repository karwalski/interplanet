# LTX v1.1 Specification
## Light-Time eXchange (LTX)
### Distributed High-Latency Deliberation Protocol

**Document status:** v1.1 — 2026-07-07
**Companion documents:**
- `spec/ltx-spec.md` — normative wire format (LtxPlan schema, hash algorithm, ICS properties, relay config, REST/MCP APIs)
- `docs/LTX-SECURITY.md` v1.1 — security architecture (normative where it overlaps §13 / Appendix A)

**Changelog v1.0 → v1.1**
- §4 rewritten around the shipped v2 plan schema; the v1.0 §4.1 field list (`planId`, `startEpochUTC`, `delayMatrix`, `streams[]`, `questions[]`, `actions[]` as required fields) never shipped and is withdrawn. v3 is defined as a strictly additive, opt-in extension (§4.4).
- planId rules split: the v2 algorithm is frozen byte-for-byte (§4.3); v3 plans use SHA-256 over RFC 8785 canonical JSON (§4.5).
- Delay model contradiction resolved: v2 delays are HOST-relative; v3 adds an authoritative pair-wise `delays` matrix with a defined conservative fallback (§3.7).
- Node roles aligned to implementation: `HOST`, `PARTICIPANT`, `OBSERVER`. `RELAY` is a transport function, not a plan role (§3.1).
- Plan Lock rewritten: amendment-chain precedence, HOST-signature precedence, N>2 full/quorum lock semantics (§5).
- In-place BUFFER insertion under drift withdrawn; replaced by the signed Plan Amendment Procedure (§6.4).
- §8–§10 rewritten: questions, actions, and merge are defined over the signed Merkle audit log (LTX-SECURITY §9) with deterministic reducers and a deterministic merge order.
- §7 Branching/Streams marked **SPECIFIED — NOT YET IMPLEMENTED**; conformance identifiers reserved.
- §14 Conference Mode formalised (attributed segments, viewer-perspective derivation, Blocks/Cycles, fairness rotation, per-attendee calendar export).

---

# 1. Purpose

Light-Time eXchange (LTX) defines a deterministic, latency-aware meeting and conference protocol for human collaboration across spatially separated nodes where signal propagation delay prevents real-time conversational interaction.

LTX is transport-agnostic but designed to operate over Delay/Disruption Tolerant Networking systems (including HDTN).

LTX governs:
- Structured turn-taking
- Deterministic scheduling
- Branching and parallel streams (reserved, §7)
- Merge and conflict resolution
- Artefact integrity
- Graceful degradation

## 1.1 Design Threshold

LTX is designed for communication channels where one-way signal propagation delay exceeds **120 seconds** — the threshold above which real-time conversational interaction becomes structurally impractical. At this delay, every exchange requires a minimum of 4 minutes of dead time (one round-trip), making traditional meeting formats unworkable.

At Earth–Mars distances (ranging from ~3 to ~22 minutes one-way), every exchange is asynchronous by necessity. LTX provides deterministic structure for these sessions.

| Delay range | Communication mode |
|-------------|-------------------|
| < 1 s | Real-time (Earth-local) |
| 1 s – 120 s | Near-real-time (Moon, L1/L2 points) |
| > 120 s | **LTX territory** — async structure required |
| 3–22 min | Earth–Mars (primary design target) |
| 33–83 min | Earth–Jupiter |
| 67–84 min | Earth–Saturn |

---

# 2. Architectural Model

## 2.1 Layering

Physical Layer
Propagation limited by speed of light.

Transport Layer
DTN / HDTN store-and-forward networking. Relay servers operate at this layer (§3.1).

Application Layer
LTX session orchestration and state management.

---

# 3. Core Concepts

## 3.1 Node
A Node is a participating site with:
- Local participants
- Local time authority
- Local recording capability
- Independent execution of SessionPlan

Examples include planetary bases, orbital stations, spacecraft, and Earth-based control centres.

### Node Roles

- **HOST** — The reference clock node. All timing and UTC anchoring is relative to the host. There MUST be exactly one HOST, and it MUST be the first entry of `nodes[]` with `delay: 0`. The host is typically (but not required to be) an Earth-based site.
- **PARTICIPANT** — A node that transmits and receives within the session plan.
- **OBSERVER** — A passive node. Receives all transmissions but does not transmit.

> **Change from v1.0:** the v1.0 roles `RELAY` and `RECEIVE-ONLY` are withdrawn as *plan* roles. `OBSERVER` replaces `RECEIVE-ONLY`. Store-and-forward relaying is a **transport function** performed by DTN relay infrastructure (see `spec/ltx-spec.md` §9, DTN Relay Config), not a session participant; relays are untrusted by design (LTX-SECURITY §3.4) and never appear in `nodes[]`.

## 3.2 Quantum (Q)
Smallest scheduling unit.
Default: **5 minutes** (reference SDKs' `DEFAULT_QUANTUM`; all demo templates).
Configurable per session (1–60 minutes).

> Known divergence at v1.1 publication: the Python port defaults to 3 and
> `spec/ltx-spec.md` §2.1 states 3. Both are wrong relative to the reference
> implementations and are tracked as a bug; 5 is normative.

## 3.3 Window (W)
Contiguous set of quanta.
Example: W = 3Q = 15 minutes at quantum 5.

## 3.4 Segment Types

Core types (every implementation MUST support):

- **PLAN_CONFIRM** – Initial handshake window; all nodes verify identical plan before session begins (§5).
- **TX** – Transmit window. In LTX-LIVE: the host presents to participants. In LTX-ASYNC: all nodes broadcast simultaneously. A TX segment MAY be *attributed* to a specific presenting node (§3.4.1).
- **RX** – Receive window. In LTX-LIVE: participants respond to the host. In LTX-ASYNC: all nodes watch/listen to the other parties' simultaneous broadcasts arriving after signal delay.
- **CAUCUS** – Local-only discussion window; no transmissions in progress.
- **BUFFER** – Timing slack window to absorb propagation variance and scheduling drift. BUFFER segments are declared in the plan at authoring time; they are never inserted into a locked plan in place (§6.4).
- **MERGE** – Reintegration phase; consolidates artefacts and registers into the plenary record (§8).

Auxiliary types (implemented; see `spec/ltx-spec.md` §4.2): **SPEAK** (general speaking window, multi-party round-robin), **REST**, **PAD**, **OPEN**.

### 3.4.1 Attributed Segments

A TX (or SPEAK) segment MAY carry two optional fields:

- `speaker` — the node id (e.g. `"N2"`) of the presenting node for this segment.
- `label` — a short agenda title for the segment (e.g. `"Mars Field Report"`).

Attribution is the foundation of Conference Mode (§14). When `speaker` is absent, the v1.0 behaviour applies (HOST presents in TX). Attribution does not change segment timing; it changes *who transmits* and how the segment is rendered from each viewer's perspective (§14.3).

## 3.5 Streams **(RESERVED)**

> **Status: SPECIFIED — NOT YET IMPLEMENTED.** No shipped implementation supports multiple streams. The concepts and identifiers below are reserved so that a future revision can implement them without a breaking spec change. Conference Mode (§14) deliberately uses attributed segments, not streams.

A Session may contain multiple streams:
- S0: Plenary (the implicit, and currently only, stream)
- S1..Sn: Branch streams (reserved)
- Merge stream (reserved)

The v3 plan field `streams[]` (§4.4) is reserved for this feature and MUST be absent or empty in current plans.

## 3.6 Session Modes

All LTX sessions declare a `mode` field in the SessionPlan. Three modes are defined.

> **Compatibility note:** Early implementations used `'LTX'` as the mode string for sequential turn-taking sessions. `'LTX'` is a **permanent** valid alias for `LTX-LIVE` and MUST be treated identically by all implementations. The planId hash includes the mode string verbatim; plans created with `mode: 'LTX'` retain that string and must not be silently migrated.

### LTX-LIVE

**Sequential turn-taking.** One node transmits while the other listens and waits. When the transmission arrives at the remote node (after one-way light-travel delay), the remote node may respond in its own TX window.

Structure: `PLAN_CONFIRM → TX → RX → [CAUCUS] → TX → RX → MERGE`

- TX and RX segments are **directional**: the HOST transmits in TX, participants respond in RX — unless the segment is attributed (§3.4.1), in which case the `speaker` node transmits.
- Suitable for lower-latency scenarios (Moon, near-Earth objects, Earth-to-Earth high-latency links).
- At Earth–Mars distances, each TX→RX→response cycle takes at minimum 2× the one-way delay (6–44 min). This is usable but slow.
- At distances beyond ~20 min one-way, LTX-ASYNC is strongly preferred.

### LTX-RELAY

**Store-and-forward relay.** Functionally identical to LTX-LIVE from a session-plan perspective, but transmissions are routed through a DTN relay server that holds and re-delivers each bundle after the configured one-way light-travel delay.

- Enables controlled testing and rehearsal without actual planetary distances.
- The relay introduces exactly the declared `ONEWAY-ASSUMED` delay before delivery.
- From the nodes' perspective, behaviour is indistinguishable from LTX-LIVE at the same delay.
- Relay configuration is carried in the plan's optional `relay` object (`spec/ltx-spec.md` §9) — the relay is not a node (§3.1).

### LTX-ASYNC

**Parallel broadcast.** All nodes transmit simultaneously during the TX segment. There is no sequential turn-taking: every node broadcasts its prepared content at the same UTC start time. Each node then enters the RX (watching/listening) segment, during which it watches/listens to the other parties' transmissions, which arrive after signal propagation delay.

Structure: `PLAN_CONFIRM → TX → RX → [CAUCUS] → TX → RX → MERGE`

Key properties:
- **TX segment** — All nodes broadcast simultaneously and independently. No node is "waiting" for another. From every node's perspective, they are presenting first.
- **RX segment** — All nodes watch/listen to the other parties' simultaneous broadcasts, arriving after the one-way light-travel delay.
- **No real-time response** is possible within a single TX/RX cycle. Responses are prepared and sent in the next TX window, after the content from the previous RX window has been reviewed.
- The concepts of "host presents, participant responds" do not apply in ASYNC. All parties present simultaneously; all parties review simultaneously.
- From any viewer's perspective, their own TX segment appears first (they transmitted at the start of the window, regardless of physical location).
- **Default mode** for all LTX sessions at delay > 120 s (including Earth–Mars). The ASYNC structure removes idle waiting time and maximises session efficiency.

Comparison of ASYNC vs LIVE at Earth–Mars (900 s one-way):
| Scenario | LTX-LIVE | LTX-ASYNC |
|---|---|---|
| Host presents 15 min | TX: 15 min | TX: 15 min (simultaneous both sides) |
| Participant receives | Waits 15 min for signal | Receives after 15 min delay |
| Participant responds | Waits 15 min more, then RX | Already received in RX window |
| Total dead time per cycle | 30+ min | 0 min (TX fills the delay window) |

## 3.7 Delay Model

### 3.7.1 v2: HOST-relative delays

In v2 plans, each node declares one number: `delay`, the one-way signal propagation delay in seconds **from HOST to that node**. The HOST's own `delay` is 0. This is the only delay information a v2 plan carries.

### 3.7.2 v3: pair-wise delay matrix

Distances between non-HOST bodies differ from their HOST-relative delays (Mars↔Jupiter ≠ Earth↔Mars + Earth↨Jupiter along the signal path). Conference sessions (§14) need true pair delays to compute when node V receives node S's attributed transmission.

v3 plans MAY carry an optional `delays` object:

```json
"delays": { "N0|N1": 860, "N0|N2": 2, "N1|N2": 890 }
```

- Keys are the two node ids joined by `|` in **lexicographically sorted order** (`"N1|N2"`, never `"N2|N1"`).
- Values are one-way delays in seconds; the matrix is symmetric by construction (one entry per unordered pair).
- When present for a pair, the matrix value is **authoritative**.

### 3.7.3 Fallback rule

Implementations MUST derive missing pair delays as follows:

```
pairDelay(HOST, x) = x.delay
pairDelay(a, b)    = delays["a|b"]            if present
                   = a.delay + b.delay        otherwise
```

The sum fallback is a deliberate **conservative upper bound** (triangle inequality via the HOST vertex): scheduling with an over-estimated delay is safe (content has certainly arrived); an under-estimate is not.

### 3.7.4 Delay bounds

Where delay variance matters (long sessions, moving spacecraft), the SessionPlan SHOULD size segments against the worst-case delay over the session duration (see §6.3). The declared value used for scheduling is referred to as `ONEWAY-ASSUMED` in ICS exports (`spec/ltx-spec.md` §8); v3 pair entries export as `LTX-DELAY;PAIR=` properties.

---

# 4. SessionPlan Specification

Each LTX session is governed by a canonical SessionPlan document (the **LtxPlan**). The normative wire format is `spec/ltx-spec.md`; this section defines the protocol-level rules.

## 4.1 v2 Schema (current, normative)

```json
{
  "v": 2,
  "title": "Earth-Mars Plenary Q1 Review",
  "start": "2026-03-15T14:00:00.000Z",
  "quantum": 3,
  "mode": "LTX-ASYNC",
  "nodes": [
    { "id": "N0", "name": "Earth HQ",    "role": "HOST",        "delay": 0,   "location": "earth" },
    { "id": "N1", "name": "Mars Hab-01", "role": "PARTICIPANT", "delay": 840, "location": "mars"  }
  ],
  "segments": [
    { "type": "PLAN_CONFIRM", "q": 2 },
    { "type": "TX", "q": 3, "speaker": "N0", "label": "Opening Address" },
    { "type": "RX", "q": 3 },
    { "type": "BUFFER", "q": 1 }
  ]
}
```

Required fields: `v`, `title`, `start` (ISO 8601 UTC), `quantum` (minutes), `mode`, `nodes[]` (HOST first), `segments[]`. Optional: `relay` (relay-mode config), and per-segment `speaker`/`label` (§3.4.1).

> **Withdrawn (v1.0 §4.1):** `planId`, `startEpochUTC`, `delayMatrix`, `streams[]`, `questions[]`, `actions[]` were listed as required fields in v1.0 but never shipped. The planId is *derived from* the plan (§4.3), not stored in it. `streams` remains reserved (§3.5). Pair delays, questions and actions return as **optional v3 fields** (§4.4).

## 4.2 Deterministic Canonicalisation

Two canonical byte encodings exist, used for different purposes:

1. **Legacy v2 planId bytes:** `JSON.stringify` of the upgraded config object, in insertion order. This is **order-sensitive** and exists only to keep v2 planIds stable (§4.3). It MUST NOT be used for signatures.
2. **Canonical JSON (RFC 8785 / JCS):** UTF-8, no whitespace, lexicographically sorted keys. Used for all signatures, Merkle leaves, amendment hashes (§6.4), and v3 planIds (§4.5). Full rules: LTX-SECURITY §16.

## 4.3 v2 planId **(FROZEN)**

```
planId = "LTX-" + YYYYMMDD(start)
       + "-" + HOSTSTR + "-" + NODESTR
       + "-v2-" + hex8( imul31(JSON.stringify(upgradedConfig)) )
```

where `imul31` is the 32-bit polynomial hash defined in `spec/ltx-spec.md` §7. This algorithm is **frozen byte-for-byte**: every shipped SDK, the demo, the relay server, and the conformance golden vectors depend on it.

Because `JSON.stringify` is insertion-order-sensitive, **adding any field to a v2 plan changes its planId**. Therefore:

- v3 fields MUST NOT be injected into an existing v2 plan object.
- Implementations MUST NOT auto-upgrade v2 plans to v3. Upgrading is an explicit, user-initiated operation (`upgradePlanToV3()`) that produces a **new plan** with a **new planId**.

## 4.4 v3 Schema (additive extension)

A v3 plan is a v2 plan with `v: 3` and any of the following **optional** fields:

| Field | Type | Purpose |
|---|---|---|
| `delays` | object | Pair-wise delay matrix (§3.7.2) |
| `planVersion` | integer ≥ 1 | Amendment counter (§6.4). Default 1. |
| `prevPlanHash` | hex string | SHA-256 (canonical JSON) of the predecessor plan in an amendment chain (§6.4). Absent on a root plan. |
| `questions[]` | array | Pre-polled question seeds (§9.2) |
| `actions[]` | array | Action register seeds (§10) |
| `streams[]` | array | **Reserved** (§3.5). MUST be absent or empty. |

All v2 semantics apply unchanged to v3 plans. A v3 plan with none of the optional fields is semantically identical to its v2 counterpart — but has a different planId, which is why auto-upgrade is forbidden.

## 4.5 v3 planId

```
planId = "LTX-" + YYYYMMDD(start)
       + "-" + HOSTSTR + "-" + NODESTR
       + "-v3-" + first8hex( SHA-256( canonicalJSON(plan) ) )
```

`HOSTSTR`/`NODESTR` are formed exactly as in v2. The hash input is the RFC 8785 canonical JSON of the full plan object — order-insensitive and cryptographically collision-resistant. The `-v3-` infix guarantees v2 and v3 planIds can never collide.

## 4.6 Schema ↔ code checklist

Normative sources of truth, in precedence order:
1. `spec/ltx-spec.md` + `spec/ltx-schema.json` (wire format)
2. Reference types: `typescript/ltx/src/types.ts` (`LtxPlan`, `LtxNode`, `SegmentTemplate`)
3. This document (protocol semantics)

A release MUST NOT ship with these three disagreeing on the plan schema.

---

# 5. Plan Lock Protocol

1. Each node computes the planId of the plan it holds.
2. Nodes exchange signed plan confirmations (planId + signature; LTX-SECURITY §7).
3. If all confirmations carry the identical planId → **LOCK**.
4. If planIds differ → deterministic resolution (§5.5).

Session begins only after lock (full or quorum, §5.6).

## 5.1 Plan-Lock Timeout

The recommended plan-lock timeout is **2× the one-way delay** from HOST to the furthest node, computed over the pair-delay model of §3.7 (for v2 plans this is 2× the largest `delay`). If an acknowledgement is not received within this window, the HOST SHOULD treat the lock as failed and MAY re-issue the plan. The 2× factor accounts for the round-trip signal path at the declared delay value.

Example: for an Earth–Mars session with a 900 s one-way delay, the recommended lock timeout is 1,800 s (30 minutes).

## 5.2 DEGRADED Session State

A session MUST enter DEGRADED state when any of the following conditions occur:

- (a) One or more nodes has not confirmed the plan within the plan-lock timeout (§5.1), or
- (b) A delay-matrix violation is detected (§5.4), or
- (c) Conflicting same-version signed plans are detected (§5.5 rule 3), or
- (d) The session proceeds with a quorum subset rather than full lock (§5.6).

In DEGRADED state:

- The session continues (it does not terminate automatically).
- All participants MUST be notified of the DEGRADED condition.
- Escalation to the HOST is required before proceeding to the TX window.
- The HOST MAY choose to continue with the confirmed subset of nodes or abort the session.
- The transition into and out of DEGRADED MUST be recorded as a `state_transition` entry in the audit log (LTX-SECURITY §9.5).

DEGRADED state is distinct from session termination. A session in DEGRADED state retains its SessionPlan and may recover if the missing node confirms before the TX window opens.

## 5.3 Sequential Fallback Ordering for Multi-Node Sessions

When a session has N > 2 nodes and cannot establish full consensus, the following fallback ordering defines which subset proceeds:

1. HOST node (always included if available).
2. PARTICIPANT nodes included in ascending order of their declared HOST-relative delay value (closest nodes first). OBSERVER nodes never count toward, nor block, consensus.

The session proceeds with the subset that achieved consensus. The HOST MUST log which nodes were excluded from the subset and notify all participants. A session proceeding with a reduced subset enters DEGRADED state.

## 5.4 Delay-Matrix Violation Rule

If a node's measured one-way delay deviates from the declared value (pair-delay model, §3.7) by more than **120 seconds (2 minutes)**:

- This constitutes a delay-matrix violation.
- The HOST MUST log the violation.
- The HOST MUST notify all participants of the violation and the measured vs. declared values.

If the deviation exceeds **300 seconds (5 minutes)**:

- The session MUST move to DEGRADED state.
- The HOST MUST determine whether to continue with adjusted delay parameters — via a plan amendment (§6.4) — or abort the session.

The 120-second threshold mirrors the design threshold of LTX itself (§1.1): a delay discrepancy that large represents a scheduling error equivalent to introducing a new communications boundary within the session.

## 5.5 Conflicting-Plan Resolution

> **Change from v1.0.** The v1.0 rule — "higher version wins; if equal, lexicographically higher hash wins" — is withdrawn. A hash tie-break is grindable: any party (including the legitimate HOST operator's tooling) can trivially mutate an immaterial field until its hash wins. Resolution is now bound to signatures and the amendment chain.

When nodes hold plans with differing planIds, resolution is deterministic:

1. **Amendment-chain precedence.** A plan with higher `planVersion` wins **iff** it carries a valid `prevPlanHash` chain (§6.4) terminating at the plan the local node last locked, and every link is HOST-signed. A higher `planVersion` without a verifiable chain is ignored (and logged — see LTX-SECURITY §4.2).
2. **HOST-signature precedence.** Between plans of equal `planVersion` (or v2 plans, which have no `planVersion`), the plan carrying a valid HOST signature (LTX-SECURITY §7) wins over any plan without one.
3. **Conflict = violation.** Two *distinct* plans of equal `planVersion`, both carrying valid HOST signatures, indicate HOST-key compromise or HOST error. Nodes MUST NOT pick one: the session enters DEGRADED state, a divergence entry is appended to the audit log, and the condition escalates to the HOST out-of-band.

All nodes applying these rules to the same evidence reach the same result, preserving the v1.0 goal of independent identical resolution.

## 5.6 Full Lock and Quorum Lock (N > 2)

- **FULL LOCK** — every PARTICIPANT node has confirmed the identical planId. This is the default requirement.
- **QUORUM-LOCK** — the HOST plus a configured threshold of PARTICIPANT confirmations. The threshold is declared in the session configuration (default: all participants; Conference Mode default: majority of PARTICIPANTs). The subset that proceeds is selected by §5.3 ordering. A quorum-locked session is DEGRADED (§5.2 d) until the remaining confirmations arrive.

OBSERVER nodes receive the plan but their confirmations are informational only.

---

# 6. Timing Model

## 6.1 Epoch Anchor
All segments are calculated from:
`start + Σ(previous segment durations)`, i.e. `start + n × quantum` boundaries.

## 6.2 Drift Handling

- Drift tolerance is configurable per session.
- If measured drift or delay deviation exceeds tolerance (§5.4 thresholds), the HOST proposes a **plan amendment** (§6.4) — typically appending or extending a BUFFER segment, or adjusting `delays`.
- Severe drift on a live link MAY be handled by re-issuing the remainder of the session as an LTX-RELAY amendment (rehearsal-grade fallback).

> **Change from v1.0:** "If exceeded → insert BUFFER window" is withdrawn as an in-place mutation. A locked plan is signed and immutable (LTX-SECURITY §7); any timing change is a new signed plan version (§6.4).

## 6.3 Variable Light-Time
SessionPlan must be sized against the worst-case one-way delay expected across the session duration. Segment sizing must accommodate this bound; the conservative pair-delay fallback (§3.7.3) errs in the same safe direction.

## 6.4 Plan Amendment Procedure

An amendment replaces a locked plan with a successor, without mutating any signed artefact:

1. HOST constructs the successor plan: a v3 plan (§4.4) with the desired changes, `planVersion` incremented by 1, and `prevPlanHash = SHA-256(canonicalJSON(predecessor plan))`.
2. HOST signs the successor (COSE envelope, LTX-SECURITY §7) and distributes it.
3. **Delta re-lock:** only nodes whose *remaining* segments change timing or attribution MUST re-confirm; the lock timeout is 2× the one-way delay to the furthest affected node. Unaffected nodes MAY continue on the amendment silently after verifying the chain.
4. Each node verifies: HOST signature, `planVersion` increment, and that `prevPlanHash` matches the plan it currently holds. On success it appends an `amendment` entry to its audit log and switches at the amendment boundary.

Amendment chains and freshness: the first (root) plan's planId remains the session identity (`sessionRootPlanId`) for sequence-number scoping (LTX-SECURITY §11), so amendments do not reset replay windows. Each amended plan additionally has its own v3 planId (§4.5).

Segments already executed are never amended; an amendment whose changes touch elapsed segments MUST be rejected.

---

# 7. Branching Model **(SPECIFIED — NOT YET IMPLEMENTED)**

> No shipped implementation supports branching. This section is retained as reserved design, with conformance identifiers reserved (`LTX-BRANCH-*`), so a future revision can implement it without a spec break. Conference Mode (§14) covers the current multi-party needs with attributed segments.

## 7.1 Local Breakout Mode
Nodes branch locally. Each branch produces artefacts. Summaries transmitted in next TX window. Merge occurs in Plenary.

## 7.2 Cross-Node Branch Mode
Branch streams span nodes. Each branch operates as independent LTX stream. Requires multiplexing policy.

## 7.3 Multiplexing
Time Division (recommended). Bandwidth Division (optional, higher complexity).

---

# 8. Merge and Conflict Resolution

The session record is the signed, append-only Merkle audit log defined in LTX-SECURITY §9. Questions (§9), actions (§10), decisions, amendments (§6.4) and state transitions (§5.2) are all entry types in that single log.

## 8.1 Append-Only Log
Entries are append-only. No in-place mutation during session. "Updating" an object (e.g. an action) means appending a new entry with a higher object `version` (§10.2).

## 8.2 Deterministic Merge

When two nodes hold divergent logs (partition, conjunction blackout, or parallel local recording), the merged log is computed identically by every node:

1. **Verify** every entry: signature (LTX-SECURITY §9.5), sequence freshness, and — where tree heads are available — inclusion/consistency proofs (LTX-SECURITY §9.3).
2. **Union** all verified entries, de-duplicated by `(nodeId, seq)`.
3. **Order** by `(timestamp, nodeId, seq)` ascending — a total order, since `(nodeId, seq)` is unique per entry.
4. **Reduce** registers from the ordered union (§9.4, §10.2). Object-level conflicts (two entries updating the same object at the same object version) resolve deterministically: **highest object version wins; at equal versions, the entry from the lexicographically lowest editor nodeId wins.** NodeIds are key-fingerprint-derived (LTX-SECURITY §5.1), so this order cannot be ground by an attacker. Losing entries remain in the log, flagged `superseded`, and are surfaced for explicit human review in the MERGE segment.

## 8.3 Partition Recovery
If link fails:
- Continue local logging.
- On reconnection, exchange signed tree heads; verify consistency proofs (LTX-SECURITY §9.4).
- If one log is a verified prefix of the other, accept the extension; otherwise apply §8.2 deterministic merge; if tree heads are inconsistent (divergent history over the *same* claimed entries), flag divergence, escalate to HOST, do not merge until resolved.

## 8.4 MERGE Segment Semantics
During a MERGE segment the HOST:
1. Runs the §8.2 merge over all logs received so far.
2. Appends a HOST-signed `merge_snapshot` entry recording the merged tree head and the resolved register states.
3. Presents flagged conflicts (§8.2 step 4) for explicit human resolution; resolutions are appended as ordinary register updates.

---

# 9. Question Management

## 9.1 Question Entries

Questions are audit-log entries (LTX-SECURITY §9.5) with `type: "question"` and entryId prefix `QST-`:

- `qid` (entryId), `text`, `submitter`, `urgency`, `intendedWindow`
- Responses are `type: "question_response"` entries referencing the `qid`.

Lifecycle (derived, never stored as mutable state): `OPEN → ANSWERED | WITHDRAWN`.

## 9.2 Pre-Polling
Questions ranked locally before session. Top-ranked questions are carried as v3 plan seeds (`questions[]`, §4.4) and are re-emitted as signed `question` log entries by their submitting nodes when the session locks — the plan seed is advisory; the log entry is the record.

## 9.3 Window Declaration
Each TX window declares:
- Agenda item (`label`, §3.4.1)
- QIDs addressed (window manifest, LTX-SECURITY §10.1)

## 9.4 Question Register Reduction
The question register is a pure function of the ordered log (§8.2): most-recent-by-version response state per qid. Implementations MUST produce identical register state from identical logs (this is a conformance requirement).

---

# 10. Action Register

## 10.1 Action Entries

Actions are audit-log entries with `type: "action"` (creation) and `type: "action_update"` (status/detail changes), entryId prefix `ACT-`:

- `aid` (entryId), `description`, `owner`, `dueTimeUTC`, `originWindow`
- Lifecycle (derived): `PROPOSED → ACCEPTED | REJECTED`, `ACCEPTED → DONE`.

## 10.2 Versioning
Updates create new `action_update` entries carrying an incremented object `version`. Entries are immutable once recorded; the current state of an action is the §8.2 reduction over its entries. High-stakes actions MAY require multi-person authorisation (LTX-SECURITY §19) before an `ACCEPTED` state is derived.

---

# 11. Media and Artefacts

## 11.1 Dual Representation Requirement
Each presentation must include:
- Low-resolution text version
- High-resolution media version

Low-resolution artefact is canonical for fallback.

## 11.2 Window Package
Each TX window produces:
- windowId
- media
- transcript
- slide state hash
- QIDs addressed

(Signed manifest format: LTX-SECURITY §10.1.)

## 11.3 Degraded Mode
If network degrades:
- Continue recording locally.
- Forward opportunistically.
- Remote may review asynchronously.

---

# 12. Timekeeper Wrapper Requirements

## 12.1 Deterministic Schedule Engine
- Runs locally
- Executes from SessionPlan
- Requires no live remote sync

## 12.2 Mandatory UI Elements
- Segment banner (with speaker attribution where present, §3.4.1)
- Countdown timer
- Next segment preview
- Plan Lock status (incl. DEGRADED indicator, §5.2)
- Drift indicator
- Recording indicator

## 12.3 Multi-Stream View **(RESERVED)**
Display active and pending streams — applies only once §7 is implemented.

---

# 13. Security and Integrity

## 13.1 Identity
Nodes and participants must possess cryptographic identity.

## 13.2 Artefact Integrity
All plans, logs, and media must be:
- Signed
- Hash-linked
- Immutable post-session

## 13.3 Emergency Override
Authorised control bundle may suspend or terminate session.

(Normative detail for this entire section: LTX-SECURITY.md v1.1 and Appendix A below.)

---

# 14. Conference Mode

Conference Mode structures multi-node sessions as an agenda of **attributed segments** (§3.4.1). It requires no new plan mechanics beyond v2 attribution and (optionally) the v3 pair-delay matrix — it is a usage profile with defined derivation rules, not a separate protocol.

## 14.1 Definitions

- **Conference session** — a session where TX segments carry `speaker` attribution and (typically) N > 2 nodes.
- **Block** — one presenting unit: an attributed TX segment, followed by the RX window(s) in which other nodes receive it, optionally followed by a CAUCUS.
- **Cycle** — one pass in which each participating node holds exactly one Block.

## 14.2 Agenda Structure

A conference agenda is an ordered list of Blocks. The canonical shape (normative example — the *Solar System Summit* template shipped in the demo):

```
PLAN_CONFIRM
TX  speaker=N0 label="Opening Address"
TX  speaker=N1 label="Mars Field Report"
TX  speaker=N2 label="Lunar Status Briefing"
TX  speaker=N3 label="Jupiter Observatory Report"
TX  speaker=N0 label="Synthesis & Close"
MERGE / BUFFER
```

In LTX-ASYNC conferences, attributed TX segments still start at their scheduled UTC times for the *speaker*; all other nodes' RX experience of that segment is derived per §14.3.

## 14.3 Viewer-Perspective Derivation

Every node renders the same plan from its own perspective. For a viewer node V and a segment attributed to speaker S starting at `segStart`:

```
arrival(V) = segStart + pairDelay(S, V)      // §3.7
```

- For V = S the segment is a transmit window at `segStart`.
- For V ≠ S the segment is a receive window beginning at `arrival(V)`.
- Unattributed segments retain their v1.0 semantics from every perspective.

Timekeeper UIs (§12.2) MUST render attributed segments from the local node's perspective ("You present" vs "Receiving from Mars Hab-01, arriving 12:43").

## 14.4 Prime-Time Fairness Rotation

Opening slots are the most valuable (freshest audience, best local time for the HOST region). Over a multi-cycle conference, fairness requires rotation: **across N cycles with N presenting nodes, each node holds the opening Block exactly once.** Agenda-builder implementations MUST provide a rotation mode implementing this invariant and SHOULD report per-node slot desirability so imbalances are visible when organisers deviate.

## 14.5 Per-Attendee Calendar Export

Conference ICS export MUST support a per-attendee form: for viewer V, each attributed segment exports as an event at `arrival(V)` (§14.3) in V's frame, with the speaker and label in the summary. Pair delays used for the derivation are exported as `LTX-DELAY;PAIR=` properties (`spec/ltx-spec.md` §8). The default (no-viewer) export remains the HOST-frame single-event form.

## 14.6 Topologies and Multi-Day Conferences

- Delay matrix maintained per node pair (§3.7.2); sessions divided into Blocks and Cycles (§14.1).
- Topologies supported: Hub-and-Spoke (HOST-mediated), Mesh (LTX-ASYNC broadcast), Relay chain (transport-level, §3.6 LTX-RELAY).
- Multi-day conferences are sequences of sessions sharing a key cache and (optionally) carried-over registers; each day is a separate plan with its own lock.

## 14.7 Not Streams

Conference Mode deliberately does **not** use the reserved streams mechanism (§3.5). Attributed segments keep the session single-streamed and fully deterministic from one plan document. Breakouts (parallel discussion) remain future work under §7.

---

# 15. Human Factors Requirements

- Window duration ≤ 20 minutes without break
- Defined roles:
  - Orchestrator
  - Stream Steward (reserved with §7)
  - Merge Steward
  - Recorder
- Summary-first speaking format
- Explicit restatement of decisions
- End-user UIs MUST NOT expose raw segment codes (TX/RX) without plain-language labels

---

# 16. Operational Modes

- LTX-Live
- LTX-Relay
- LTX-Async

Mode transitions logged and deterministic (`state_transition` entries, §5.2).

---

# 17. Validation Requirements

Before operational deployment:
- Delay simulation testing
- Partition testing (incl. §8.2 merge determinism across implementations)
- Drift fault injection (incl. §6.4 amendment round-trip)
- Plan-lock adversarial testing (§5.5 rules 1–3)
- Merge stress testing
- Human usability trials

Metrics:
- Decision latency
- Merge conflict rate
- Action accuracy
- Participant fatigue

---

# 18. Design Principles

1. Determinism over improvisation
2. Artefact-first communication
3. Append-only session state
4. Explicit merge resolution
5. Graceful degradation by default
6. Transport independence
7. Immutability: signed artefacts are never mutated — they are superseded (§6.4, §8.1)

---

# Appendix A. Security Considerations (Normative)

This appendix is normative. Implementations MUST comply with the security requirements defined here.

## A.1 Why Interactive Protocols Are Unsuitable

At Earth–Mars distances, a single TLS handshake round-trip takes between 6 and 44 minutes (2× one-way light-travel delay of 3–22 minutes). The following interactive security operations are therefore structurally infeasible for LTX sessions involving Mars or more distant nodes:

- TLS handshake (requires multiple round-trips)
- OAuth token fetch (requires HTTP redirect round-trip)
- Certificate Authority queries (require round-trip to CA server)
- OCSP certificate revocation checks (require round-trip to OCSP responder)

LTX security MUST be achieved through pre-positioned cryptographic material, not interactive protocols. All keys, certificates, and trust anchors MUST be in place at each node before the session commencement time.

## A.2 Pre-Positioned Key Model

All nodes MUST possess cryptographic identity keys before session commencement. Keys MUST NOT be fetched or negotiated during the session.

Keys are distributed via **KEY_BUNDLE messages** prior to the session start time, through a key distribution channel established during mission preparation (not during the live session). The timing of key distribution must account for the one-way light-travel delay to ensure all nodes have received and verified their key material before the plan-lock window opens.

Full key management specification: see docs/LTX-SECURITY.md.

## A.3 SessionPlan Signing

All SessionPlan objects MUST be signed using **COSE_Sign1** (RFC 9052) with the **Ed25519** signature algorithm (COSE algorithm ID -19, per RFC 9864).

- Plans without a valid HOST signature MUST be rejected by all nodes.
- Nodes MUST verify the HOST signature against the pre-positioned HOST public key before accepting any SessionPlan.
- A SessionPlan with a valid signature from a key that is not the pre-registered HOST key MUST be rejected.
- Amended plans (§6.4) MUST be re-signed; each link of an amendment chain is independently verifiable.

## A.4 Bundle Integrity

All LTX bundles transported via DTN relay MUST carry **BPSec Bundle Integrity Blocks** as defined in RFC 9172.

- Bundles without integrity blocks MUST be rejected.
- Bundles with integrity blocks that fail verification MUST be rejected and the failure logged.
- Relay infrastructure MUST NOT strip or modify integrity blocks.

## A.5 Sequence-Number Freshness

All LTX bundles MUST carry a **monotonically increasing sequence number** per sender node. The sequence number MUST be included in the bundle metadata and MUST be covered by the BPSec integrity block.

Receiving nodes MUST maintain a per-sender last-accepted sequence number. Bundles with a sequence number less than or equal to the last accepted value from that sender MUST be rejected as potential replay attacks. The rejection MUST be logged with the received and expected sequence numbers.

Sequence scope is the session root plan (§6.4): amendments do not reset freshness windows. Session-independent bundle types use the global scope rules of LTX-SECURITY §11.

## A.6 Threat Model

The following threats are considered in scope for this specification:

| # | Threat | Mitigation |
|---|---|---|
| 1 | Forged SessionPlan with inflated version number (causes nodes to accept attacker's plan over HOST plan) | COSE_Sign1 HOST signature required (§A.3); unsigned plans rejected; amendment-chain verification (§5.5) |
| 2 | Node impersonation via key substitution (attacker presents forged node identity) | Pre-positioned key model (§A.2); keys distributed before session, not during |
| 3 | Corrupted delay matrix causing scheduling errors (attacker modifies declared delay values) | SessionPlan signing covers node delays and the v3 `delays` matrix; violation detection (§5.4) |
| 4 | Replay attacks using captured bundles (attacker retransmits old valid bundles) | Monotonic sequence numbers per sender (§A.5); replays rejected; cross-session replay blocked by scope rules (LTX-SECURITY §11) |
| 5 | Plan-hash grinding to win conflict resolution | Hash tie-break withdrawn; resolution bound to signatures and amendment chains (§5.5) |

## A.7 Reference

Full security architecture specification: see **docs/LTX-SECURITY.md v1.1**

---

End of LTX v1.1 Specification
