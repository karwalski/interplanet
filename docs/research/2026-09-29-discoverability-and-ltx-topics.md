# Discoverability audit, Space Braiding research and LTX topic assessment

**Prepared:** 29 September 2026
**Reviewed commit:** `ac29d383bf9830e5e585966b7b43d503c116b10b` (main, committed 8 July 2026)
**Scope:** Work items 1 to 4 of the story "InterPlanet: discoverability review and patent-aware LTX topic research"
**Status:** Research output for backlog review. This is not legal advice or a freedom-to-operate opinion.

## 0. Method and access limitations

This review was run from an isolated cloud container. Its outbound network policy blocked many hosts, so several required sources could not be read directly. Every blocked item is listed here and none has been treated as confirmed absence.

| Source | Result | Consequence |
| --- | --- | --- |
| `https://interplanet.live/` (HTTPS, and the `www` host) | Connection refused by the egress proxy | Live deployment, deployed version, HTTP status, redirects and robots behaviour **not verified**. The site source in `demo/` was audited instead. |
| `patents.google.com`, USPTO Patent Center / Patent Public Search, IP Australia, EPO Register, WIPO Patentscope | Blocked | **Claim text, family, prosecution and legal status for US11397521B2 are unverified.** |
| `braided.space` PDF, NASA NTRS 20230004112, ScienceDirect full text, the Georgia Tech copy of Fischer & Mosier 2016 | Blocked | Findings come from abstracts and search-index snippets only. |
| GitHub API (via MCP), npm registry, PyPI, crates.io, RubyGems | Reachable | Verified directly. |

A multi-agent web research pass (5 search angles, 22 sources fetched, claims checked by 3-vote adversarial verification) was also run. Only claims taken from the Mosier & Fischer *Human Factors* paper and from GitHub Docs survived verification. Everything else below that is marked "snippet" comes from search-engine abstracts and should be re-checked against the full text.

---

## 1. Work item 1: baseline audit

### 1.1 Repository metadata (GitHub API, 29 Sep 2026)

| Item | Observation |
| --- | --- |
| Created | 2021-05-22 |
| Last push | 2026-07-08 |
| Description | **Empty** (the field is absent from the API response) |
| Homepage | `https://interplanet.live/` (**set**; the earlier review said it was empty) |
| Topics | None returned |
| Stars / watchers / forks | 1 / 1 / 0 |
| Issues (open and closed) | 0 |
| Licence | GPL-3.0, detected correctly by GitHub |
| Discussions | Disabled |
| Wiki | Enabled (content not checked) |

The earlier finding of "no forks, no issues, a single star" is reproduced. Stars and downloads are not treated as evidence of adoption.

### 1.2 Advertised package names

`grep` over `README.md`, `docs/` and the per-language READMEs finds these install commands:

| Advertised command | Registry check (29 Sep 2026) | Status |
| --- | --- | --- |
| `pip install interplanet-time` | PyPI JSON API 404 | **Not published** |
| `pip install interplanet-ltx` / `"interplanet-ltx[time]"` | PyPI 404 | **Not published** |
| `npm install @interplanet/time` | npm 404 | **Not published** |
| `npm install @interplanet/ltx` | npm 404 | **Not published** |
| `npm install interplanet-ltx` | npm 404 | **Not published** |
| `npm install -g interplanet-time-cli` | npm 404 | **Not published** |
| crates.io `interplanet-time` | 404 | Not published |
| RubyGems `interplanet_time` | 404 | Not published |

Contributing causes found in the repository:

- The repository has **no git tags**, while the publish workflows (`.github/workflows/publish-*.yml`) only run on tags such as `python/planet-time/v*`. So publishing has never been triggered.
- `publish-python.yml` is named "Publish interplanet-ltx to PyPI" but builds `python/planet-time`. The name and the package it builds do not match.
- `publish-js-planet-time.yml` is named "interplanet-planet-time", which is different from the advertised `@interplanet/time`.

### 1.3 Version and conformance claims

