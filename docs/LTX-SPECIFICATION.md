# LTX v1.0 Specification
## Light-Time eXchange (LTX)
### Distributed High-Latency Deliberation Protocol

---

# 1. Purpose

Light-Time eXchange (LTX) defines a deterministic, latency-aware meeting and conference protocol for human collaboration across spatially separated nodes where signal propagation delay prevents real-time conversational interaction.

LTX is transport-agnostic but designed to operate over Delay/Disruption Tolerant Networking systems (including HDTN).

LTX governs:
- Structured turn-taking
- Deterministic scheduling
- Branching and parallel streams
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
DTN / HDTN store-and-forward networking.

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
- **HOST** — The reference clock node. All timing and UTC anchoring is relative to the host. Signal delays are declared from host to each participant node. The host is typically (but not required to be) an Earth-based site.
- **PARTICIPANT** — A node that transmits and receives within the session plan.
- **RELAY** — A store-and-forward intermediary node. Does not participate directly but forwards bundles.
- **RECEIVE-ONLY** — A passive observer node. Receives all transmissions but does not transmit.

### Delay Matrix
For sessions with N > 2 nodes, a delay matrix records the one-way propagation delay from HOST to each participant node. Each HOST→NODE delay is declared independently, as distances between non-terrestrial bodies vary significantly and may differ between participants. The delay matrix is declared in the SessionPlan and in the iCalendar export (see RFC 5545 extension, §5.6 LTX-DELAY).

## 3.2 Quantum (Q)
Smallest scheduling unit.
Default: 5 minutes.
Configurable per session.

## 3.3 Window (W)
Contiguous set of quanta.
Example: W = 3Q = 15 minutes.

## 3.4 Segment Types
- TX – Node transmits presentation block
- RX – Node receives remote TX block
- CAUCUS – Local-only discussion
- BUFFER – Timing slack
- MERGE – Reintegration phase
- PLAN_CONFIRM – Initial handshake window

## 3.5 Streams
A Session may contain multiple streams:
- S0: Plenary
- S1..Sn: Branch streams
- Merge stream (optional)

Each stream executes deterministically from the SessionPlan.

---

# 4. SessionPlan Specification

Each LTX session is governed by a canonical SessionPlan document.

## 4.1 Required Fields
- planId
- version
- startEpochUTC
- quantum
- nodes[] — ordered list of participating nodes; first entry MUST be the HOST
  - Each entry: id, name, role (HOST | PARTICIPANT | RELAY | RECEIVE-ONLY), delay (seconds, from HOST; 0 for HOST node), location hint
- delayMatrix — per-node-pair one-way delay bounds (oneWayMin, oneWayMax, oneWayAssumed)
- streams[]
- questions[]
- actions[]

## 4.2 Deterministic Canonicalisation
- Canonical JSON format
- UTF-8 encoding
- Lexicographically sorted keys
- SHA-256 hash of canonical JSON forms PlanID suffix

---

# 5. Plan Lock Protocol

1. Each Node computes plan hash.
2. Nodes exchange planId values.
3. If identical → LOCK.
4. If mismatch → deterministic resolution:
   - Higher version wins.
   - If equal, lexicographically higher hash wins.

Both nodes independently reach identical resolution.
Session begins only after lock.

## 5.1 Plan-Lock Timeout

The recommended plan-lock timeout is **2× the one-way light-travel delay** from HOST to the furthest participant node. If an acknowledgement is not received within this window, the HOST SHOULD treat the lock as failed and MAY re-issue the plan. The 2× factor accounts for the round-trip signal path at the declared ONEWAY-ASSUMED delay value.

Example: for an Earth–Mars session with ONEWAY-ASSUMED = 900 s, the recommended lock timeout is 1,800 s (30 minutes).

## 5.2 DEGRADED Session State

A session MUST enter DEGRADED state when any of the following conditions occur:

- (a) One or more nodes has not confirmed the plan within the plan-lock timeout (§5.1), or
- (b) A delay-matrix violation is detected (§5.4).

In DEGRADED state:

- The session continues (it does not terminate automatically).
- All participants MUST be notified of the DEGRADED condition.
- Escalation to the HOST is required before proceeding to the TX window.
- The HOST MAY choose to continue with the confirmed subset of nodes or abort the session.

DEGRADED state is distinct from session termination. A session in DEGRADED state retains its SessionPlan and may recover if the missing node confirms before the TX window opens.

## 5.3 Sequential Fallback Ordering for Multi-Node Sessions

When a session has N > 2 nodes and cannot establish full consensus (i.e., full LOCK is not achieved), the following fallback ordering defines which subset proceeds:

1. HOST node (always included if available).
2. PARTICIPANT nodes included in ascending order of their declared ONEWAY-ASSUMED delay value (closest nodes first).

The session proceeds with the subset that achieved consensus. The HOST MUST log which nodes were excluded from the subset and notify all participants. A session proceeding with a reduced subset enters DEGRADED state.

## 5.4 Delay-Matrix Violation Rule

If a node's measured one-way delay deviates from the declared ONEWAY-ASSUMED delay by more than **120 seconds (2 minutes)**:

