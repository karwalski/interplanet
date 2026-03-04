# LTX Security Architecture

**Document status:** v1.0
**Companion to:** LTX-SPECIFICATION.md v1.0
**Classification:** Documentation artefact — reviewed before code implementation
**Keywords:** LTX, interplanetary communication, BPSec, DTKA, COSE, Ed25519,
delay-tolerant networking, session security, zero-interactive cryptography

---

## Abstract

The Light-Time eXchange (LTX) protocol operates in an environment where all
interactive cryptographic protocols — TLS, IKEv2, OAuth, certificate authority
queries — are structurally infeasible. At Earth–Mars distances, a single round
trip takes 6 to 44 minutes. No handshake can complete; no certificate can be
fetched on demand; no revocation check can be performed in real time.

This document specifies the security architecture for LTX sessions, grounded in
the Delay-Tolerant Networking (DTN) security ecosystem: BPSec (RFC 9172), the
Delay-Tolerant Key Administration (DTKA) model, COSE (RFC 9052, RFC 9053,
RFC 9864), and the BPSec COSE security context (`draft-ietf-dtn-bpsec-cose`).
All cryptographic material is pre-positioned, not negotiated. All artefacts are
signed at creation and verified at receipt. All session state is maintained in
a Merkle-tree audit log for efficient partition recovery.