| Claim | Evidence | Finding |
| --- | --- | --- |
| "✅ 54 fixture entries pass" in every port (README, `LANGUAGE-SUPPORT.md`) | `c/planet-time/fixtures/reference.json` exists | The fixture file is public. The per-port pass results are not published as CI output (the only workflows are publish workflows), so the claim cannot be reproduced from public evidence without running each port locally. |
| JS planet-time version | `javascript/planet-time/package.json` says 1.4.0; `LANGUAGE-SUPPORT.md` says 1.1.0; site assets use `?v=1.17.0` | Version numbers conflict. |
| LTX default quantum | Spec 3.2 says 5; spec 4.1 example uses 3; `ltx-sdk.js:145` JSDoc says 3; `DEFAULT_QUANTUM = 5` at `ltx-sdk.js:31` | Internally inconsistent. |
| Normative LTX wire format | The spec cites `spec/ltx-spec.md` and `spec/ltx-schema.json` (spec lines 7, 86, 112, 158, 216, 222, 265, 300) | **Neither file exists** in the repository. |
| Conformance golden vectors, `LTX-BRANCH-*` IDs | Cited at spec line 265 | Not found in the repository. |

### 1.4 Website source audit (`demo/`, assumed to be the web root because `og:url` is `https://interplanet.live/`)

| Check | Finding |
| --- | --- |
| `<title>` and `description` | Present on most pages. `playground.html` has an emoji title and no description. `v1.html` (2021 "Mars Meeting Planner") is still deployable and competes with the current app. |
| Canonical links | **No `rel="canonical"` on any page.** |
| `robots.txt`, `sitemap.xml` | **Absent.** |
| Structured data (JSON-LD) | **None.** |
| `<h1>` on the homepage | **None** in `demo/index.html`. The explanatory content is rendered by JavaScript (`sky.js`), so the discovery text is not in the initial HTML. |
| Open Graph | Present on `index.html` only. `ltx.html`, `distance.html` and `events.html` have none. |
| Session content | `ltx.html` carries plans in the URL hash, and `dashboard.html` is a live-session view. Both should stay out of any sitemap. |
| Analytics / Search Console | No evidence in the repository. Recorded as **unknown**. |

### 1.5 Prioritised changes

1. Mark every unpublished package clearly, or publish it through a deliberate release (story IP-D2).
2. Add canonical links, robots.txt, sitemap and an `<h1>` plus static explanatory HTML on the homepage and the LTX page (IP-D1).
3. Restore or remove references to the missing `spec/` files (IP-L1).
4. Fill in the GitHub description and topics (IP-D3).
5. Publish per-port fixture results in CI (IP-D4).

---

## 2. Work item 2: discoverability plan

GitHub Docs (retrieved 29 Sep 2026, verified 3-0) confirm that repository topics help people explore a subject and find projects to contribute to. Topics must use lowercase letters, numbers and hyphens, be 50 characters or fewer, with at most 20 per repository. Anyone can propose featured topics through `github/explore`. GitHub publishes no measured effect of topics on traffic.

Recommended About description (≤ 350 characters):

> Open-source planetary clocks, Earth-Mars meeting planning and LTX, a proposed protocol for collaboration across long communication delays.

Recommended topics, each supported by repository content: `interplanetary`, `mars`, `mars-time`, `planetary-time`, `timekeeping`, `meeting-scheduler`, `asynchronous-communication`, `space-communications`, `delay-tolerant`, `ltx`, `astronomy`, `javascript`, `typescript`, `multi-language`.

These metadata fields can only be set by the repository owner. No tool available in this session could edit them.

The Google Search Central pages (JavaScript SEO, sitemaps, structured data) could not be retrieved from this container. The website recommendations therefore follow the story's own sources S11 to S13, and should be checked against the live Google documentation before implementation.

---

## 3. Work item 3: Space Braiding and patent research

### 3.1 Product and research evidence

