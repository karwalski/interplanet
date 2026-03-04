# Internet-Draft: iCalendar Extensions for LTX and Interplanetary Scheduling

> **Note:** This document supersedes `ICS for LTX.md`. That file is retained as archive only.

```
Internet-Draft                                                    M. Watt
draft-interplanet-ltx-ical-ext-00                              InterPlanet
Intended status: Internet-Draft (Community Submission)         March 2026
Expires: September 2026
```

## Title

**iCalendar Extensions for Light-Time eXchange (LTX) and Non-Terrestrial Time Rendering**

---

## Abstract

This document specifies extensions to iCalendar (RFC 5545) to support deterministic scheduling and execution of high-latency, multi-node meetings using the Light-Time eXchange (LTX) meeting protocol. The extensions enable calendar-based distribution of LTX SessionPlan identifiers, deterministic segment timing, multi-stream (branch) structure, delay bounds, readiness checks, and non-terrestrial local time rendering metadata (for planets, moons, spacecraft, and stations). The extensions are defined as new iCalendar properties and parameters, with backward-compatible processing rules.

---

## Status of This Memo

This is an Internet-Draft submitted as a Community Submission. Internet-Drafts are working documents of the Internet Engineering Task Force (IETF). Note that other groups may also distribute working documents as Internet-Drafts.

Internet-Drafts are draft documents valid for a maximum of six months and may be updated, replaced, or obsoleted by other documents at any time. It is inappropriate to use Internet-Drafts as reference material or to cite them other than as "work in progress."

This Internet-Draft will expire in September 2026.

---

## Copyright Notice

Copyright (c) 2026 InterPlanet (Matthew Watt). All rights reserved.

---

## Table of Contents

1. Introduction
2. Conventions and Terminology
3. Design Goals
4. Processing Model
5. New iCalendar Properties (ABNF)
6. TEXT Property Value Escaping
7. New iCalendar Parameters
8. Non-Terrestrial Local Time Rendering
9. Attachments and Plan Integrity
10. Backward Compatibility
11. Security Considerations
12. IANA Considerations
13. References
14. Appendix A: Vendor Extension Notes
15. Appendix B: Implementation Notes

---

## 1. Introduction

RFC 5545 provides interoperability for calendaring and scheduling on Earth, with strong support for UTC, floating time, and local time rendered via VTIMEZONE. However, scheduling across spatially separated Nodes in deep space introduces constraints not addressed by RFC 5545:

* Signal propagation delay (one-way light time) exceeds real-time interaction tolerance.
* Delay is variable and MUST be accounted for when structuring meeting segments.
* Deterministic execution requires all Nodes to run an identical plan without real-time coordination.
* Non-terrestrial "local time" systems (e.g., on Mars or spacecraft mission time) are not representable via VTIMEZONE.

This document defines extensions to support:

* **LTX-compatible meeting invites** where VEVENT carries sufficient metadata for Nodes to deterministically execute a SessionPlan.
* **Non-terrestrial time rendering metadata** so clients can display Node-local meeting time consistently.

---

## 2. Conventions and Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 [RFC2119] and RFC 8174 [RFC8174] when, and only when, they appear in all capitals, as shown here.

### 2.1 Terms

* **Node**: A participating site (planetary base, station, spacecraft, Earth site) executing the same LTX plan.
* **Quantum (Q)**: Smallest timing unit for an LTX plan.
* **Window (W)**: A contiguous set of Quanta.
* **Segment**: An LTX phase (TX, RX, CAUCUS, BUFFER, MERGE, PLAN_CONFIRM).
* **Stream**: A logical channel of segments (Plenary or Branch) executed deterministically.
* **SessionPlan**: A canonical plan document describing streams, segments, and governance for an LTX session.

---

## 3. Design Goals

1. **Backward compatibility**: Existing RFC 5545 clients MUST continue to treat the event as a normal VEVENT.
2. **Determinism**: LTX-capable clients MUST be able to compute identical segment boundaries independently.
3. **Integrity**: Nodes MUST be able to verify they are executing the same plan.
4. **Multi-node readiness**: Nodes SHOULD be able to declare readiness pre-start and fall back gracefully.
5. **Non-terrestrial display**: Clients SHOULD be able to render Node-local meeting time without requiring VTIMEZONE.