This document is intended for review and research validation before any
implementation work begins. Decisions about SDK-level changes will be made
following review.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Terminology](#2-terminology)
3. [Fundamental Constraints](#3-fundamental-constraints)
4. [Threat Model](#4-threat-model)
5. [Cryptographic Identity](#5-cryptographic-identity)
6. [Key Management](#6-key-management)
7. [SessionPlan Signing — COSE Envelope](#7-sessionplan-signing--cose-envelope)
8. [Bundle Integrity — BPSec BIBs](#8-bundle-integrity--bpsec-bibs)
9. [Merkle-Tree Audit Log](#9-merkle-tree-audit-log)
10. [Per-Window Artefact Integrity](#10-per-window-artefact-integrity)
11. [Freshness Markers](#11-freshness-markers)
12. [Confidentiality (Optional)](#12-confidentiality-optional)
13. [Emergency Override Security](#13-emergency-override-security)
14. [Session-Level Security Associations — BP-SAFE](#14-session-level-security-associations--bp-safe)
15. [iCalendar Distribution Security](#15-icalendar-distribution-security)
16. [Canonical JSON Specification](#16-canonical-json-specification)
17. [Library Integrity — planet-time.js and Ports](#17-library-integrity--planet-timejs-and-ports)
18. [Conjunction-Safe Security Checkpoints](#18-conjunction-safe-security-checkpoints)
19. [Multi-Person Authorisation](#19-multi-person-authorisation)
20. [Post-Quantum Readiness](#20-post-quantum-readiness)
21. [Formal Analysis and Verification Gap](#21-formal-analysis-and-verification-gap)
22. [Security Test Plan](#22-security-test-plan)
23. [Priority Summary and Implementation Roadmap](#23-priority-summary-and-implementation-roadmap)
24. [Security Considerations for This Document](#24-security-considerations-for-this-document)
25. [References](#25-references)

---

## 1. Introduction

LTX-SPECIFICATION.md §13 states:

> "Nodes and participants must possess cryptographic identity. All plans, logs,
> and media artefacts must be signed, hash-linked, and immutable."

This document fulfils that requirement. It defines *how* nodes possess cryptographic
identity, *how* artefacts are signed, and *how* integrity is maintained across
store-and-forward relay hops, conjunction blackouts, and adversarial environments.

### 1.1 Scope

This document covers:

- Cryptographic identity for nodes
- Pre-session key distribution
- SessionPlan signing and verification
- Bundle Payload Integrity (BPSec BIB)
- Merkle-tree audit log for efficient partition recovery
- Per-window artefact signing
- Freshness and anti-replay
- Optional session confidentiality
- Emergency override authentication
- Canonical JSON specification
- iCalendar event security
- Library supply-chain integrity
- Conjunction-safe security checkpoints
- Post-quantum readiness roadmap
- Formal analysis gap

This document does not cover:

- Physical security of ground stations or spacecraft
- Side-channel attacks beyond those noted in §5
- Transport-layer security for Earth-based segments (use standard TLS)
- Key ceremony procedures (out of scope; future work)

### 1.2 Requirements Language

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
RECOMMENDED, MAY, and OPTIONAL in this document are to be interpreted as described
in BCP 14 (RFC 2119, RFC 8174).

### 1.3 Relationship to LTX-SPECIFICATION.md

This document is normative where it conflicts with the brief security requirements
in LTX-SPECIFICATION.md §13. All other sections of LTX-SPECIFICATION.md remain
authoritative.

---

## 2. Terminology

**BIB** — Bundle Integrity Block (BPSec, RFC 9172 §3.7). A security block that
provides cryptographic integrity assurance for a target block within a DTN bundle.

**BPSec** — Bundle Protocol Security (RFC 9172). The security framework for DTN
Bundle Protocol v7 (RFC 9171). Defines BCBs and BIBs.

**BCB** — Bundle Confidentiality Block (BPSec, RFC 9172 §3.8). A security block
that provides encryption of a target block within a DTN bundle.

**BP-SAFE** — Bundle Protocol Security Associations with Few Exchanges
(`draft-sipos-dtn-bp-safe-00`). An individual submission by Brian Sipos (June 2025,
expired December 2025). NOT an adopted IETF working group document. Its purpose —
negotiating scoped security associations — remains important, but no standardised
alternative exists yet. See §14.

**BPSec COSE Context** — `draft-ietf-dtn-bpsec-cose`. At version -15 (March 2026),
authored by Brian Sipos. WG state: "Consensus: Waiting for Write-Up." Defines
Security Context ID 3 (unified COSE-based context for both BIB and BCB). As of v15,
EdDSA (-19) is permitted but has been removed from the mandatory interoperability
profile; the mandatory profile uses ES-P384 (-51) / ES-P512 (-52) for ECC integrity
and A256GCM for confidentiality, aligned with CNSA 1.0/2.0.

**CCSDS** — Consultative Committee for Space Data Systems.

**COSE** — CBOR Object Signing and Encryption (RFC 9052). A compact signing and
encryption format based on CBOR (RFC 8949). Algorithm IDs assigned in RFC 9053 and
updated by RFC 9864.

**CNSA 2.0** — NSA Commercial National Security Algorithm Suite 2.0 (December 2024,
Ver. 2.1). Mandates AES-256 as the sole approved symmetric cipher and specifies
approved post-quantum algorithms.

**DTKA** — Delay-Tolerant Key Administration. A key management framework concept
for DTN environments. The primary academic reference is `draft-burleigh-dtnwg-dtka-02`
(August 2018, expired March 2019; author Scott C. Burleigh, JPL/Caltech — not E.
Birrane). The draft was never adopted as a DTN working group item. See §6 for
current alternatives.

**HOST** — The LTX node with role HOST; reference clock and session plan authority.
Defined in LTX-SPECIFICATION.md §2.2.

**LTX Bundle** — A DTN bundle carrying an LTX payload (SessionPlan, TX window
package, readiness signal, action register entry, etc.).

**LTX Node Identity Key (NIK)** — An Ed25519 or ECDSA P-384 key pair permanently
bound to an LTX node for the scope of a session.

**SessionPlan** — The canonical JSON document defining the structure, timing, and
participants of an LTX session. Defined in LTX-SPECIFICATION.md §4.

**planId** — The deterministic SHA-256-derived session plan identifier. Defined in
LTX-SPECIFICATION.md §4.2.

**Merkle Root** — The root hash of a Merkle tree over the audit log entries. Allows
O(log n) inclusion and consistency proofs. See §9.

---

## 3. Fundamental Constraints

### 3.1 Interactive Protocols Are Infeasible

At Earth–Mars distances (56 million to 401 million km), one-way signal propagation
takes 3 to 22 minutes. A round trip takes 6 to 44 minutes.

This means:

- TLS 1.3 requires 1 RTT minimum → **6 to 44 minutes** per handshake.
- IKEv2 requires 2 RTTs → **12 to 88 minutes**.
- OCSP certificate revocation check requires 1 RTT → **6 to 44 minutes**.
- OAuth 2.0 token exchange requires multiple RTTs.

None of these are viable for session initiation or ongoing authentication.

**All cryptographic material MUST be pre-positioned at all nodes before the
session begins.** Key negotiation, certificate fetching, and revocation checking
at session time are not permitted in LTX security schemes.

### 3.2 Signatures Are Always Offline

Because the signing party cannot be contacted in real time, every signature in
LTX is an *offline signature*: created at artefact generation time by the
originating node using its pre-positioned private key, and verified by receiving
nodes using the originating node's pre-positioned public key.

### 3.3 The Merkle Audit Log Provides Efficient Tamper Evidence

LTX sessions maintain an append-only log of questions, actions, and decisions.
This document specifies a Merkle-tree structure (§9) rather than a simple sequential
hash chain. Merkle trees provide O(log n) inclusion proofs and consistency proofs,
critical for efficient partition recovery over bandwidth-constrained DTN links.

A simple hash chain requires O(n) sequential re-hashing for any single entry
verification. After a conjunction blackout during which each node accumulates
thousands of entries, a simple chain verification is impractical. Merkle trees
reduce this to O(log n) without sacrificing tamper evidence.

### 3.4 Relay Nodes Are Untrusted

DTN relay nodes (including relay satellites) are treated as potentially compromised.
End-to-end integrity (BPSec BIBs) and end-to-end confidentiality (BPSec BCBs, when
enabled) protect LTX payloads in transit through relay nodes.

### 3.5 Zero-Trust Requires Asynchronous Accountability

NIST SP 800-207 Zero Trust Architecture principles cannot be applied as specified —
continuous verification is impossible across multi-minute delays. Instead, LTX
implements **asynchronous accountability**: pre-positioned credentials, cached trust
decisions, policy pre-distribution, and tamper-evident logs that are verified upon
reconnection. This approach aligns with the findings of Montilla (IEEE/NASA CCAA
2023) and CISA's Space Systems Security Landscape (2024).

---

## 4. Threat Model

### 4.1 Threat Actors

| Actor | Capability | Example |
|-------|-----------|---------|
| State-level adversary | Intercept, forge, modify bundles in transit; compromise relay infrastructure | Nation-state with access to deep-space relay assets |
| Opportunistic attacker | Replay captured bundles; inject malformed plans | Rogue software on ground segment network |
| Insider threat | Crew member at PARTICIPANT node modifies action register; leaks session content; forges readiness signals | Authorised node operator with physical access |
| Environmental | Cosmic ray bit-flips corrupting bundle payloads in deep space | Single-event upsets in relay spacecraft memory |
| Malicious relay | Compromised relay satellite reads, modifies, or selectively drops bundles | State-controlled relay infrastructure |

### 4.2 Threat: Forged SessionPlan

**Description.** An attacker injects a forged SessionPlan with a version number
higher than the legitimate plan. The plan lock protocol resolves ties by preferring
the higher version, so the forged plan wins.

**Impact.** Attacker controls the session structure: timing, participant ordering,
delay matrix values, questions and actions registers.

**Mitigation.** See §7. Every SessionPlan MUST be signed by the HOST node.
Participants MUST reject any SessionPlan whose signature does not verify against
the HOST's pre-positioned NIK public key.

### 4.3 Threat: Node Impersonation

**Description.** An attacker claims to be a legitimate PARTICIPANT node, injecting
transmissions into the session with a false node identity.

**Mitigation.** See §5 and §8. Every LTX bundle MUST carry a BIB signed by the
originating node's NIK. Receiving nodes verify the BIB before accepting the payload.
NodeIDs are derived from key fingerprints (§5.1) so that a false identity cannot be
constructed without the corresponding private key.

### 4.4 Threat: Corrupted Delay Matrix

**Description.** An attacker modifies the delay matrix, causing nodes to use incorrect
propagation delay values.

**Mitigation.** The delay matrix is inside the signed SessionPlan envelope (§7).
Modification invalidates the HOST's signature. Nodes SHOULD additionally validate
delay matrix values against independent ephemeris computation (±10% tolerance).

### 4.5 Threat: Denial of Service on Scheduling Infrastructure

**Description.** An attacker floods the DTN network with invalid LTX bundles,
exhausting relay storage (store-and-forward; storage is finite on relay spacecraft).

**Mitigation.** See §8. BPSec BIBs allow relay nodes to verify bundle integrity
before committing storage. LTX bundles carry priority classification:

```
PLAN            → highest (SessionPlan and plan updates)
SESSION_CONTENT → high (TX window packages)
READINESS       → normal (readiness signals)
GENERAL         → low (everything else)
```

Relay nodes SHOULD drop bundles failing BIB verification before storing them.

### 4.6 Threat: Replay Attacks

**Description.** An attacker replays a legitimate TX window package from an earlier
session or earlier in the current session.

**Mitigation.** See §11. Every LTX bundle includes a monotonically increasing
sequence number. Receiving nodes reject bundles with non-increasing sequence numbers.

### 4.7 Threat: Emergency Override Abuse

**Description.** A forged emergency override terminates a legitimate session.

**Mitigation.** See §13. Override bundles are signed by an Emergency Override Key
(EOK), separate from the session NIK, with a distinct DTKA trust scope. All override
bundles — including failed ones — are logged.

### 4.8 Threat: Conjunction-Window Attack

**Description.** During a solar conjunction blackout (14–25 days for Earth–Mars),
an attacker pre-stages forged bundles for delivery immediately after the window ends,
exploiting the high-volume resumption period.

**Mitigation.** See §18. A cryptographic session checkpoint is committed before
the conjunction window. All post-conjunction bundles are held in a verification queue
and cryptographically verified before processing.

### 4.9 Threat: Relay Node Compromise

**Description.** An attacker gains control of a relay satellite. A compromised relay
can read, modify, or drop bundles.

**Mitigation.** End-to-end BPSec BIBs prevent undetected modification. Optional
BPSec BCBs (§12) prevent content exposure. Bundle-in-Bundle Encapsulation (BIBE)
SHOULD be considered to prevent compromised relay nodes from gaining universal
routing knowledge. Redundant relay paths where topology permits.

### 4.10 Threat: Block-Dropping by Intermediate Nodes

**Description.** A significant vulnerability identified by formal analysis (Dowling
et al., 2025): BPSec does not ensure destination awareness of missing message
components. Intermediate nodes can legitimately strip security blocks during
processing, but the destination cannot verify whether blocks were legitimately
processed or maliciously dropped.

**Mitigation.** See §21. The StrongBPSec mechanism (`draft-tian-dtn-sbam-00`)
introduces Bundle Report Blocks — signed, verifiable blocks produced by intermediate
nodes that process and discard source-added blocks. LTX implementations SHOULD
track this draft; adoption is recommended once standardised.

### 4.11 Threat: Insider Modification of Action Register

**Description.** A crew member with physical access modifies action register entries
after recording, or fabricates readiness signals.

**Mitigation.** The Merkle-tree audit log (§9) provides efficient tamper evidence.
Signatures on each entry (§10) allow attribution. High-stakes actions require
multi-person authorisation (§19).

---

## 5. Cryptographic Identity

### 5.1 Node Identity Key (NIK)

Every LTX node MUST possess a Node Identity Key (NIK) pair:

- **Algorithm:**
  - **Ed25519 (RECOMMENDED for general deployments):** FIPS 186-5 (2023) approved;
    64-byte signatures; 32-byte public keys; COSE algorithm ID **-19** (RFC 9864).
    See §5.3 for implementation cautions specific to constrained hardware.
  - **ECDSA P-384 (RECOMMENDED for CNSA-conformant deployments):** Required for
    government and NASA missions; COSE algorithm ID **-35** (ES384);
    BPSec COSE context v15 mandatory interop profile.
- **NodeID derivation:** The node's LTX `id` (e.g., `"N0"`) is bound to its NIK
  for the session scope. For persistent node identities across sessions, the NodeID
  SHOULD be derived as the first 16 hex characters of the SHA-256 fingerprint of
  the NIK public key (e.g., `"IPT-3a4f2c1b9e07d5a8"`). This ensures identity
  cannot be forged without the corresponding private key.
- **Signing key vs. ECDH key:** Per RFC 9053 §2.2.1, Ed25519 signing keys
  (COSE crv=6) MUST NOT be reused for X25519 ECDH operations (crv=4), despite
  sharing the same underlying curve mathematically. Separate key pairs are mandatory.

> **Algorithm ID Note:** RFC 9864 ("Fully-Specified Algorithms for JOSE and COSE")
> deprecated the polymorphic EdDSA identifier `-8` (RFC 9053) in favour of
> fully-specified identifiers: **Ed25519 = -19**, Ed448 = -53. The IANA COSE
> Algorithms registry marks -8 as "Deprecated". New implementations MUST use -19.

### 5.2 Node Identity Certificate (NIC)

A Node Identity Certificate (NIC) MUST accompany the NIK public key:

```json
{
  "nodeId":    "N1",
  "sessionId": "<planId or 'global'>",
  "publicKey": "<base64url-NIK>",
  "algorithm": "Ed25519",
  "validFrom": "<ISO 8601 UTC>",
  "validUntil": "<ISO 8601 UTC>",
  "issuer":    "<issuing-authority-id>",
  "signature": "<base64url-sig>"
}
```

For Earth-based sessions (one-way delay < 120 s), NICs MAY use standard X.509 v3
certificates. For deep-space sessions, NICs MUST use the compact format above,
distributed via the key management process described in §6.

### 5.3 Ed25519 Implementation Cautions for Constrained Hardware

Three concerns apply to Ed25519 on spacecraft-class processors:

1. **Two-pass algorithm:** PureEdDSA (the only COSE-permitted variant per RFC 9053
   §2.2) requires buffering the entire message for signing. This may strain RAM on
   embedded processors. Implementations SHOULD stream-hash large payloads separately
   and sign only the hash output with a fixed-length wrapper.

2. **Hash dependency:** Ed25519's internal SHA-512 may force implementations to carry
   an additional hash function if the platform otherwise needs only SHA-256. This is
   a build-size concern for deeply constrained implementations.

3. **Fault injection vulnerability:** Deterministic nonce generation in Ed25519 creates
   a side-channel: fault injection attacks (Romailler & Pelissier, FDTC 2017)
   demonstrated full private key recovery from a single fault during signing on
   embedded hardware. **Implementations MUST use hedged EdDSA** — adding a random
   value to nonce derivation (e.g., `nonce = H(random || private_key || message)`)
   while maintaining verifier compatibility. This is the RECOMMENDED mitigation
   across all LTX deployment contexts.

### 5.4 Emergency Override Key (EOK)

Separate from the NIK, nodes authorised to initiate emergency overrides MUST possess
an Emergency Override Key (EOK):

- Same algorithm constraints as NIK (Ed25519 / P-384)
- Distributed via the key management process (§6) with trust-scope tag `"scope": "override"`
- EOK public keys MUST be included in the signed SessionPlan envelope (§7.2)
- EOK private keys SHOULD be stored on separate hardware from the NIK
- Emergency overrides SHOULD require multi-party authorisation (§19): both Mission
  Control and the local commander must co-sign to prevent single-party abuse

### 5.5 Key Lifetimes

- NIKs SHOULD be rotated between sessions, not shared across unrelated sessions.
- NIKs MUST have `validUntil` covering the planned session duration plus a
  post-conjunction recovery margin (minimum: session duration + 30 days).
- If a key expires during a conjunction blackout, the renewing party MUST
  pre-distribute a successor key before the conjunction window begins.
- Expired keys MUST be refused for new session authentication; existing session
  state signed under an expired key remains valid (the signature was valid when made).

---

## 6. Key Management

### 6.1 Why Standard PKI Fails

Standard PKI requires real-time CA queries, OCSP checks, and CRL downloads. All require
RTTs of 6–44 minutes at interplanetary distances. None are viable. See §3.1.

### 6.2 DTKA Background and Current Status

The Delay-Tolerant Key Administration (DTKA) concept was proposed by Scott C. Burleigh
(JPL/Caltech) in `draft-burleigh-dtnwg-dtka-02` (August 2018). **This draft expired
March 2019 and was never adopted as an IETF DTN working group item.** It has not
progressed beyond its 2017–2018 drafts. Note: the author is S. C. Burleigh, not
E. Birrane (who authored BPSec-related drafts).

DTKA's core model — periodic "whitelist broadcast" bundles containing all valid
(NodeID, PublicKey, EffectiveTime) tuples, with revocation implicit by omission —
remains the best-described approach for DTN key administration. It informs this
document's key management design, but implementations SHOULD NOT reference the
expired draft as a standard.

### 6.3 Current Key Management Alternatives

Three significant alternatives have emerged since DTKA's expiration:

**RFC 9891 (November 2025)** — An ACME extension for DTN Node ID validation, authored
by Brian Sipos (JHU/APL). Allows ACME servers to validate DTN Node IDs for X.509
certificate issuance. The **only DTN key management-related specification to achieve
RFC publication**. Addresses certificate issuance but not full key lifecycle management.

**BERMUDA (2025)** — "A BPSec-Compatible Key Management Scheme for DTNs" by Fuchs,
Walter, and Tschorsch (D3TN GmbH), published at IFIP WNDSS 2025 (IACR ePrint 2025/806).
Combines hierarchical PKI with ECDH and an adapted NOVOMODO hash-chain-based certificate
revocation scheme. Feasible but noted scalability limitations in resource-constrained
environments.

**KeySpace (2025–2026)** — Smailes et al. (Oxford University, arXiv:2408.10963, updated
through v5 February 2026). Proposes distributed CAs per network segment (one each for
Earth, Moon, Mars), relay-as-firewall techniques, and OCSP hybrid approaches. Local
revocations complete within minutes; remote segment protection is faster than a
cross-system approach.

### 6.4 LTX Key Distribution Model

In the absence of a standardised DTKA successor, LTX adopts the following key
distribution model:

**Pre-Session Key Bundle.** Before a session begins, HOST generates a KEY_BUNDLE
DTN bundle containing:
- HOST's own NIC (§5.2)
- All known PARTICIPANT NICs for this session
- All Emergency Override Key (EOK) public keys
- Session scope (planId) and validity window

HOST signs the KEY_BUNDLE under its NIK and distributes it to all nodes via DTN.
Each PARTICIPANT responds with its own signed KEY_BUNDLE. Distribution is considered
complete when HOST has received acknowledgements from all nodes, or when the
pre-session window expires.

**Key Cache.** Each node maintains a persistent local Key Cache:

```
key_cache/
  <nodeId>/
    current.nic        # current NIC
    history/           # prior NICs (kept for post-hoc artefact verification)
      <validFrom>.nic
    override.eok       # EOK public key for this node
```

Key Cache entries MUST be retained for at minimum the session duration plus 2 years
(for artefact audit purposes).

**Mandatory vs Optional KEY_DISTRIBUTION.**
- Mandatory for any node appearing in a session for the first time
- Mandatory after any key rotation event
- Optional for nodes with valid, cached NICs from a recent prior session

### 6.5 Key Revocation Realities in Interplanetary DTN

Real-time revocation is physically impossible. The exposure window equals the interval
until the next valid KEY_BUNDLE fully propagates to all nodes. Under normal conditions
this may be hours; during solar conjunction this can be **two or more weeks**.

The KeySpace distributed-CA model (§6.3) is the most practical mitigation: with
separate CAs per network segment (Earth, Moon, Mars), local revocations complete within
minutes and compromise is bounded to the local segment. LTX implementations operating
on a multi-segment network SHOULD plan for distributed-CA architecture in the
long term.

As an interim measure, KEY_BUNDLE broadcasts SHOULD be scheduled at a cadence
sufficient to bound the revocation exposure window to an acceptable level for the
mission (typically: daily for active sessions, weekly for dormant infrastructure).

### 6.6 Key Revocation Handling

Compromised keys are reported via a `KEY_REVOCATION` bundle:
- Priority class: PLAN (highest)
- Signed by the Key Agent or issuing authority NIK
- Contains: revoked NodeID, revoked key fingerprint, revocation timestamp, reason

Receiving nodes MUST:
1. Check Key Cache for revocation notices before verifying any signature
2. Transition any active session using the revoked key to DEGRADED mode
3. Log the revocation event in the session audit log

---

## 7. SessionPlan Signing — COSE Envelope

### 7.1 Rationale for COSE

COSE (RFC 9052) is RECOMMENDED over JWS/JWT because:
- CBOR encoding is more compact than JSON — critical for bandwidth-constrained DTN links
- COSE is the native signing format for BPSec, ensuring consistency across the LTX stack
- COSE supports Ed25519 (algorithm **-19** per RFC 9864) and ECDSA P-384 (algorithm -35)
- COSE is used in IoT and constrained-device contexts analogous to space deployments

### 7.2 Signed SessionPlan Envelope

A SessionPlan MUST be wrapped in a COSE_Sign1 structure before distribution:

```
COSE_Sign1 {
  protected: {
    1: -19,                        // alg: Ed25519 (RFC 9864; formerly -8, now deprecated)
    4: <kid>,                      // key ID: HOST node ID (e.g., "N0")
    "ltx-plan-version": 2,         // LTX plan schema version
    "ltx-timestamp": <unix-ms>     // signing timestamp (UTC milliseconds)
  },
  unprotected: {},
  payload: <canonical-JSON-bytes>, // canonical JSON per §16
  signature: <64-byte-Ed25519-sig> // over bstr(protected || payload)
}
```

For CNSA-conformant deployments, replace `-19` (Ed25519) with `-35` (ES384, P-384).

The canonical JSON encoding MUST follow the rules in §16 (UTF-8, no whitespace,
keys sorted lexicographically, `nodes` before `segments`).

### 7.3 Verification Procedure

Upon receipt of a SessionPlan envelope, a node MUST:

1. Deserialise the COSE_Sign1 structure
2. Extract the `kid` from the protected header
3. Look up the corresponding NIC in the local Key Cache
4. Verify the NIC is current (not expired, not revoked)
5. Verify the COSE_Sign1 signature using the NIK public key from the NIC
6. If verification fails: MUST reject the SessionPlan; log the failure with source and reason
7. If verification succeeds: proceed with plan lock protocol

A node MUST NOT participate in a session whose SessionPlan fails signature
verification, except to emit a signed rejection notice.

### 7.4 Plan Updates

Updated SessionPlans (version increments) MUST be re-signed by HOST under a new
COSE_Sign1 envelope. The new signature covers the updated canonical JSON. The version
increment and new planId are part of the signed payload.

### 7.5 Fallback: JSON + Detached Signature (TRANSITIONAL)

For implementations where CBOR support is not yet available:

```json
{
  "ltx:v": 2,
  "ltx:signed": true,
  "ltx:alg": "Ed25519",
  "ltx:kid": "N0",
  "ltx:timestamp": 1743033600000,
  "ltx:plan": { },
  "ltx:sig": "<base64url-Ed25519-signature-over-canonical-JSON-of-ltx:plan>"
}
```

The `ltx:sig` field is computed over the `ltx:plan` value in canonical JSON form only
(not over the outer envelope). Implementations MUST migrate to COSE_Sign1 at the
earliest opportunity; the JSON fallback is TRANSITIONAL status only.

---

## 8. Bundle Integrity — BPSec BIBs

### 8.1 Overview

Every LTX bundle MUST carry at least one Bundle Integrity Block (BIB) as defined by
BPSec (RFC 9172 §3.7).

### 8.2 Security Context Options and Current Status

LTX BIBs operate under one of two security contexts:

**Context ID 1 — BIB-HMAC-SHA2 (RFC 9173, symmetric).**
Symmetric HMAC with SHA-256/384. Requires a pre-shared key per node pair. Fast and
compact. Does not provide non-repudiation. This is the context implemented by all
current production DTN stacks (ION 4.1.4, HDTN v2.0.0, NASA/AMMOS BSL).
RECOMMENDED for performance-critical links or when relay verification with a shared
key is acceptable.

**Context ID 3 — BPSec COSE context (`draft-ietf-dtn-bpsec-cose` v15).**
Asymmetric signatures via COSE. Provides non-repudiation; relay nodes can verify
BIBs using pre-positioned public keys without holding a shared secret.

> **Implementation warning:** As of March 2026, **no production DTN stack implements
> Context ID 3**. ION, HDTN, and BSL all implement Context IDs 1 and 2 only.
> Adding Context ID 3 support requires integration of a COSE library and PKI
> infrastructure; this work has not been done in any released DTN implementation.
> The LTX project should plan to either extend NASA/AMMOS BSL (Apache 2.0,
> C99, modular architecture designed for pluggable contexts) or collaborate with
> the ION/HDTN teams.

> **EdDSA in Context ID 3:** Earlier versions of the BPSec COSE context draft
> listed EdDSA as "Recommended." Version -15 (March 2026) has removed EdDSA from
> the mandatory interoperability profile. Ed25519 (-19) remains permitted but the
> mandatory profile uses ES-P384 (-51) / ES-P512 (-52) for ECC integrity. For CNSA
> conformance, use P-384.

> **CCSDS note:** CCSDS has a draft Recommended Standard for Bundle Protocol
> Security (document 734x5r2, February 2025) that profiles RFC 9172 and references
> the COSE context draft but defines no EdDSA-specific specification.

**Recommended approach for LTX v1.0 security implementation:**
Use Context ID 1 (HMAC-SHA2) for relay-layer bundle integrity (symmetric key per
session) and COSE_Sign1 envelopes (§7) for SessionPlan and artefact non-repudiation.
Migrate BIBs to Context ID 3 once the draft achieves RFC status and implementations
are available.

### 8.3 BIB Coverage per LTX Bundle Type

| Bundle type | Target block(s) | BIB signer | Recommended context |
|-------------|----------------|------------|---------------------|
| SessionPlan distribution | Payload block | HOST (NIK) | Context ID 1 or 3 |
| TX window package | Payload + extension blocks | Originating node (NIK) | Context ID 1 or 3 |
| Readiness signal | Payload block | Originating node (NIK) | Context ID 1 |
| Action register entry | Payload block | Originating node (NIK) | Context ID 1 or 3 |
| KEY_DISTRIBUTION bundle | Payload block | HOST (NIK) | Context ID 3 |
| KEY_REVOCATION bundle | Payload block | Issuing authority (NIK) | Context ID 3 |
| Emergency override | Payload block | Originating node (EOK) | Context ID 3 |

### 8.4 Relay Verification Requirement

Relay nodes MUST:
1. Verify the BIB on every incoming LTX bundle before storing it
2. Drop bundles that fail BIB verification; log the failure with source EID
3. NOT forward bundles that fail BIB verification

### 8.5 BIB Verification Failure Handling

If a PARTICIPANT node receives a bundle that fails BIB verification:
1. MUST NOT process the payload
2. MUST log the failure: `{ timestamp, source-EID, bundle-id, failure-reason }`
3. SHOULD emit a signed `INTEGRITY_FAILURE` notification bundle to HOST
4. If failures are frequent: SHOULD transition session to DEGRADED mode

---

## 9. Merkle-Tree Audit Log

### 9.1 Why Merkle Trees Instead of Hash Chains

A simple sequential hash chain `H(n) = SHA-256(entry_n ∥ H(n-1))` requires O(n)
sequential re-hashing to verify any single entry.

For DTN partition recovery, where nodes may accumulate thousands of entries during
days of disconnection, the difference is critical:

- Hash chain: verifying one entry in an 80-million-entry log = ~800 MB data transferred
  (Crosby & Wallach, USENIX Security 2009)
- Merkle tree: the same verification = ~3 KB (O(log n) inclusion proof)

Over a bandwidth-constrained Mars relay link, hash chain re-verification is infeasible.
**LTX MUST use Merkle-tree audit logs.**

### 9.2 Merkle Tree Structure

The audit log Merkle tree follows the Certificate Transparency log design
(RFC 6962, updated RFC 9162):

- **Leaf nodes:** H(0x00 ∥ entry_bytes) — SHA-256 of the serialised log entry
- **Internal nodes:** H(0x01 ∥ left_child_hash ∥ right_child_hash)
- **Tree head:** signed by the local node's NIK; includes: tree size, Merkle root,
  timestamp, session planId

```json
{
  "treeHead": {
    "planId": "<session-plan-id>",
    "nodeId": "N1",
    "treeSize": 42,
    "merkleRoot": "<hex-SHA-256>",
    "timestamp": "<ISO 8601 UTC>",
    "sig": "<base64url-Ed25519-over-treeHead-sans-sig>"
  }
}
```

Tree heads are signed and exchanged between nodes at each reconnection event and
at defined checkpoints (e.g., end of each TX window, pre-conjunction).

### 9.3 Proof Types

**Inclusion proof (audit proof):** Proves that a specific log entry is in the tree.
O(log n) hashes transmitted.

**Consistency proof:** Proves that one tree (of size n₁) is an append-only prefix
of another tree (of size n₂). O(log n₂) hashes transmitted. Critical for partition
recovery: after reconnection, nodes exchange tree heads and consistency proofs to
verify their logs are compatible append-only extensions of each other.

### 9.4 Partition Recovery Procedure

After reconnection following a partition (conjunction blackout or network failure):

1. Both nodes exchange signed tree heads
2. If roots differ: request consistency proof from the node with the larger tree
3. Verify the consistency proof: O(log n) hashes
4. If consistent: the smaller tree is a valid prefix; accept the additional entries
5. If inconsistent: flag divergence; escalate to HOST; DO NOT merge until HOST resolves

### 9.5 Leaf Entry Format

```json
{
  "entryId":   "ACT-0042",
  "sessionId": "<planId>",
  "nodeId":    "N1",
  "seq":       17,
  "type":      "action",
  "content":   { },
  "timestamp": "<ISO 8601 UTC>",
  "sig": "<base64url-Ed25519-over-entry-sans-sig>"
}
```

Each entry is individually signed by the originating node's NIK. The leaf hash is
computed over the serialised entry bytes (after signature is set). This allows
per-entry attribution independent of the tree structure.

---

## 10. Per-Window Artefact Integrity

### 10.1 TX Window Package Manifest

Every TX window package (LTX-SPECIFICATION.md §11.2) MUST include a signed
artefact manifest:

```json
{
  "windowId":       "<planId>-<windowIndex>",
  "nodeId":         "N1",
  "sequenceNumber": 42,
  "artifacts": [
    { "type": "transcript",    "sha256": "<hex>", "byteLen": 14200 },
    { "type": "slide-state",   "sha256": "<hex>", "byteLen": 2048  },
    { "type": "media-lowres",  "sha256": "<hex>", "byteLen": 98304 },
    { "type": "media-highres", "sha256": "<hex>", "byteLen": 4194304, "optional": true }
  ],
  "addressedQIDs":  ["Q-003", "Q-007"],
  "treeHeadHash":   "<sha256-of-current-tree-head>",
  "manifestSig":    "<base64url-Ed25519-over-manifest-sans-sig>"
}
```

`treeHeadHash` links the manifest to the current Merkle tree head, chaining the
window artefacts into the tamper-evident audit log.

### 10.2 Verification at Receipt

Upon receipt of a TX window package, the receiving node MUST:
1. Verify the bundle BIB (§8)
2. Verify the manifest signature using the sender's NIK
3. Verify each artefact's SHA-256 hash matches its declared value
4. Verify `treeHeadHash` matches the most recently verified tree head from this sender
5. If any verification fails: quarantine the package; log the failure; notify HOST

---

## 11. Freshness Markers

### 11.1 Per-Node Sequence Numbers

Every LTX bundle originating from a node MUST include a freshness marker:

```json
{
  "planId": "<session-plan-id>",
  "nodeId": "<originating-node-id>",
  "seq":    42
}
```

Sequence numbers are scoped to `(planId, nodeId)`. They MUST start at 1 and increment
monotonically per bundle.

### 11.2 Replay Detection

Receiving nodes MUST maintain a freshness window per `(planId, nodeId)` pair:
- Track the highest sequence number seen
- Reject (and log) any bundle whose sequence number is not greater than the highest seen
- The freshness window MUST be persisted across restarts

### 11.3 Sequence Number Gaps

Gaps (seq jumped forward) indicate potentially missing bundles; request retransmission
in LTX-Live mode, flag in the session log in LTX-Relay/Async mode. Gaps are
distinguished from replays (duplicate or backward seq = replay attempt).

---

## 12. Confidentiality (Optional)

### 12.1 CONFIDENTIALITY Mode Flag

A SessionPlan MAY include `"confidential": true`. When set, all TX window packages
MUST be encrypted using BPSec BCBs (RFC 9172 §3.8).

### 12.2 Algorithm — AES-256-GCM

All confidentiality operations MUST use **AES-256-GCM**.

BPSec BCB security context: BCB-AES-GCM (RFC 9173, Context ID 2), value 3
(A256GCM). Initialisation vector: 96 bits, random, included in BCB parameters.
Authenticated Additional Data: `windowId ∥ nodeId ∥ sequenceNumber`.

### 12.3 Key Agreement — Offline ECDH

Because interactive key negotiation is infeasible, keys are derived offline during
the KEY_DISTRIBUTION phase:

1. Each node generates an ephemeral ECDH key pair and distributes the public ephemeral
   key alongside its NIC in the KEY_BUNDLE
2. Shared secrets are derived: `ECDH(my-ephemeral-private, their-ephemeral-public)`
3. HKDF-SHA-256 (or HKDF-SHA-384 for CNSA) derives symmetric encryption keys per
   node pair, keyed on session context (planId)
4. TX window packages are encrypted with AES-256-GCM

**COSE key agreement:** ECDH-ES+A256KW (-31) or ECDH-ES+HKDF-512 (-26) with P-384
for CNSA conformance. The direct HKDF variants (-25/-26) are RECOMMENDED for
single-recipient bundles. X25519 (crv=4) is supported by COSE and offers
implementation advantages but is not CNSA-conformant.

### 12.4 Relay Implications

With CONFIDENTIALITY mode enabled, relay nodes cannot read payload content but CAN
still verify BIBs on the primary and extension blocks.

---

## 13. Emergency Override Security

### 13.1 Override Bundle Structure

```json
{
  "type":        "EMERGENCY_OVERRIDE",
  "planId":      "<target-session-plan-id>",
  "nodeId":      "<originating-node-id>",
  "reason":      "<human-readable, max 500 chars>",
  "timestamp":   "<ISO 8601 UTC>",
  "seq":         42,
  "cosigNodeId": "<second-authorising-node-id>",
  "cosigSig":    "<base64url-Ed25519-co-signature>",
  "overrideSig": "<base64url-Ed25519-over-content-sans-sigs-using-EOK>"
}
```

Override bundles require both a primary signature (EOK) and a co-signature from a
second authorised node (§19). A single-authority override MUST be rejected.

### 13.2 Override Verification

Upon receipt:
1. Verify `overrideSig` against the sender's EOK public key
2. Verify `cosigSig` against the co-signer's EOK public key
3. Confirm both keys have trust scope `"override"`
4. Check sequence number against EOK-scoped freshness window
5. Log the override regardless of verification result
6. If verified with both signatures: halt session; enter EMERGENCY_HOLD
7. If not verified or only one signature: continue session; emit `OVERRIDE_REJECTED`
   notice to HOST

### 13.3 Override Log Requirement

All override bundles, including those failing verification, MUST be included in the
session Merkle audit log and the final session artefact package.

---

## 14. Session-Level Security Associations — BP-SAFE

### 14.1 Status of BP-SAFE

`draft-sipos-dtn-bp-safe-00` ("Bundle Protocol Security Associations with Few
Exchanges") is an **individual submission** by Brian Sipos, submitted June 4, 2025
and **expired December 6, 2025**. It was **never adopted** by the IETF DTN working
group and has no RFC stream assignment. Its design — negotiating scoped SAs to
amortise asymmetric-key operation costs — remains conceptually important, but
LTX implementations MUST NOT treat BP-SAFE as an established standard.

### 14.2 Interim Security Association Approach

Until a standardised SA mechanism is available, LTX establishes security context
implicitly through the KEY_BUNDLE exchange (§6.4):

- All nodes agree on algorithms and security context via the signed SessionPlan
  (`"ltx:alg"` field, covered by HOST signature)
- The planId serves as the SA scope identifier for all BPSec operations
- If/when `draft-sipos-dtn-bp-safe` is revised and adopted, LTX SHOULD migrate
  to explicit SA establishment via that mechanism

---

## 15. iCalendar Distribution Security

### 15.1 Threats

ICS files distributed by email are subject to spoofing, MITM modification, and
interception.

### 15.2 iCalendar Attachment Format

The SessionPlan JSON embedded in the VEVENT MUST be carried as a signed attachment:

```
ATTACH;FMTTYPE="application/vnd.ietf.ltx-plan+json";ENCODING=BASE64:
  <base64(COSE_Sign1 of canonical SessionPlan JSON)>
```

This carries the full COSE_Sign1 envelope (§7.2) as a base64-encoded binary
attachment. Recipients base64-decode and COSE-verify the attachment independently of
email channel security.

For implementations not yet supporting COSE, the TRANSITIONAL JSON+detached
signature (§7.5) may be carried as:

```
ATTACH;FMTTYPE="application/vnd.ietf.ltx-plan+json":
  <base64url(JSON-envelope-with-ltx:sig)>
```

### 15.3 S/MIME Signing for Calendar Distribution

ICS files SHOULD be distributed as S/MIME signed messages (RFC 8551). The signing
certificate MUST bind the sender's identity to an email address or organisational
identity.

### 15.4 Detached CMS Signature

Where S/MIME is not available, a detached CMS signature (RFC 5652) SHOULD accompany
the ICS. Verification chain: `email identity (S/MIME or DKIM) → VEVENT integrity →
LTX-PLANID → SessionPlan JSON attachment → COSE_Sign1 signature`.

### 15.5 CalDAV

CalDAV calendar distribution MUST use TLS 1.2+ (RFC 8446). Calendar entries at
rest SHOULD use server-side encryption.

---

## 16. Canonical JSON Specification

All SessionPlan JSON objects used as COSE signature inputs MUST conform to this
canonical form. Deviation causes signature verification failure.

### 16.1 Rules

1. **Encoding:** UTF-8, no BOM
2. **Whitespace:** none (no spaces, tabs, or newlines outside string values)
3. **Key ordering:** object keys sorted lexicographically by Unicode code point
4. **Number format:** no trailing zeros after decimal point; no leading zeros; no
   explicit `+` sign; no `-0`
5. **String escaping:** only mandatory JSON escape sequences; no unnecessary Unicode
   escapes
6. **Array ordering:** preserved as specified (arrays are not sorted)
7. **Top-level key ordering:** `"nodes"` MUST appear before `"segments"` in the
   SessionPlan root object (existing conformance requirement)

These rules are consistent with RFC 8785 (JSON Canonicalisation Scheme, JCS).
Implementations SHOULD use a JCS-compliant library.

### 16.2 Canonical JSON Example (SessionPlan fragment)

```json
{"mode":"LTX","nodes":[{"delay":860,"id":"N1","location":"mars","name":"Mars Hab-02","role":"PARTICIPANT"},{"delay":0,"id":"N0","location":"earth","name":"Earth HQ","role":"HOST"}],"quantum":5,"segments":[{"q":2,"type":"PLAN_CONFIRM"}],"start":"2026-03-15T14:00:00.000Z","title":"Mars Mission Alpha","v":2}
```

Note: no spaces, keys sorted, `"nodes"` before `"segments"`.

---

## 17. Library Integrity — planet-time.js and Ports

### 17.1 Supply-Chain Risk

`planet-time.js` and language ports are used in LTX scheduling. A compromised library
could corrupt timing computations or inject malicious code.

### 17.2 Signed Release Manifests

Every release MUST be accompanied by a signed manifest:

```json
{
  "package":     "interplanet-planet-time",
  "version":     "1.2.0",
  "releaseDate": "<ISO 8601>",
  "files": [
    { "path": "dist/planet-time.esm.js",  "sha256": "<hex>" },
    { "path": "dist/planet-time.iife.js", "sha256": "<hex>" }
  ],
  "manifestSig": "<base64url-Ed25519-over-manifest-sans-sig>"
}
```

Signed by the project Release Signing Key (RSK), separate from any session NIK.

### 17.3 Registry Provenance

All packages published to npm, PyPI, or other registries SHOULD use provenance
attestation where supported (npm provenance via OIDC, PyPI Trusted Publishers).

### 17.4 Conformance Suite as Secondary Integrity Check

The cross-language conformance test suite (`c/planet-time/fixtures/reference.json`)
serves as a secondary integrity check. Running the suite against a newly installed
library provides additional assurance beyond the signed manifest.

---

## 18. Conjunction-Safe Security Checkpoints

### 18.1 Pre-Conjunction Checkpoint

Before every predicted solar conjunction window, a signed checkpoint MUST be committed:

```json
{
  "type":             "CONJUNCTION_CHECKPOINT",
  "planId":           "<session-plan-id>",
  "checkpointTime":   "<ISO 8601 UTC>",
  "conjunctionStart": "<ISO 8601 UTC>",
  "conjunctionEnd":   "<estimated ISO 8601 UTC>",
  "merkleRoot":       "<sha256-of-audit-log-merkle-root>",
  "treeSize":         1247,
  "lastSeqPerNode":   { "N0": 147, "N1": 89 },
  "checkpointSig":    "<base64url-Ed25519-over-checkpoint-sans-sig>"
}
```

Signed by HOST; distributed to all PARTICIPANT nodes before the conjunction window.

### 18.2 Post-Conjunction Verification Queue

All bundles arriving during and immediately after conjunction:
1. Are placed in a verification queue
2. BIB verified before processing
3. Sequence numbers verified to be monotonically increasing from `lastSeqPerNode`
4. SessionPlan updates verified against HOST's pre-conjunction checkpoint
5. Merkle consistency proof verified (§9.4) before merging new log entries

The queue MUST be fully cleared before the session resumes normal operation.

### 18.3 Post-Conjunction Reconciliation

After queue clearance, nodes MUST emit a signed `POST_CONJUNCTION_CLEAR` bundle
confirming state integrity verification has passed.

---

## 19. Multi-Person Authorisation

### 19.1 MULTI-AUTH Mode

For mission-critical decisions, emergency overrides, and post-conjunction log
modifications, sessions SHOULD operate in MULTI-AUTH mode. A flagged action requires
co-signatures from at least two authorised operators before being appended as
authorised.

### 19.2 Co-Signature Bundle

```json
{
  "type":         "ACTION_COSIG",
  "entryId":      "ACT-0099",
  "planId":       "<session-plan-id>",
  "cosigNodeId":  "N1-operator-2",
  "cosigTime":    "<ISO 8601 UTC>",
  "cosigSig":     "<base64url-Ed25519-over-entryId+planId+cosigTime>"
}
```

An action is AUTHORISED only after the required number of co-signatures (default: 2)
are present and all verify successfully.

---

## 20. Post-Quantum Readiness

### 20.1 Threat Timeline

Current elliptic-curve algorithms (Ed25519, ECDSA P-384) are secure against
classical computers. Cryptographically relevant quantum computers (CRQCs) capable of
breaking these algorithms do not exist as of 2026. However, LTX is designed for
multi-decade interplanetary missions; a CRQC may become available during a mission
lifetime. "Harvest now, decrypt later" attacks (storing ciphertext today for future
decryption) are a realistic threat for long-term data.

### 20.2 NIST PQC Standards (August 2024)

NIST finalised three initial PQC standards on August 13, 2024:
- **FIPS 203** — ML-KEM (key encapsulation)
- **FIPS 204** — ML-DSA (signatures, 2,420-byte signatures for Level 2)
- **FIPS 205** — SLH-DSA (signatures, 7,856-byte signatures for 128s variant)

Additional algorithms progressing:
- **FIPS 206** — FN-DSA/FALCON (~666-byte signatures), submitted August 2025;
  expected final 2026/2027. COSE draft: `draft-ietf-cose-falcon-03` (October 2025).
- **ML-DSA COSE:** `draft-ietf-cose-dilithium-11` (November 2025)
- **LMS/HSS (SP 800-208):** Already standardised; COSE support via RFC 8778;
  1,776-byte signatures but tiny 60-byte public keys

### 20.3 Bandwidth Impact on DTN Links

| Algorithm | Sig (bytes) | PubKey (bytes) | Overhead vs Ed25519 | At 256 kbps | At 1 kbps |
|-----------|------------|----------------|---------------------|-------------|-----------|
| Ed25519 | 64 | 32 | baseline (96 B) | <1 ms | <1 s |
| FN-DSA-512 | ~666 | 897 | 16× | ~25 ms | ~12 s |
| LMS H=20,W=8 | 1,776 | ~60 | 19× | ~55 ms | ~14 s |
| ML-DSA-44 | 2,420 | 1,312 | 39× | ~93 ms | ~30 s |
| SLH-DSA-128s | 7,856 | 32 | 82× | ~245 ms | ~63 s |

At 256 kbps (Mars relay), ML-DSA-44 adds ~93 ms per signature — acceptable for
session-level bundles. At 1 kbps (direct link), 30 seconds per signature is
problematic for small command bundles. For large TX window packages (>100 KB),
even ML-DSA-44 adds <2.4% overhead.

### 20.4 Recommended Post-Quantum Migration Path

**Near-term (available now):** LMS/HSS (SP 800-208) via COSE (RFC 8778) is the
best deployable option. Requires careful state management to prevent one-time key
reuse (LMS is stateful).

**Medium-term (once FIPS 206 finalised ~2026/2027):** FN-DSA-512 offers the best
bandwidth efficiency for DTN. COSE draft (`draft-ietf-cose-falcon-03`) is actively
progressing.

**Long-term:** ML-DSA once COSE draft (`draft-ietf-cose-dilithium-11`) achieves
RFC status. Larger but widely supported.

**Hybrid signatures** (classical + PQ, e.g., Ed25519 + ML-DSA) are RECOMMENDED
during the transition period: verification requires both signatures to pass, providing
security against both classical and quantum adversaries while not weakening classical
security if the PQ algorithm has an undiscovered flaw.

### 20.5 BPSec Pluggability

BPSec's pluggable security context architecture (§8) is designed to accommodate new
algorithms without protocol-level changes. Adding a PQ security context requires:
1. A new COSE algorithm registration
2. A new BPSec security context draft (analogous to `draft-ietf-dtn-bpsec-cose`)
3. Implementation in DTN stacks

No DTN-specific post-quantum proposals exist yet — this is a research gap the LTX
project should explicitly plan for.

---

## 21. Formal Analysis and Verification Gap

### 21.1 Existing Formal Analysis

The first and only formal cryptographic analysis of BPSec was published in 2025:
**"Cryptography is Rocket Science: Analysis of BPSec"** by Dowling, Hale, Tian, and
Wimalasiri (IACR Communications in Cryptology, Vol. 1, No. 4,
DOI: 10.62056/a39qudhdj).

**Key finding — block-dropping vulnerability:** BPSec does not ensure destination
awareness of missing message components. Intermediate nodes can legitimately strip
security blocks during processing, but the destination cannot verify whether blocks
were legitimately processed or maliciously dropped.

**StrongBPSec mitigation:** The authors proposed StrongBPSec, formalized as
`draft-tian-dtn-sbam-00` ("StrongBPSec Audit Mechanism"). It introduces **Bundle
Report Blocks** — signed, verifiable blocks produced by intermediate nodes that
process and discard source-added blocks, maintaining a verifiable ledger of
modifications. LTX implementations SHOULD track this draft and adopt it once
standardised.

### 21.2 No Automated Protocol Verification

No TLA+, ProVerif, or Tamarin analysis of BPSec or the Bundle Protocol has been
published. This is a significant gap for a system being deployed on the Lunar Gateway.
ESA has commissioned a BPSec testbed for implementation validation (testing, not
formal verification).

**Recommendation:** The LTX project should commission a Tamarin or ProVerif model of
its specific security protocol composition — particularly the interaction between
BPSec, the DTKA-style key distribution, COSE_Sign1 envelopes, and the Merkle-tree
audit log. The plan lock protocol under adversarial plan manipulation (red-team
scenario) should be explicitly modelled.

---

## 22. Security Test Plan

### 22.1 Unit Tests

| Test | Description | Expected result |
|------|-------------|----------------|
| Valid SessionPlan signature | HOST signs plan; PARTICIPANT verifies via Key Cache | Plan accepted; session proceeds |
| Tampered plan content | Bit-flip in canonical JSON after signing | COSE verification fails; plan rejected |
| Wrong signing key | Plan signed with unknown key not in Key Cache | COSE verification fails; plan rejected |
| Stale version replay | Old SessionPlan (lower version number) re-submitted | Plan rejected; higher version retained |
| Missing BIB | LTX bundle arrives without BIB | Bundle rejected; `INTEGRITY_FAILURE` logged |
| Bundle payload tamper | Relay modifies payload bytes | BIB MAC/signature fails; bundle dropped |
| Replay attack | Bundle with seq=10 arrives after seq=20 already seen | Bundle rejected; replay logged |
| Sequence gap | seq=5 received then seq=8 (gap of 2) | Gap logged; retransmission requested |
| Single-signature override | Emergency override with only one EOK signature | Override rejected; `OVERRIDE_REJECTED` emitted |
| Expired NIK | SessionPlan signed with key past `validUntil` | Plan rejected with expired-key reason |
| Revoked key | KEY_REVOCATION bundle processed; subsequent plan signed by revoked key | Plan rejected; DEGRADED mode |
| Log entry tamper | Merkle leaf value modified after tree head signed | Consistency proof fails; divergence flagged |
| Merkle consistency — valid append | Node A has tree of size 10; Node B has same tree extended to 15 | Consistency proof verifies; entries accepted |
| Merkle consistency — diverged | Two nodes have same size but different roots | Divergence detected; escalate to HOST |
| AES-256-GCM round-trip | Encrypt TX window; decrypt; compare | Plaintext matches; AEAD tag verifies |
| Canonical JSON determinism | Two independent implementations serialise same plan | Byte-identical output; same signature |

### 22.2 Integration Tests

- **DTN testbed:** Two LTX nodes communicating via ION or HDTN with simulated
  delay (3–22 min one-way) and packet loss. Verify BIB integrity end-to-end.
- **Partition simulation:** Disconnect nodes for simulated conjunction period;
  accumulate log entries; reconnect; verify Merkle consistency reconciliation.
- **Cross-implementation:** Python LTX and TypeScript LTX verify each other's
  COSE_Sign1 signatures and canonical JSON.
- **Key rotation:** Rotate NIK mid-session; verify successor key accepted; verify
  old key rejected for new bundles.

### 22.3 Adversarial Tests

- **Forged SessionPlan with higher version:** Adversary injects higher-version plan.
  Should be rejected because HOST signature is absent/invalid.
- **Relay block-stripping:** Simulate BPSec block removal by relay; verify
  StrongBPSec-style report blocks expose the modification.
- **Conjunction timing attack:** Pre-stage forged bundles; deliver post-conjunction;
  verify verification queue catches them before session state is affected.

---

## 23. Priority Summary and Implementation Roadmap

Implementation is deferred to a future sprint pending review of this document.

### Critical (implement first)

| Ref | Requirement | Section |
|-----|-------------|---------|
| R1 | Node Identity Keys (Ed25519 / P-384); NIK binding; NodeID from key fingerprint | §5 |
| R2 | COSE_Sign1 envelope on all SessionPlans; algorithm ID -19 (Ed25519) or -35 (P-384) | §7 |
| R3 | BPSec BIBs on all LTX bundles; Context ID 1 initially; plan for Context ID 3 | §8 |
| R4 | Sequence-number freshness markers; replay rejection; persisted across restarts | §11 |
| R5 | Merkle-tree audit log; signed tree heads; consistency proof on reconnection | §9 |
| R6 | Canonical JSON implementation (RFC 8785 / JCS compliant) | §16 |

### High (same or immediately following sprint)

| Ref | Requirement | Section |
|-----|-------------|---------|
| R7 | Key distribution pre-session (KEY_BUNDLE exchange); Key Cache persistence | §6.4 |
| R8 | Emergency Override Key (EOK); multi-signature override bundles | §5.4, §13 |
| R9 | Per-window artefact manifest; SHA-256 hashes; tree head linkage | §10 |
| R10 | Hedged EdDSA for fault-injection resistance on constrained hardware | §5.3 |

### Medium-High (within 2 sprints)

| Ref | Requirement | Section |
|-----|-------------|---------|
| R11 | Conjunction-safe checkpoints; post-conjunction verification queue | §18 |
| R12 | MULTI-AUTH mode for high-stakes actions | §19 |
| R13 | Security test plan execution (unit + integration + adversarial) | §22 |

### Medium (when confidentiality is required)

| Ref | Requirement | Section |
|-----|-------------|---------|
| R14 | CONFIDENTIALITY mode: BPSec BCBs + AES-256-GCM | §12 |
| R15 | iCalendar S/MIME signing and COSE_Sign1 attachment | §15 |
| R16 | Library signed release manifests | §17 |

### Deferred (future work)

| Ref | Requirement | Notes |
|-----|-------------|-------|
| R17 | Migrate BIBs to Context ID 3 once `draft-ietf-dtn-bpsec-cose` achieves RFC status | §8.2 |
| R18 | Post-quantum hybrid signatures (classical + LMS or FN-DSA) | §20 |
| R19 | Tamarin/ProVerif formal model of LTX security composition | §21.2 |
| R20 | StrongBPSec Bundle Report Blocks once `draft-tian-dtn-sbam` standardised | §21.1 |
| R21 | BP-SAFE SA establishment once a successor to `draft-sipos-dtn-bp-safe` is adopted | §14 |
| R22 | Distributed-CA per network segment (KeySpace model) for revocation improvement | §6.5 |

---

## 24. Security Considerations for This Document

**Completeness.** This document covers the primary attack surface. Post-quantum
migration (§20) is treated as future work; implementations beginning now should plan
for algorithm agility from the start.

**Implementation gap.** No production DTN stack currently implements BPSec Context
ID 3 (asymmetric COSE-based BIBs). The recommended interim approach — Context ID 1
symmetric BIBs for relay integrity, COSE_Sign1 at the LTX application layer for
non-repudiation — provides meaningful security without waiting for Context ID 3
implementations.

**Standards in flux.** `draft-ietf-dtn-bpsec-cose` is at v15 but not yet RFC.
`draft-sipos-dtn-bp-safe-00` has expired. `draft-tian-dtn-sbam-00` is early draft.
LTX implementations must track these drafts; the architecture is designed to accommodate
changes without protocol-level disruption via BPSec's pluggable context model.

**Review status.** This document is a documentation artefact prepared for qualified
security review. No cryptographic scheme should be considered adopted or implemented
until review is complete.

---

## 25. References

### Normative References

**[RFC2119]** Bradner, S., "Key words for use in RFCs to Indicate Requirement
Levels", BCP 14, RFC 2119, March 1997.

**[RFC8174]** Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key
Words", BCP 14, RFC 8174, May 2017.

**[RFC9052]** Schaad, J., "CBOR Object Signing and Encryption (COSE): Structures
and Process", RFC 9052, August 2022.

**[RFC9053]** Schaad, J., "CBOR Object Signing and Encryption (COSE): Initial
Algorithms", RFC 9053, August 2022.

**[RFC9864]** Schaad, J. et al., "Fully-Specified Algorithms for JOSE and COSE",
RFC 9864, 2024. Deprecates EdDSA algorithm ID -8; assigns Ed25519 = -19, Ed448 = -53.

**[RFC9171]** Burleigh, S. et al., "Bundle Protocol Version 7", RFC 9171,
January 2022.

**[RFC9172]** Birrane, E. and K. McKeever, "Bundle Protocol Security (BPSec)",
RFC 9172, January 2022.

**[RFC9173]** Birrane, E., "Default Security Contexts for Bundle Protocol Security
(BPSec)", RFC 9173, January 2022. Note: §4.3.2 specifies A256GCM as the default.

**[RFC8785]** Rundgren, A. et al., "JSON Canonicalization Scheme (JCS)", RFC 8785,
June 2020. Used for canonical JSON in COSE_Sign1 payloads (§16).

**[RFC8551]** Schaad, J. et al., "Secure/Multipurpose Internet Mail Extensions
(S/MIME) Version 4.0", RFC 8551, April 2019.

**[RFC5652]** Housley, R., "Cryptographic Message Syntax (CMS)", RFC 5652,
September 2009.

**[RFC9162]** Laurie, B. et al., "Certificate Transparency Version 2.0", RFC 9162,
February 2022. Merkle tree structure for audit logs (§9).

**[RFC8778]** Panos, A., "Use of the HSS/LMS Hash-Based Signature Algorithm with
CBOR Object Signing and Encryption (COSE)", RFC 8778, April 2020.
Post-quantum near-term option (§20).

### Informative References

**[RFC8949]** Bormann, C. and P. Hoffman, "Concise Binary Object Representation
(CBOR)", RFC 8949, December 2020.

**[RFC9891]** Sipos, B., "Automated Certificate Management Environment (ACME)
Challenges Using DTN Node IDs", RFC 9891, November 2025. First RFC publication
for DTN key management-related standardisation.

**[BPSec-COSE-15]** Sipos, B., "CBOR Object Signing and Encryption (COSE) for
Bundle Protocol Security (BPSec)", `draft-ietf-dtn-bpsec-cose-15`, March 2026.
WG state: Consensus/Waiting for Write-Up. Defines Security Context ID 3.

**[BP-SAFE-00]** Sipos, B., "Bundle Protocol Security Associations with Few
Exchanges", `draft-sipos-dtn-bp-safe-00`, June 2025. Individual submission;
expired December 2025; NOT adopted by DTN WG.

**[DTKA]** Burleigh, S.C. (JPL/Caltech), "Delay-Tolerant Key Administration",
`draft-burleigh-dtnwg-dtka-02`, August 2018. Expired March 2019; not adopted.
See §6.2 and alternatives (§6.3).

**[BERMUDA]** Fuchs, S., Walter, M., and Tschorsch, F. (D3TN GmbH), "A
BPSec-Compatible Key Management Scheme for DTNs", IFIP WNDSS 2025,
IACR ePrint 2025/806.

**[KEYSPACE]** Smailes, J. et al. (Oxford University), "KeySpace: PKI for
Interplanetary Networks", arXiv:2408.10963, updated v5 February 2026.

**[STRONGBPSEC]** Tian, H. et al., "StrongBPSec Audit Mechanism",
`draft-tian-dtn-sbam-00`. Proposes Bundle Report Blocks to address the
block-dropping vulnerability identified in [BPSEC-ANALYSIS].

**[BPSEC-ANALYSIS]** Dowling, B., Hale, B., Tian, H., and Wimalasiri, C.,
"Cryptography is Rocket Science: Analysis of BPSec", IACR Communications in
Cryptology, Vol. 1, No. 4, 2025. DOI: 10.62056/a39qudhdj.

**[FIPS186-5]** NIST, "Digital Signature Standard (DSS)", FIPS 186-5, 2023.
Approves Ed25519.

**[FIPS204]** NIST, "Module-Lattice-Based Digital Signature Standard (ML-DSA)",
FIPS 204, August 2024.

**[FIPS205]** NIST, "Stateless Hash-Based Digital Signature Standard (SLH-DSA)",
FIPS 205, August 2024.

**[FIPS206]** NIST, "Fast Fourier Lattice-Based Compact Signatures over NTRU
(FN-DSA)", FIPS 206 draft, submitted August 2025. Expected final 2026/2027.

**[CNSA2]** NSA, "Commercial National Security Algorithm Suite 2.0", Version 2.1,
December 2024.

**[CCSDS-734x5]** CCSDS, "Bundle Protocol Security — Recommended Standard",
Document 734x5r2, February 2025. Profiles RFC 9172 for space use.

**[HDTN-SPACE]** NASA Glenn Research Center, HDTN v2.0.0, September 2025.
Demonstrated BPSec integrity and confidentiality in space (June 2024, LCRD laser
comms, 900+ Mbps).

**[MONTILLA-ZT]** Montilla, A. (Spatiam Corporation), "Zero Trust Architecture for
Interplanetary Networks", IEEE/NASA CCAA Workshop, June 2023.

**[ROMAILLER-FDTC]** Romailler, Y. and Pelissier, S., "Practical Fault Attack
Against the Ed25519 and EdDSA Signature Schemes", FDTC 2017.

**[LTX-SPEC]** InterPlanet Project, "LTX Specification v1.0",
`interplanet-github/docs/LTX-SPECIFICATION.md`.

**[RFC9557]** IETF, "Date and Time on the Internet: Timestamps with Additional
Information", RFC 9557, April 2024.