| Topic | Evidence (source, quality) | Notes |
| --- | --- | --- |
| What Space Braiding is | "a novel, text-based software designed to facilitate communication between crewmembers in space and mission support on Earth under signal latency" (Fischer et al. 2023 abstract, via ScienceDirect/ADS snippet) | Vendor: Braided Communications Ltd, Scotland (braided.space/about, snippet). |
| Study | Human-in-the-loop study with flight surgeons / mission support personnel and former analog-mission crew (2023 abstract, snippet). Authors: Fischer, Mosier, Schmid, Smithsimmons, Brougham. *Acta Astronautica* 207:411-424. | The sample size, delay values and statistical tests could not be read; the full text was blocked. |
| Findings | Braiding "was preferred over texting for quality of time-delayed communication", "mitigated the impact of communication delay and supported teamwork" (abstract, snippet) | The comparator was ordinary texting. Preference is a subjective measure. At least two authors are connected to the vendor (Smithsimmons, Brougham), so this is not independent evaluation. |
| Funding / trials | The vendor says initial trials were funded by NASA, ESA and UKSA, and that it holds "US Patent 11,397,521" (braided.space, snippet) | Vendor claim; not independently verified. |
| Product mechanics (threads, carousel, input activation) | **Not obtained.** The introduction PDF and the full paper were blocked. | Required for AC7. Must be retrieved before any design comparison. |

### 3.2 Related asynchronous-communication research

| Work | What it found | Evidence quality |
| --- | --- | --- |
| Fischer & Mosier (2014), *Proc. HFES* 58(1), doi:10.1177/1541931214581025 | 24 three-person teams (2 crew, 1 flight controller) solved simulated life-support failures. Medium (text vs voice) was between-groups; delay presence was within-groups. **Under delay, no differences were found between voice and text.** It gives up to 20 min one-way delay as the motivation. | Abstract snippet. The exact delay value used was not visible. |
| Fischer & Mosier (2015), *Proc. HFES*, doi:10.1177/1541931215591001 | Communication protocols to support collaboration under asynchronous conditions | Title and abstract only. |
| Fischer & Mosier (2016), NASA HRP task report "Protocols for asynchronous communication in space operations" | Structured communication templates. Participants were trained before analog missions that included 2 to 4 days of delayed communication with Mission Control. | Snippet; NASA HRR task 1441. |
| Mosier & Fischer (2023; online 2021), *Human Factors* 65(6):1235-1250, doi:10.1177/00187208211047085 | 24 teams of three, voice or text. Protocol training was the between-groups variable. The authors call the protocols "feasible, usable, and effective" and say they were "adopted for training in NASA analog simulations". | **Verified 3-0** against the abstract. Some measures are subjective, and the authors evaluated their own countermeasure. |
| NASA NTRS 20230004112 | Not retrieved | Blocked. |

**Design implications for InterPlanet** (supported by the evidence above):

- The medium (text vs voice) mattered less than structure under delay. This favours investing in **protocol templates** (restating context, numbering questions, explicit acknowledgement) over media features.
- Protocol training is a manipulable variable. That supports an LTX "protocol template" feature and a training mode, and an evaluation design that crosses delay × medium × protocol.

### 3.3 Patent family and status

| Right | Office | Status as reported | Verified from official register? |
| --- | --- | --- | --- |
| US11397521B2, "Communication system", granted 26 Jul 2022, priority 30 Sep 2019, Braided Communications Ltd | USPTO | Granted (vendor and story say so) | **No.** USPTO blocked. The maintenance-fee window (3.5 years after grant, about Jan 2026, 6-month grace to about Jul 2026) has passed, so fee status is **material and unknown**. |
| WO2021064341A1, PCT/GB2020/051711 | WIPO | Published PCT application | **No.** A PCT publication is not a grant anywhere. |
| GB priority application | UKIPO | Implied by the 2019 priority and the GB PCT number | **Unknown** |
| EP, AU and other national phases | EPO, IP Australia | **Unknown** | **No** |

The story's own reading (independent claims 1, 14 and 16; cyclic threads, one-at-a-time input activation, latency-controlled intervals, spacecraft-coordinate information; carousel in dependent claim 8) **could not be checked against the claim text** in this session. The comparison in 3.4 therefore uses those features only as *reported* limitations.

### 3.4 Claim comparison for existing LTX (reported limitations; claim text unverified)