- This constitutes a delay-matrix violation.
- The HOST MUST log the violation.
- The HOST MUST notify all participants of the violation and the measured vs. declared values.

If the deviation exceeds **300 seconds (5 minutes)**:

- The session MUST move to DEGRADED state.
- The HOST MUST determine whether to continue with adjusted delay parameters or abort the session.

The 120-second threshold mirrors the design threshold of LTX itself (§1.1): a delay discrepancy that large represents a scheduling error equivalent to introducing a new communications boundary within the session.

---

# 6. Timing Model

## 6.1 Epoch Anchor
All segments are calculated from:
startEpochUTC + n × quantum

## 6.2 Drift Handling
- Drift tolerance configurable.
- If exceeded → insert BUFFER window.
- Severe drift → switch to RELAY mode.

## 6.3 Variable Light-Time
SessionPlan must include worst-case oneWayMax delay.
Segment sizing must accommodate this bound.

---

# 7. Branching Model

## 7.1 Local Breakout Mode
Nodes branch locally.
Each branch produces artefacts.
Summaries transmitted in next TX window.
Merge occurs in Plenary.

## 7.2 Cross-Node Branch Mode
Branch streams span nodes.
Each branch operates as independent LTX stream.
Requires multiplexing policy.

## 7.3 Multiplexing
Time Division (recommended)
Bandwidth Division (optional, higher complexity)

---

# 8. Merge and Conflict Resolution

## 8.1 Append-Only Log
Questions, actions, and decisions are append-only.
No in-place mutation during session.

## 8.2 Conflict Handling
Conflicting entries preserved and flagged.
Resolution occurs explicitly in MERGE segment.

## 8.3 Partition Recovery
If link fails:
- Continue local logging.
- Exchange logs when link restored.
- Deterministic merge.

---

# 9. Question Management

## 9.1 Question Object
- qid
- text
- submitter
- targetStream
- urgency
- intendedWindow

## 9.2 Pre-Polling
Questions ranked locally before session.
Top-ranked transmitted during PLAN_CONFIRM.

## 9.3 Window Declaration
Each TX window declares:
- Agenda item
- QIDs addressed

---

# 10. Action Register

## 10.1 Action Object
- aid
- description
- owner
- dueTimeUTC
- originStream

## 10.2 Versioning
Updates create new action entries.
Actions remain immutable once recorded.

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
- Segment banner
- Stream identifier
- Countdown timer
- Next segment preview
- Plan Lock status
- Drift indicator
- Recording indicator

## 12.3 Multi-Stream View
Display active and pending streams.

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

---

# 14. Conference Mode Extension

For multi-day or multi-node conferences:
- Streams become channels
- Delay matrix maintained per node pair
- Prime-time fairness rotation
- Session divided into Blocks composed of Cycles

Topologies supported:
- Hub-and-Spoke
- Mesh
- Relay chain

---

# 15. Human Factors Requirements

- Window duration ≤ 20 minutes without break
- Defined roles:
  - Orchestrator
  - Stream Steward
  - Merge Steward
  - Recorder
- Summary-first speaking format
- Explicit restatement of decisions

---

# 16. Operational Modes

- LTX-Live
- LTX-Relay
- LTX-Async

Mode transitions logged and deterministic.

---

# 17. Validation Requirements

Before operational deployment:
- Delay simulation testing
- Partition testing
- Drift fault injection
- Branch merge stress testing
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

## A.4 Bundle Integrity

All LTX bundles transported via DTN relay MUST carry **BPSec Bundle Integrity Blocks** as defined in RFC 9172.

- Bundles without integrity blocks MUST be rejected.
- Bundles with integrity blocks that fail verification MUST be rejected and the failure logged.
- Relay nodes (ROLE=RELAY) MUST NOT strip or modify integrity blocks.

## A.5 Sequence-Number Freshness

All LTX bundles MUST carry a **monotonically increasing sequence number** per sender node. The sequence number MUST be included in the bundle metadata and MUST be covered by the BPSec integrity block.

Receiving nodes MUST maintain a per-sender last-accepted sequence number. Bundles with a sequence number less than or equal to the last accepted value from that sender MUST be rejected as potential replay attacks. The rejection MUST be logged with the received and expected sequence numbers.

## A.6 Threat Model

The following threats are considered in scope for this specification:

| # | Threat | Mitigation |
|---|---|---|
| 1 | Forged SessionPlan with inflated version number (causes nodes to accept attacker's plan over HOST plan) | COSE_Sign1 HOST signature required (§A.3); unsigned plans rejected |
| 2 | Node impersonation via key substitution (attacker presents forged node identity) | Pre-positioned key model (§A.2); keys distributed before session, not during |
| 3 | Corrupted delay matrix causing scheduling errors (attacker modifies ONEWAY-ASSUMED values) | SessionPlan signing covers delay matrix; violation detection (§5.4) |
| 4 | Replay attacks using captured bundles (attacker retransmits old valid bundles) | Monotonic sequence numbers per sender (§A.5); replays rejected |

## A.7 Reference

Full security architecture specification: see **docs/LTX-SECURITY.md v1.0**

---

End of LTX v1.0 Specification