---

## 4. Processing Model

### 4.1 Canonical Event Time

An LTX-enabled VEVENT:

* MUST include DTSTART and DTEND as UTC DATE-TIME values.
* MUST NOT use TZID on DTSTART/DTEND.

Rationale: UTC provides a single epoch anchor that all Nodes can use to compute plan timing.

### 4.2 LTX Capability Signalling

An iCalendar object containing an LTX session:

* MUST include the property **LTX** in the VEVENT.
* MUST include **LTX-PLANID**.

Clients that do not understand LTX properties:

* MUST ignore unknown properties as per RFC 5545 processing rules.

---

## 5. New iCalendar Properties (ABNF)

This section defines new iCalendar properties and their complete ABNF grammar [RFC5234]. All properties are to be registered with IANA under the RFC 5545 "Properties" registry (see Section 12).

The following ABNF uses productions defined in RFC 5545 Section 3.1 and RFC 5234.

```abnf
; ============================================================
; LTX — LTX session flag
; ============================================================
ltx-prop     = "LTX" ":" ltx-value CRLF
ltx-value    = "1"
               ; MUST be "1" for this specification

; ============================================================
; LTX-PLANID — session plan identifier
; ============================================================
ltx-planid   = "LTX-PLANID" ":" planid-value CRLF
planid-value = TEXT
               ; TEXT per RFC 5545 §3.3.11
               ; Typically of the form: LTX-{date}-{nodes}-v{n}-{hash}
               ; Example: LTX-20260227-EARTHHQ-MARSHAB-v2-7f9ca21b

; ============================================================
; LTX-QUANTUM — smallest scheduling unit (duration)
; ============================================================
ltx-quantum  = "LTX-QUANTUM" ":" dur-value CRLF
               ; dur-value per RFC 5545 §3.3.6 (DURATION)
               ; Example: PT5M  (five-minute quantum)
               ; Example: PT2M  (two-minute quantum)

; ============================================================
; LTX-DELAY — one-way signal delay declaration
; ============================================================
ltx-delay    = "LTX-DELAY" *(";" ltx-delay-param) ":" delay-value CRLF
ltx-delay-param = nodeid-param / iana-param
delay-value  = "ONEWAY-MIN=" integer
               ";" "ONEWAY-MAX=" integer
               [";" "ONEWAY-ASSUMED=" integer]
               [";" "JITTER-BUDGET=" integer]
               ; All values in seconds (INTEGER per RFC 5545 §3.3.8)
               ; A single LTX-DELAY without NODEID applies to all participants
               ; Multiple instances, each with NODEID, for multi-node sessions

; ============================================================
; LTX-NODE — participating node declaration
; ============================================================
ltx-node     = "LTX-NODE" ":" node-value CRLF
node-value   = "ID=" node-id
               ";" "ROLE=" node-role
               [";" "URI=" DQUOTE uri DQUOTE]
node-id      = TEXT         ; Opaque node identifier; TEXT-escaped
node-role    = "HOST" / "PARTICIPANT" / "RELAY" / "RECEIVE-ONLY"
uri          = <as defined in RFC 3986>

; ============================================================
; LTX-STREAM — stream identifier and label
; ============================================================
ltx-stream   = "LTX-STREAM" ":" stream-value CRLF
stream-value = "ID=" stream-id ";" "NAME=" TEXT
stream-id    = 1*ALPHA 1*DIGIT   ; e.g. S0, S1, S2

; ============================================================
; LTX-SEGMENT-TEMPLATE — ordered segment sequence
; ============================================================
ltx-seg-tpl  = "LTX-SEGMENT-TEMPLATE" ":" seg-tpl-value CRLF
seg-tpl-value = seg-token *("," seg-token)
seg-token    = "TX" / "RX" / "CAUCUS" / "BUFFER" / "MERGE" / "PLAN_CONFIRM"
               ; Commas within TEXT values MUST be escaped as \,
               ; (see Section 6)
```

### 5.1 LTX Property

**Property Name:** LTX
**Purpose:** Declares that the VEVENT is an LTX session.
**Value Type:** TEXT
**Conformance:** VEVENT; REQUIRED for LTX sessions.

The value MUST be "1" for this specification.

Example:

```
LTX:1
```