| Jurisdiction and document | Reported limitation | Source | Existing LTX evidence | Present / absent / unclear | Interpretation and open question |
| --- | --- | --- | --- | --- | --- |
| US11397521B2 | Multiple conversation threads presented cyclically | Story summary of claims 1, 14, 16 | No thread object exists. The only agenda concept is a per-segment `label` (`demo/ltx.html:180, 2220`). `buildConferenceAgenda` rotates **speakers**, not threads (`javascript/ltx/ltx-sdk.js:3196-3229`). | **Unclear** | Whether a "thread" could be read to cover a speaker-attributed segment depends on claim construction. Question for counsel. |
| US11397521B2 | Input activated for one thread/party at a time | Story summary | **There are no input controls.** `ltx.html` has no message input. The runner (`tick`, `ltx.html:2240`) is display-only and nothing gates transmission (`transition`, `ltx-sdk.js:2381-2555`). | **Absent** (for the current implementation) | Banner text "You present" (`ltx.html:1442-1457`) is advisory only. |
| US11397521B2 | Intervals controlled by latency | Story summary | Segment length is `q × quantum` and is **never derived from light-time** (`ltx-sdk.js:186-196`). Delay only shifts a receiver's view of a segment's start (`computeSegmentsFor`, `:329-366`) and sets lock and degrade timeouts (`:44-48`). | **Unclear** | Delay-shifted receive windows and delay-based timeouts may need review against "latency-controlled". Question for counsel. |
| US11397521B2 | Spacecraft coordinate information | Story summary | LTX delays are **typed in by hand** (`ltx.html:1685-1689`) or hard-coded in templates (`:1169-1174`). Ephemeris is used only for the clock display. | **Absent** in LTX. Note: `planet-time` computes planet positions and light time (`lightTravelSeconds`), and a future story that feeds these into LTX timing would change this row. | Keep ephemeris out of LTX interval control until reviewed. |
| US11397521B2 claim 8 | Carousel UI | Story summary | No carousel in LTX. | **Absent** | Removing a carousel does not by itself avoid the independent claims. |

**Conclusion (technical, not legal):** Current LTX is a schedule display and signed register without gated message input. The limitations most likely to matter are *unclear* rather than present, and the claim text still has to be obtained.

### 3.5 Prior-art register (dated, pre-30 Sep 2019 unless marked)

| Date | Item | Relevance | Verified? |
| --- | --- | --- | --- |
| Apr 2007 | RFC 4838, Delay-Tolerant Networking Architecture (IETF) | Store-and-forward over long delay | URL identified; fetch blocked |
| 2014 | Fischer & Mosier, HFES 58(1) | Delay × medium experiment | Snippet |
| 2015 | Fischer & Mosier, HFES | Asynchronous communication protocols | Snippet |
| 2016 | Fischer & Mosier, NASA HRP report | Structured templates in analog missions | Snippet |
| 2010-2011 | Mars-500 crew/MCC delay studies (ResearchGate 289197704) | Delay in isolation analog | URL identified only |
| Pre-2019 (dates to confirm) | HI-SEAS, NEEMO, HERA delay protocols; Mars24 (NASA GISS) | Analog practice; Mars time | URLs identified only |
| 1980s onward | Usenet threading, mailing-list digests, IRC, meeting agendas | Threaded, agenda-based discussion | Not researched here |
| **2021-05-22** | InterPlanet repository created | **Later than the 2019 priority date.** Provenance only; not prior art. | GitHub API |
| 2021-2023 (post-priority) | Mosier & Fischer 2021/2023; Fischer et al. 2023 | Later related work | Verified / snippet |

No validity conclusion is drawn.

### 3.6 Questions for a qualified patent professional

1. What is the current status of US11397521B2 (maintenance fees, assignments)? Which national rights exist in AU, GB and EP?
2. How would "thread" and "input activation" be construed? Could a speaker-attributed LTX segment, or a topic board without gated input, fall within them literally or by equivalents?
3. Does using delay to shift receive-window display or to set timeouts amount to "latency-controlled intervals"?
4. For a GPL-3.0 project that distributes an SDK, runs in the browser and hosts on a service, where would a potential act of infringement happen?
5. Do the pre-2019 Fischer/Mosier publications and the DTN literature matter to validity? (A separate question from freedom to operate.)

