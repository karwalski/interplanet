# Handoff: continue locally with Claude Code

**Prepared:** 29 September 2026, at the end of a Claude Code cloud session
**Branch:** `claude/interplanet-repo-review-v5kogt` (not merged, no pull request yet)
**Issues:** #2 to #38 in karwalski/interplanet

This file is the starting point for picking the work up on your own machine. Paste the "Prompt to start the local session" section into Claude Code from the repository root.

---

## 1. Where things stand

### Delivered on the branch

| Track | Issues | State |
| --- | --- | --- |
| Research and audit | report in `docs/research/2026-09-29-discoverability-and-ltx-topics.md` | Done |
| Discoverability (site, installs, CI, versions, baseline) | #2, #3, #5, #6, #7 | Done |
| LTX spec integrity (schema, golden vectors, validatePlan, late seq, decisions, delay matrix) | #8 to #13 | Done in JS/TS, then cascaded to all ports (#27) |
| Topics (RFC, module, accessible board), experimental | #15, #16, #17 | Done, marked experimental |
| Research support (protocol templates, replication kit, evaluation protocol, related-work page) | #18 to #21 | Done |
| Port fixes found along the way | #23 to #29 | Done |
| Versions and docs, build entry points, interop harness, toke port | #30 to #33 | Done |
| Server planIds, Zig typed model, typed escaping and speaker/label, Unicode prefixes | #34 to #37 | Done |
| Full sweep | #38 | See section 3 |

### Blocked on you (cannot be done by Claude)

| Issue | What you need to do |
| --- | --- |
| #4 IP-D3 | Set the GitHub description, topics and Discussions. Exact text and a `gh repo edit` command are in `docs/research/discoverability-baseline.md` under "Owner actions". |
| #14 IP-T1 | Look up US11397521B2 and its family on the official registers. Steps and a results table are in `docs/research/ip-t1-patent-record.md`. The first US maintenance fee grace period ended 26 Jul 2026, so the fee record decides whether the US patent is in force. |
| #22 IP-O1 | Review the outreach drafts (sent to you as a file in the cloud session, not committed). Nothing has been sent. Have a patent professional see the licensing enquiry first. |

### Decisions waiting for you

1. **Spec change in IP-L4 (#11):** spec section A.5 used to say a receiver MUST reject any seq at or below the last one. It now accepts late seqs inside a 64-entry reorder window and rejects exact replays. Confirm or revert.
2. **Changed planIds.** Several fixes change ids for affected inputs. They are more correct against spec 4.3, but any stored ids from older builds will differ:
   - non-ASCII titles or names in most non-JS ports (they hashed UTF-8 bytes instead of UTF-16 code units)
   - R ids for about half of all plans (hash reduced modulo 2^31-1)
   - Kotlin default plans (default segments now match JS; default mode is now `LTX` instead of the invalid `async`)
   - Zig typed plans (model rewritten to the v2 schema)
   - `api/ltx.php` and both relay servers (now the spec id of the plan as received)
3. **Split surrogate forms** in planId prefixes: ports whose strings cannot hold a lone surrogate use U+FFFD, and byte-string ports keep WTF-8. This is written into spec 4.3 and `spec/golden/plan-id-prefixes.json`. Confirm this is acceptable as normative text.
4. **Merge strategy:** the branch is large (about 480 files, much of it removed build output). Decide whether to merge as one pull request or split it.

---

## 2. Setting up locally

```bash
git fetch origin
git checkout claude/interplanet-repo-review-v5kogt
```

Toolchains used in the cloud session (install what you need for the ports you care about):

| Port | Toolchain used |
| --- | --- |
| JS, TS, CLI, servers | Node 22, npm |
| Python | Python 3.11+, pytest, cryptography |
| Java, Kotlin, Scala | JDK 17 or 21, Gradle 8.x, sbt 1.10 |
| C, C++ | gcc or clang, make |
| Go, Rust | Go 1.21+, Rust stable |
| Ruby, PHP | Ruby 3.x; PHP 8.1+ with Composer (PHPUnit 10) |
| C#, F# | .NET 8 or later |
| Dart, Swift | Dart 3; Swift 5.10 |
| Elixir | Elixir 1.14+ (jason dependency via Hex) |
| Lua, OCaml, R, Julia, Zig | Lua 5.4; OCaml with ocamlfind; R 4.1+ (run with `LC_ALL=C.UTF-8`); Julia 1.10; Zig 0.15.1 |
| toke | `toke/build.sh` clones and builds tkc at a pinned revision |

Cloud-only workarounds you do **not** need locally: the scratchpad `bin/` wrappers for julia, zig, sbt and dart, the unpacked Swift toolchain, and the GitHub-built jason for Elixir. Locally, use normal installs and set `SWEEP_PATH` or `INTEROP_PATH` only if a tool is not on `PATH`.

---

## 3. Verifying everything

```bash
scripts/sweep/run-all.sh          # every port, conformance checks, interop, web and services
node scripts/interop/run.js       # cross-port planId interoperability only
node scripts/check-versions.js    # versions.json against manifests and tables
```

Sweep results from the cloud session: SEE_SWEEP_RESULTS

---

## 4. Suggested next steps

1. Review and answer the decisions in section 1.
2. Run the sweep locally and fix anything that differs from section 3 on your machine.
3. Push once and let `.github/workflows/conformance.yml` and `versions.yml` run for the first time on GitHub. The Swift, Scala, Julia and Elixir CI setup steps have not yet run on GitHub.
4. Open a pull request (the repository has a PR template).
5. Close the implemented issues when merged; keep #4, #14 and #22 open until you finish them.
6. Remaining known gaps: SEE_REMAINING_GAPS

---

## 5. Prompt to start the local session

```text
Read docs/HANDOFF.md. We are continuing the InterPlanet work on branch
claude/interplanet-repo-review-v5kogt. First run scripts/sweep/run-all.sh and
report any failures on this machine compared with the cloud results in the
handoff. Do not merge or open a pull request until I have answered the
decisions in section 1. Keep changes small and commit per issue with
"Refs #N".
```