### 5.2 LTX-PLANID Property

**Property Name:** LTX-PLANID
**Purpose:** Identifies the canonical LTX SessionPlan by opaque identifier, typically including a cryptographic hash.
**Value Type:** TEXT
**Conformance:** VEVENT; REQUIRED.

Example:

```
LTX-PLANID:LTX-20260227-EARTH-MARS-v1-7f9c...a21
```

### 5.3 LTX-QUANTUM Property

**Property Name:** LTX-QUANTUM
**Purpose:** Declares the LTX Quantum (smallest scheduling unit).
**Value Type:** DURATION (RFC 5545 §3.3.6)
**Conformance:** VEVENT; REQUIRED.

Example:

```
LTX-QUANTUM:PT5M
```

### 5.4 LTX-DELAY Property

**Property Name:** LTX-DELAY
**Purpose:** Declares one-way signal delay bounds between the HOST node and a participant node.
**Value Type:** TEXT (semicolon-separated key=value pairs)
**Conformance:** VEVENT; REQUIRED; MAY appear multiple times — once per non-HOST node.

The value MUST include ONEWAY-MIN and ONEWAY-MAX in seconds. MAY include ONEWAY-ASSUMED and JITTER-BUDGET.

When multiple nodes are present, each LTX-DELAY instance SHOULD carry a NODEID parameter identifying the participant node it applies to. A single LTX-DELAY without a NODEID parameter applies to all participant nodes (two-node sessions).

Examples:

```
LTX-DELAY:ONEWAY-MIN=600;ONEWAY-MAX=1500;ONEWAY-ASSUMED=900;JITTER-BUDGET=60

LTX-DELAY;NODEID=MARS-HAB-01:ONEWAY-MIN=600;ONEWAY-MAX=1500;ONEWAY-ASSUMED=900
LTX-DELAY;NODEID=LUNA-BASE:ONEWAY-MIN=1;ONEWAY-MAX=2;ONEWAY-ASSUMED=1
```

### 5.5 LTX-NODE Property

**Property Name:** LTX-NODE
**Purpose:** Declares a participating Node and its role.
**Value Type:** TEXT (semicolon-separated: nodeId;role;name)
**Conformance:** VEVENT; REQUIRED; MAY appear multiple times.

The value MUST include ID and ROLE. MAY include URI for control endpoints.

Roles: HOST, PARTICIPANT, RELAY, RECEIVE-ONLY.

Example:

```
LTX-NODE:ID=EARTH-HQ;ROLE=HOST
LTX-NODE:ID=MARS-HAB-01;ROLE=PARTICIPANT
```

### 5.6 LTX-STREAM Property

**Property Name:** LTX-STREAM
**Purpose:** Declares stream identifiers and human-readable labels.
**Value Type:** TEXT (semicolon-separated list)
**Conformance:** VEVENT; OPTIONAL; MAY appear multiple times.

Example:

```
LTX-STREAM:ID=S0;NAME=Plenary
LTX-STREAM:ID=S1;NAME=Technical
LTX-STREAM:ID=S2;NAME=Strategic
```

### 5.7 LTX-SEGMENT-TEMPLATE Property

**Property Name:** LTX-SEGMENT-TEMPLATE
**Purpose:** Declares a default ordered sequence of segments for the primary stream.
**Value Type:** TEXT (semicolon-separated list)
**Conformance:** VEVENT; REQUIRED.

The value MUST be a comma-separated list of segment tokens. Tokens MUST be one of: TX, RX, CAUCUS, BUFFER, MERGE, PLAN_CONFIRM. Literal commas within token values MUST be escaped as `\,` (see Section 6).

Example:

```
LTX-SEGMENT-TEMPLATE:PLAN_CONFIRM,TX,RX,CAUCUS,TX,RX,MERGE,BUFFER
```

### 5.8 LTX-MODE Property

**Property Name:** LTX-MODE
**Purpose:** Declares LTX operational mode.
**Value Type:** TEXT
**Conformance:** VEVENT; REQUIRED.

Allowed values: LTX-LIVE, LTX-RELAY, LTX-ASYNC.

Example:

```
LTX-MODE:LTX-LIVE
```

### 5.9 LTX-MUX Property