---

## 4. Work item 4: LTX topic model assessment

### 4.1 Definitions (proposal)

- **Topic:** a persistent organisational object with a stable id and title. It is not tied to time.
- **Contribution:** a signed register entry that belongs to one topic and optionally replies to another contribution.
- **Thread:** the reply tree of contributions inside one topic. It is derived data, not a scheduling unit.
- **Segment:** an existing LTX timed window. It may *reference* topics and never *owns* them.
- **Stream:** reserved in spec 3.5. **Topics must not populate `streams[]`.**

### 4.2 Candidates

| Candidate | Behaviour | Gating by latency / order / segment? | Reported patent limitations touched | Assessment |
| --- | --- | --- | --- | --- |
| A. Persistent topic board | Every authorised topic can be read and drafted at any time; submission goes through the existing register and merge. | **None.** Drafting and submission are always open. | None of the reported limitations: no cyclic presentation, no single-input activation, no latency-derived intervals | **Preferred**, subject to the claim text |
| B. Agenda-linked topics | Segments carry `topicRefs[]`. The UI *recommends* a focus topic per segment, and other drafts stay editable. | Recommendation only; no gating | A rotating agenda could look like "cyclic threads" | Proceed only as advisory metadata. Defer any automatic focus switching until review. |
| C. Asynchronous topic batches | A participant composes contributions across several topics and sends them as one signed batch, and replies arrive later. | None | None reported | Low risk. Builds on the existing register and `LTX-ASYNC`. |

**Explicitly deferred** (needs professional review): locking input to one topic at a time; cycling topic focus automatically on a timer; deriving topic-rotation intervals from light time or ephemeris.

### 4.3 Compatibility

- **v2:** there is no change to v2 plans, and the frozen `imul31` planId (spec 4.3) is untouched.
- **v3:** add an optional `topics[]` and a per-segment `topicRefs[]` under a new capability flag (for example `caps: ["topics/0"]`), included in canonical JSON and therefore in the v3 SHA-256 planId. Nodes without the capability must render the plan without topics and must not rewrite it.
- **No silent upgrade:** the demo currently upgrades a form-built plan to v3 when pair delays are edited (`ltx.html:1747-1759`). That behaviour should be made explicit before a topics extension relies on v3.
- **Register:** add entry types `topic`, `topic_update` and `contribution` next to `ENTRY_PREFIX` (`ltx-sdk.js:2631-2636`), with a reducer on the same conflict rule as `reduceQuestions`.
- **Late messages:** `createSequenceTracker.recordSeq` rejects `seq <= last` as a replay (`ltx-sdk.js:1517-1528`). A late contribution would be dropped rather than reordered. Before topics ship, that rule must be told apart from `orderEntries` deduplication (`:2691-2705`).

### 4.4 Decision record

- **Decision:** proceed with **design and schema drafting only** for candidates A and C. Keep B limited to advisory `topicRefs`. **Do not implement any gated, cyclic or latency-timed topic behaviour.**
- **Gate before production:** obtain the claim text and the official status of US11397521B2 and its family, and get a professional opinion on the questions in 3.6.
- **Evidence still needed:** Space Braiding product mechanics, full text of Fischer et al. 2023, NTRS 20230004112.

---

## 5. Proposed new stories

Stories are grouped by track. The IDs are proposals.

### Track D: discoverability and release hygiene (can start now)

**IP-D1 Crawlable site foundation.** As a researcher searching for Mars time or interplanetary scheduling, I want InterPlanet's public pages to explain themselves in plain HTML, so that I can find and understand the project without running the clock.
*AC:* homepage and `ltx.html` have one `<h1>` and at least 150 words of static explanatory copy; every public page has `rel="canonical"`; `robots.txt` and `sitemap.xml` list only public pages (excluding `dashboard.html`, `playground.html` and hash-state URLs); `v1.html` is either redirected to `/` or marked `noindex`; Open Graph tags are on the principal pages; the SoftwareApplication JSON-LD matches the visible content.