**Property Name:** LTX-MUX
**Purpose:** Declares multiplexing policy for multi-stream sessions.
**Value Type:** TEXT
**Conformance:** VEVENT; OPTIONAL.

Allowed values: TIME-DIVISION, BANDWIDTH-DIVISION.

Example:

```
LTX-MUX:TIME-DIVISION
```

### 5.10 LTX-READINESS Property

**Property Name:** LTX-READINESS
**Purpose:** Declares readiness requirements and fallback behaviour.
**Value Type:** TEXT
**Conformance:** VEVENT; OPTIONAL.

Parameters: CHECK (DURATION), REQUIRED (BOOLEAN), FALLBACK (TEXT).

Example:

```
LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY
```

---

## 6. TEXT Property Value Escaping

All LTX property values of type TEXT MUST follow the RFC 5545 §3.3.11 TEXT escaping rules. The following characters MUST be escaped when they appear in TEXT property values:

| Character | Escaped form |
|---|---|
| Comma (`,`) | `\,` |
| Semicolon (`;`) | `\;` |
| Backslash (`\`) | `\\` |
| Newline (LF or CRLF) | `\n` |

Note that the semicolon (`;`) is used as a key=value delimiter within LTX property values (e.g., LTX-DELAY, LTX-NODE). Literal semicolons appearing within key values or text content MUST be escaped as `\;` to distinguish them from the delimiter. Implementations producing LTX properties MUST apply this escaping. Implementations consuming LTX properties MUST unescape these sequences before processing the value content.

---

## 7. New iCalendar Parameters

This section defines new property parameters to be registered with IANA under the RFC 5545 "Parameters" registry.

### 7.1 NODEID Parameter

**Parameter Name:** NODEID
**Purpose:** Associates a property instance with a specific Node.

Conformance: MAY be applied to LTX-* properties.

Example:

```
LTX-READINESS;NODEID=MARS-HAB-01:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-ASYNC
```

### 7.2 LOCALEPOCH Parameter

**Parameter Name:** LOCALEPOCH
**Purpose:** Declares the epoch reference used for local-time rendering metadata.

The value MUST be UTC DATE-TIME.

Example:

```
LTX-NODE;LOCALEPOCH=20260227T000000Z:ID=MARS-HAB-01;ROLE=PARTICIPANT
```

---

## 8. Non-Terrestrial Local Time Rendering

RFC 5545 local time rendering relies on VTIMEZONE. For non-terrestrial Nodes, clients require a rendering scheme that does not depend on the IANA tzdata database.

### 8.1 LTX-LOCALTIME Property

**Property Name:** LTX-LOCALTIME
**Purpose:** Provides metadata for rendering Node-local meeting time.
**Value Type:** TEXT
**Conformance:** VEVENT; OPTIONAL; MAY appear multiple times.

The value MUST include NODE and SCHEME. MAY include PARAMS.

Clients MUST treat DTSTART/DTEND as canonical. Clients SHOULD display a Node-local time label derived from LTX-LOCALTIME when supported.

Example:

```
LTX-LOCALTIME:NODE=MARS-HAB-01;SCHEME=LMST;PARAMS=LONGITUDE:137.4E
LTX-LOCALTIME:NODE=SHIP-A;SCHEME=MISSION-TIME;PARAMS=T0:20260101T000000Z
```

---

## 9. Attachments and Plan Integrity

LTX plans are commonly distributed as attachments.

Implementations SHOULD include a SessionPlan JSON as an ATTACH. Implementations SHOULD include a low-resolution agenda artifact as an ATTACH.

### 9.1 LTX-ATTACH-HASH Property

**Property Name:** LTX-ATTACH-HASH
**Purpose:** Provides integrity hashes for referenced attachments.
**Value Type:** TEXT
**Conformance:** VEVENT; OPTIONAL; MAY appear multiple times.

Example:

```
LTX-ATTACH-HASH:URI=cid:sessionplan.json;ALG=SHA-256;DIGEST=...
```

---

## 10. Backward Compatibility

Non-LTX clients:

* MUST interpret the VEVENT using DTSTART/DTEND and standard RFC 5545 properties.
* MUST ignore unknown LTX properties.

LTX-capable clients:

* MUST treat DTSTART/DTEND UTC as the epoch anchor.
* MUST NOT reinterpret DTSTART/DTEND using LTX-LOCALTIME.
* SHOULD present additional Node-local renderings as informational only.

---

## 11. Security Considerations

LTX introduces operational reliance on plan integrity. LTX properties may carry session identifiers (LTX-PLANID) and node identifiers (LTX-NODE ID fields) that SHOULD be treated as potentially sensitive metadata. These identifiers may reveal information about mission participants, base locations, and session timing to unintended recipients. Implementations SHOULD apply end-to-end encryption to iCalendar objects containing LTX properties when transmitted over untrusted channels.

Implementations:

* MUST support cryptographic integrity verification of SessionPlan identifiers.
* SHOULD support signed attachments and signed event logs.
* SHOULD support end-to-end encryption for transport of the iCalendar object and attachments.

If readiness or control endpoints are included:

* Implementations MUST authenticate Nodes.
* Implementations MUST restrict emergency override mechanisms to authorised principals.

---

## 12. IANA Considerations

IANA is requested to register the following new iCalendar properties in the registry defined by RFC 5545, using the registration template format specified in RFC 5545 Section 8.2.3.

### 12.1 LTX Property Registration

```
Property name:     LTX
Purpose:           Declares an LTX session
Value type:        TEXT
Property encoding: 8BIT
Property value:    "1"
Conformance:       VEVENT
Description:       Signals that the VEVENT is an LTX session.
Reference:         draft-interplanet-ltx-ical-ext-00, Section 5.1
```

### 12.2 LTX-PLANID Property Registration

```
Property name:     LTX-PLANID
Purpose:           Identifies the canonical LTX SessionPlan
Value type:        TEXT
Property encoding: 8BIT
Conformance:       VEVENT
Description:       Opaque identifier for the SessionPlan document,
                   typically including a cryptographic hash suffix.
Reference:         draft-interplanet-ltx-ical-ext-00, Section 5.2
```

### 12.3 LTX-QUANTUM Property Registration

```
Property name:     LTX-QUANTUM
Purpose:           Declares the minimum scheduling unit
Value type:        DURATION
Property encoding: 8BIT
Conformance:       VEVENT
Description:       Declares the quantum (Q) for session timing.
Reference:         draft-interplanet-ltx-ical-ext-00, Section 5.3
```

### 12.4 LTX-DELAY Property Registration

```
Property name:     LTX-DELAY
Purpose:           Declares one-way signal delay bounds
Value type:        TEXT (semicolon-separated key=value pairs)
Property encoding: 8BIT
Conformance:       VEVENT; MAY appear multiple times
Description:       Declares ONEWAY-MIN, ONEWAY-MAX, and optionally
                   ONEWAY-ASSUMED and JITTER-BUDGET in seconds.
Reference:         draft-interplanet-ltx-ical-ext-00, Section 5.4
```

### 12.5 LTX-NODE Property Registration

```
Property name:     LTX-NODE
Purpose:           Declares a participating node and its role
Value type:        TEXT (semicolon-separated: ID=..;ROLE=..)
Property encoding: 8BIT
Conformance:       VEVENT; MAY appear multiple times
Description:       Declares node identity, role (HOST/PARTICIPANT/
                   RELAY/RECEIVE-ONLY), and optional URI.
Reference:         draft-interplanet-ltx-ical-ext-00, Section 5.5
```

### 12.6 LTX-STREAM Property Registration

```
Property name:     LTX-STREAM
Purpose:           Declares a stream identifier and label
Value type:        TEXT (semicolon-separated list)
Property encoding: 8BIT
Conformance:       VEVENT; OPTIONAL; MAY appear multiple times
Reference:         draft-interplanet-ltx-ical-ext-00, Section 5.6
```

### 12.7 LTX-SEGMENT-TEMPLATE Property Registration

```
Property name:     LTX-SEGMENT-TEMPLATE
Purpose:           Declares the ordered default segment sequence
Value type:        TEXT (semicolon-separated list of segment tokens)
Property encoding: 8BIT
Conformance:       VEVENT; REQUIRED
Description:       Comma-separated list of segment type tokens.
Reference:         draft-interplanet-ltx-ical-ext-00, Section 5.7
```

Additional properties (LTX-MODE, LTX-MUX, LTX-READINESS, LTX-LOCALTIME, LTX-ATTACH-HASH) follow the same registration template structure and are to be registered under the same RFC 5545 Properties registry.

IANA is also requested to register the following iCalendar parameters under the RFC 5545 Parameters registry:

* NODEID (Section 7.1)
* LOCALEPOCH (Section 7.2)

---

## 13. References

### 13.1 Normative References

* [RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", BCP 14, RFC 2119, March 1997.
* [RFC5234] Crocker, D. and P. Overell, "Augmented BNF for Syntax Specifications: ABNF", STD 68, RFC 5234, January 2008.
* [RFC5545] Desruisseaux, B., Ed., "Internet Calendaring and Scheduling Core Object Specification (iCalendar)", RFC 5545, September 2009.
* [RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", BCP 14, RFC 8174, May 2017.

### 13.2 Informative References

* [LTX-SPEC] Watt, M., "LTX v1.0 Specification — Light-Time eXchange Distributed High-Latency Deliberation Protocol", InterPlanet project, 2026. (docs/LTX-SPECIFICATION.md)
* [DRAFT-STANDARD] Watt, M., "Interplanetary Timezone Conventions for Human Work Scheduling", InterPlanet community specification, February 2026. (docs/DRAFT-STANDARD.md)

---

## Appendix A: Vendor Extension Notes

RFC 5545 permits vendor extensions via X- properties. This document standardises a minimal set of LTX properties and parameters to enable interoperable scheduling of deterministic high-latency sessions.

The canonical property names in this document (e.g., `LTX-PLANID`, `LTX-DELAY`) omit the `X-` prefix because this document registers them with IANA as standardised properties. During prototyping and pre-standard implementations, the same properties may appear with the `X-` prefix (e.g., `X-LTX-PLANID`, `X-LTX-DELAY`) in accordance with RFC 5545 Section 3.8.8.2 vendor extension rules. Implementations SHOULD accept both forms during a transition period. Once IANA registration is complete, the `X-`-prefixed forms are deprecated.

---

## Appendix B: Implementation Notes

### B.1 HOST Node as Reference Clock Anchor

The first declared `LTX-NODE` with `ROLE=HOST` is always the reference clock anchor for all timing computations. All one-way delays are declared relative to the HOST. The HOST is typically an Earth-based site (e.g., mission control) but MAY be any node elected to serve as the reference. Additional nodes carry the roles PARTICIPANT, RELAY, or RECEIVE-ONLY.

### B.2 Canonical UTC vs. Multiple-VEVENT Patterns

Two patterns were considered during design:

**Pattern A (adopted — canonical UTC + derived local displays)**

Use `DTSTART`/`DTEND` in UTC as the canonical epoch anchor, and add LTX metadata to compute local displays per node. This is the approach specified in this document.

**Pattern B (not adopted — multiple VEVENTs)**

One canonical VEVENT in UTC, plus additional VEVENTs per node as "mirrors" for local systems. This pattern is backward-compatible with existing calendar applications but introduces synchronisation risk and is not deterministic across nodes. Pattern B is NOT RECOMMENDED.

### B.3 Timescale Declaration

In implementations using vendor-extension (`X-`) syntax, an explicit timescale declaration property was used:

```
X-LTX-TIMESCALE:UTC
```

Under this specification, the requirement that `DTSTART`/`DTEND` be UTC (Section 4.1) makes this property redundant. It is listed here for implementors reading pre-standard artefacts.

### B.4 Ephemeris Reference

Pre-standard implementations included an ephemeris reference property:

```
X-LTX-EPHEMERIS-REF:SPICE-kernels:<id>
X-LTX-EPHEMERIS-REF:Mars24-algorithm:<version>
```

This metadata is not yet formalised in the property registry. Implementors requiring ephemeris provenance SHOULD include this as a free-form parameter on the `LTX-LOCALTIME` property (e.g., `PARAMS=ALGORITHM:Mars24-v2`) until a dedicated property is standardised.

### B.5 Hard-Stop and End-Buffer Properties

Pre-standard implementations used:

```
X-LTX-HARDSTOP:20260227T013000Z
X-LTX-BUFFER:PT5M
```

The hard-stop time is captured by `DTEND` in standard practice. A separate `LTX-BUFFER` property for trailing buffer declaration is under consideration for a future revision.

### B.6 Stream Allocation and Merge Windows

Pre-standard implementations used:

```
X-LTX-MUX-ALLOCATION:S1=PT10M,S2=PT10M
X-LTX-MERGE-WINDOWS:S0@T+PT60M,S0@T+PT90M
```

Both are candidates for inclusion in a future revision alongside `LTX-MUX`.

### B.7 Question Polling Properties

Pre-standard implementations included:

```
X-LTX-QPOLL-OPEN:20260226T120000Z
X-LTX-QPOLL-CLOSE:20260227T000000Z
X-LTX-QBOARD-URI:<URI>
X-LTX-QID-SCHEME:UUID
```

These are candidates for a future revision.

### B.8 Pragmatic Minimum Set for LTX Compatibility

For implementors needing a baseline before full adoption of this specification, the following properties constitute the minimum LTX-compatible VEVENT:

1. `DTSTART`/`DTEND` in UTC as the canonical epoch
2. `LTX-PLANID` and an `ATTACH` pointing to the SessionPlan JSON
3. `LTX-QUANTUM`, `LTX-SEGMENT-TEMPLATE`
4. `LTX-DELAY` (with ONEWAY-MIN and ONEWAY-MAX at minimum)
5. At least one `LTX-NODE` with `ROLE=HOST`
6. `LTX-MODE` and a `FALLBACK` value in `LTX-READINESS`

### B.9 Example VEVENTs

**Two-node (Earth and Mars)**

```
BEGIN:VEVENT
UID:ltx-demo-001@example
DTSTAMP:20260226T230000Z
DTSTART:20260227T000000Z
DTEND:20260227T013000Z
SUMMARY:LTX Plenary — Earth HQ / Mars Hab-01
LTX:1
LTX-PLANID:LTX-20260227-EARTHHQ-MARSHAB-v2-7f9ca21b
LTX-QUANTUM:PT5M
LTX-SEGMENT-TEMPLATE:PLAN_CONFIRM,TX,RX,CAUCUS,TX,RX,MERGE,BUFFER
LTX-MODE:LTX-LIVE
LTX-NODE:ID=EARTH-HQ;ROLE=HOST
LTX-NODE:ID=MARS-HAB-01;ROLE=PARTICIPANT
LTX-DELAY;NODEID=MARS-HAB-01:ONEWAY-MIN=600;ONEWAY-MAX=1500;ONEWAY-ASSUMED=900
LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY
LTX-LOCALTIME:NODE=MARS-HAB-01;SCHEME=LMST;PARAMS=LONGITUDE:137.4E
END:VEVENT
```

**Multi-node (Earth host + Mars + Moon)**

```
BEGIN:VEVENT
UID:ltx-demo-002@example
DTSTAMP:20260226T230000Z
DTSTART:20260227T000000Z
DTEND:20260227T020000Z
SUMMARY:Interplanetary Plenary — Earth\, Mars\, Moon
LTX:1
LTX-PLANID:LTX-20260227-EARTHHQ-MARS-LUNA-v2-3c4d8e9f
LTX-QUANTUM:PT5M
LTX-SEGMENT-TEMPLATE:PLAN_CONFIRM,TX,RX,CAUCUS,TX,RX,MERGE,BUFFER
LTX-MODE:LTX-LIVE
LTX-NODE:ID=EARTH-HQ;ROLE=HOST
LTX-NODE:ID=MARS-HAB-01;ROLE=PARTICIPANT
LTX-NODE:ID=LUNA-BASE;ROLE=PARTICIPANT
LTX-DELAY;NODEID=MARS-HAB-01:ONEWAY-MIN=600;ONEWAY-MAX=1500;ONEWAY-ASSUMED=900
LTX-DELAY;NODEID=LUNA-BASE:ONEWAY-MIN=1;ONEWAY-MAX=2;ONEWAY-ASSUMED=1
LTX-STREAM:ID=S0;NAME=Plenary
LTX-STREAM:ID=S1;NAME=Technical
LTX-MUX:TIME-DIVISION
LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY
LTX-LOCALTIME:NODE=MARS-HAB-01;SCHEME=LMST;PARAMS=LONGITUDE:137.4E
END:VEVENT
```

---

End of Internet-Draft `draft-interplanet-ltx-ical-ext-00`