**IP-D2 Truthful installation instructions.** As a developer, I want every install command in the docs to work or be clearly marked, so that my first attempt doesn't fail.
*AC:* each advertised package is either published or labelled "not yet published; install from source" with a tested source command; publish workflow names match the packages they build; a release checklist states the tag convention.

**IP-D3 GitHub About and topics.** *AC:* the description and the topics from section 2 are set by the owner; Discussions is enabled with categories for Q&A, research and interoperability; `good first issue` labels are on at least five issues.

**IP-D4 Public conformance evidence.** As an evaluator, I want per-port fixture results produced by CI, so that "54/54" is reproducible.
*AC:* a GitHub Actions matrix runs the fixture runner for each port and publishes a badge or table; `LANGUAGE-SUPPORT.md` links to the latest run; ports that fail or are skipped are shown as such.

**IP-D5 Version single source of truth.** *AC:* one `VERSIONS.json` (or similar) drives the README tables, `LANGUAGE-SUPPORT.md` and the site `?v=` strings; a CI check fails on mismatch.

**IP-D6 Measurement baseline.** *AC:* owner-accessible Search Console and privacy-respecting analytics are recorded as configured or "not configured"; the baseline figures and the 30/60/90-day checkpoints are recorded in `docs/research/`.

### Track L: LTX specification integrity

**IP-L1 Restore or retire missing normative files.** *AC:* `spec/ltx-spec.md`, `spec/ltx-schema.json` and the golden vectors are either added or their references removed; the spec quantum example matches the normative default of 5; the `ltx-sdk.js:145` JSDoc is corrected.

**IP-L2 Enforce reserved fields.** *AC:* the SDK rejects or warns on a non-empty `streams[]` and on branching fields, per spec 3.5 and 7; conformance tests are added.

**IP-L3 No silent v3 upgrade in the demo.** *AC:* the upgrade to v3 in `ltx.html` asks the user and shows the planId change; v2 plans round-trip unchanged.

**IP-L4 Late-entry handling.** *AC:* document and test the difference between transport replay rejection (`recordSeq`) and register merge ordering (`orderEntries`), so that a delayed but valid register entry is merged rather than dropped.

**IP-L5 Decision reducer.** *AC:* the `decision` entry type gets a reducer that matches the question and action reducers, with tests.

**IP-L6 Delay matrix correctness.** *AC:* fix the `buildDelayMatrix` comment/code mismatch (sum vs max) or change the code, with a test documenting the intended semantics.

### Track T: topic model (gated by the research decision)

**IP-T1 Obtain the official patent record (spike).** *AC:* claim text, prosecution history and maintenance status for US11397521B2, plus register status for WO2021064341A1 and all national phases (AU, GB, EP, US), each with retrieval date; section 3.4 is re-run against the actual claim text.

**IP-T2 Topic schema RFC (design only).** *AC:* a draft spec section for `topics[]`, `topicRefs[]`, the `topic` / `contribution` register entries and a capability flag, with v2/v3 compatibility tests planned. No UI or runtime gating.

**IP-T3 Asynchronous topic batches prototype.** Gated by IP-T1 and a professional opinion. *AC:* a batch of signed contributions across topics is sent, merged and reduced deterministically under duplicate, out-of-order and partitioned delivery.

**IP-T4 Accessible topic board.** Gated. *AC:* keyboard-only operation, screen-reader announcements for arriving contributions with an expected-arrival time, drafts never lost when the recommended focus changes, no input gating.

### Track R: research evaluation

**IP-R1 Protocol templates in LTX.** As a mission-simulation team, I want built-in structured message templates (context restatement, numbered questions, explicit acknowledgement), so that we can apply the Fischer/Mosier protocol approach under delay.
*AC:* templates are available in the LTX question and action entries; a "training mode" explains each template; the source papers are cited.

**IP-R2 Replication study kit.** As a human-factors researcher, I want a configurable InterPlanet scenario that replicates the Fischer/Mosier design (teams of three, simulated life-support fault, delay × medium × protocol), so that results can be compared with published findings.
*AC:* scenario config for 0, 5, 10 and 20-minute one-way delay; text channel with injected delay; protocol on/off; interrupted-delivery condition; exportable logs; outcome measures of task completion, response accuracy, missed context and NASA-TLX workload; an ethics and consent template; no results claimed in advance.

**IP-R3 Comparative evaluation: threaded messaging vs LTX vs LTX + topics.** Gated by IP-T3. *AC:* a preregistered protocol using the IP-R2 kit with three participants and several topics.

**IP-R4 Related-work page.** *AC:* a public page citing Mars24, NASA analog research, Fischer/Mosier and Space Braiding accurately, with no implied affiliation or endorsement.

### Track O: outreach (drafts only, owner approval required)

**IP-O1 Outreach drafts.** *AC:* draft messages to analog-mission programmes and human-factors researchers, plus an optional licensing enquiry to Braided Communications, prepared for the maintainer to review. **Nothing is sent without the maintainer's approval.**

---

## 6. Acceptance-criteria status

| AC | Status |
| --- | --- |
| AC1 Reproducible review | **Partial.** The commit and repository state are recorded. The deployed version could not be reached. |
| AC2-AC6 | Not started (implementation stories IP-D1 to IP-D6) |
| AC7 Research quality | **Partial.** Abstract-level evidence and limitations are recorded; product mechanics are missing. |
| AC8 Patent coverage | **Not met.** Official records were unobtainable, and this is stated explicitly. |
| AC9 Existing and proposed behaviour | **Partial.** Current LTX is mapped with code pinpoints; the claim text is pending. |
| AC10 Prior-art discipline | **Met for what was found.** Dates are recorded, the InterPlanet 2021 date is marked post-priority, and no validity conclusion is drawn. |
| AC11 Compatibility decision | **Met at design level** (section 4.3) |
| AC12 Implementation boundary | **Met** (section 4.4) |

## 7. Sources

- Repository: https://github.com/karwalski/interplanet (commit `ac29d38`)
- Fischer, U., Mosier, K. et al. (2023). Braiding: A novel approach to supporting space/ground communication under signal latency. *Acta Astronautica* 207, 411-424. https://doi.org/10.1016/j.actaastro.2023.03.023 ; https://ui.adsabs.harvard.edu/abs/2023AcAau.207..411F/abstract
- Fischer, U. & Mosier, K. (2014). The impact of communication delay and medium on team performance and communication in distributed teams. *Proc. HFES* 58(1). https://journals.sagepub.com/doi/abs/10.1177/1541931214581025
- Fischer, U. & Mosier, K. (2015). Communication protocols to support collaboration in distributed teams under asynchronous conditions. https://journals.sagepub.com/doi/10.1177/1541931215591001
- Fischer, U. & Mosier, K. (2016). Protocols for asynchronous communication in space operations. https://ute-fischer.lmc.gatech.edu/files/2018/10/Fischer_Mosier-Protocols-for-Asynchronous-Communication-in-Space-Operations-2016.pdf ; NASA HRR task https://humanresearchroadmap.nasa.gov/tasks/task.aspx?i=1441
- Mosier, K. & Fischer, U. (2023). Meeting the challenge of transmission delay: communication protocols for space operations. *Human Factors* 65(6), 1235-1250. https://doi.org/10.1177/00187208211047085 ; https://pubmed.ncbi.nlm.nih.gov/34663105/
- Braided Communications: https://braided.space/about ; https://braided.space/resources/space-braiding ; https://braided.space/wp-content/uploads/2024/01/Space-Braiding-An-introduction-Jul23.pdf
- US11397521B2: https://patents.google.com/patent/US11397521B2/en (not retrievable in this session)
- WO2021064341A1: https://patents.google.com/patent/WO2021064341A1/en (not retrievable in this session)
- RFC 4838: https://www.rfc-editor.org/rfc/rfc4838.html
- GitHub Docs, repository topics: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics (retrieved 29 Sep 2026)
