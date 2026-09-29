# Comparative evaluation protocol: threaded messaging vs LTX vs LTX with topics

**Status:** draft protocol, preregistration-ready in structure, 2026-09-29
(story IP-R3, issue #20). **Not preregistered, not approved, not run.** No
results exist and none are implied.

**Depends on:**

- Issue #16 (topic prototype). The LTX + topics condition cannot run until a
  topic prototype exists. The topic model is experimental.
- Issue #14 (patent review). The topic condition must not be built or run
  until the review described in
  `docs/research/2026-09-29-discoverability-and-ltx-topics.md` (sections 3.3 to
  3.6 and decision record 4.4) is complete.
- Issue #19 (replication kit, `research/replication-kit/`). This protocol reuses
  its relay, logging, scoring and consent template, and needs the extensions
  listed in [Materials](#materials).
- Issue #18 (protocol templates, `javascript/ltx/ltx-protocol-templates.js`).

**Running the study with participants is a separate human step.** It requires a
qualified principal investigator, institutional ethics approval, and
preregistration of the final version of this document before recruitment.
Nothing in this repository runs a study.

---

## 1. Background and rationale

Abstract-level evidence summarised in section 3.2 of the research note:

- Fischer and Mosier (2014), doi:10.1177/1541931214581025, found no differences
  between voice and text under delay in 24 teams of three solving simulated
  life-support failures.
- Mosier and Fischer (2023), doi:10.1177/00187208211047085, manipulated
  protocol training between groups in 24 teams of three and describe the
  protocols as feasible, usable and effective.
- Fischer et al. (2023), *Acta Astronautica* 207:411-424, report that the Space
  Braiding tool was preferred over ordinary texting for time-delayed
  communication. At least two authors are connected to the vendor, the
  comparator was ordinary texting, and preference is a subjective measure.

Together these suggest that under delay, how messages are structured and
organised matters more than the medium. They leave open whether organising a
conversation into persistent topics helps teams handle several concurrent
issues under delay, compared with ordinary threaded chat or with LTX's existing
schedule and register structure.

This study asks that question. It does **not** compare InterPlanet with Space
Braiding, and its results would not say anything about Space Braiding.

## 2. Research questions and hypotheses

**RQ1.** Does LTX with persistent topics reduce missed context, compared with
ordinary threaded messaging and with unextended LTX, when a team works on
several concurrent issues under delay?

**RQ2.** Does it change task completion, response accuracy and workload?

**RQ3.** Do any differences change with delay length or with interrupted
delivery?

Confirmatory hypotheses (directional where a direction is predicted):

| Id | Hypothesis | Test |
| --- | --- | --- |
| H1 | Hand-coded missed-context events per 100 cross-site messages are lower in LTX + topics (C) than in threaded messaging (A). | Contrast C vs A |
| H2 | Hand-coded missed-context events per 100 cross-site messages are lower in C than in unextended LTX (B). | Contrast C vs B |
| H3 | Response accuracy is higher in C than in A. | Contrast C vs A |
| H4 | NASA-TLX workload differs between C and A (two-sided: topics may reduce search effort or add overhead). | Contrast C vs A |

Secondary and exploratory (reported as such): B vs A on all outcomes; task
completion; time to correct answer; interaction of interface with delay;
behaviour around interrupted delivery; per-topic neglect (topics with no
cross-site message for longer than one round trip while an item is open).

## 3. Design

- **Interface (within teams, 3 levels):** A threaded messaging, B unextended
  LTX, C LTX + topics. Order counterbalanced with a Latin square across teams.
  Each interface is paired with a different scenario form, and the pairing is
  also counterbalanced.
- **One-way delay (between teams, 3 levels):** 5, 10 or 20 minutes, assigned
  at random with equal allocation. A 0-minute control is not included because
  the question is about behaviour under delay; add it only if the pilot shows a
  need.
- **Interrupted delivery (within every session):** each session contains one
  scripted link outage in `hold` mode (messages arriving during the outage are
  delivered when it ends), at the same scenario time in every form. This makes
  interruption a common stressor rather than a factor.
- **Medium:** text only.
- **Protocol:** all three interfaces get the same protocol training and the
  same template skeletons (context restatement, numbered items, readback,
  explicit reply time). Protocol is held constant so that the comparison
  isolates the interface structure.

### 3.1 Interface definitions

| Condition | What participants use | Held constant |
| --- | --- | --- |
| A. Threaded messaging | A chat with a main channel and reply threads, like common workplace chat tools. No schedule, no registers. | Delay, outage, templates, scenario content |
| B. Unextended LTX | An LTX session plan (segments, transmit and receive windows) with the question and action registers. No topic objects. | Same |
| C. LTX + topics | B plus a persistent topic board: every topic can be read and drafted at any time, and contributions are submitted through the register. | Same |

Condition C must follow decision record 4.4 of the research note: **no input
gating, no automatic cycling of topic focus, no topic intervals derived from
light time.** If the patent review (#14) restricts C further, this protocol
must be revised before preregistration.

## 4. Participants

- **Unit:** teams of three. Two participants act as crew members on the
  spacecraft site and one as flight controller on the ground site. Roles are
  assigned at random within a team and stay fixed across the three sessions.
- **Inclusion:** adults; fluent in the study language; able to attend all three
  sessions; normal or corrected vision sufficient for screen reading.
- **Exclusion at enrolment:** previous participation in an InterPlanet or
  replication-kit study; involvement in developing InterPlanet or the topic
  prototype; current employment by, or financial interest in, a vendor of
  delay-tolerant communication tools.
- **Population:** to be stated at preregistration (for example university
  students, or people with operations or aviation experience). This choice
  limits generalisation (see section 10).

### 4.1 Sample size and power

Numbers are not fixed here because there is no defensible effect-size estimate
for a topic interface under delay. The abstract-level sources do not report
effect sizes that transfer to this design, and the interface and outcome
definitions differ.

Qualitative considerations:

- The published studies used 24 teams of three. Matching that count aids
  comparison but is not a power justification.
- The within-team interface factor increases sensitivity for H1 to H4 because
  each team is its own control. The between-team delay factor has much less
  power: with 24 teams there would be 8 teams per delay level, which is enough
  only for a large delay-by-interface interaction. RQ3 is therefore
  exploratory unless the sample is much larger.
- Missed-context counts are overdispersed and depend on how many messages a
  team sends, which reduces power relative to a continuous outcome.
- **Before preregistration**, run a pilot (see section 7) to estimate
  between-team variance, message volume and coding reliability, then run a
  simulation-based power analysis for H1 using the mixed model in section 8.
  Fix the number of teams and the smallest effect size of interest at that
  point, and record both in the preregistration.

## 5. Materials

- **Scenario forms:** three parallel forms, each with at least three concurrent
  topics (for example a life-support fault, a crew-health consultation and a
  schedule or resource conflict), overlapping in time so that at least two
  topics are open at once for most of the session. Each topic has scripted
  injections, an information split between sites, and ground-truth answers,
  in the format of `research/replication-kit/scenarios/*.json`. The two existing
  kit scenarios are single-thread and are **not sufficient**; new forms must be
  written and piloted for equivalence.
- **Relay:** `research/replication-kit/relay/relay.js` for delay, outage and
  JSONL logging.
- **Clients (to be built):**
  1. a threaded chat client for A, on the relay, logging `threadId` and
     `replyTo` for each message;
  2. an LTX client for B that sends question, action and acknowledgement
     entries through the relay (the protocol templates module already produces
     register-compatible payloads);
  3. an LTX + topics client for C from the topic prototype (#16), logging
     `topicId` for each contribution.
  All clients must log to the same schema so that scoring is identical.
- **Training:** a written protocol-training script, identical across
  interfaces, based on the training texts in
  `javascript/ltx/ltx-protocol-templates.js`, plus a short interface tutorial
  per condition with a practice task at 0 delay.
- **Questionnaires:** official NASA-TLX after each session; a short
  post-session questionnaire on perceived coordination (exploratory; instrument
  to be chosen and cited at preregistration); a final interface preference
  question (exploratory).
- **Consent:** `research/replication-kit/ethics/consent-template.md`, adapted
  and approved.

## 6. Measures

| Measure | Definition | Role |
| --- | --- | --- |
| Missed context | Events coded by two trained coders, blind to condition where the interface does not reveal it, on the coding sheet from `scoring/score.js`. Event types: clarification request, action or answer that ignores information already sent, reply to the wrong topic or item, duplicated question already answered, crossed message that causes rework. Rate per 100 cross-site messages. | Primary (H1, H2) |
| Response accuracy | Proportion of scenario items whose last on-time answer matches ground truth (`score.js`). | Confirmatory (H3) |
| Task completion | Proportion of topics with every item answered by the deadline. | Secondary |
| Time to correct answer | Minutes from a topic's first injection to its first correct answer. | Secondary |
| Workload | Raw NASA-TLX per participant per session; weighted TLX if weights are collected. | Confirmatory (H4) |
| Topic neglect | Minutes an open topic goes without any cross-site message, beyond one round trip. | Exploratory |
| Automatic markers | `clarification_request`, `crossed_message`, `no_context_restatement` from `score.js`. | Exploratory, and as a check on coding |
| Manipulation check | Share of messages using threads (A), register entries (B) or topics (C). | Descriptive |

Coding reliability: Cohen's kappa (or Krippendorff's alpha) on event type,
target at least 0.7 on the pilot before main coding starts. Disagreements are
resolved by discussion, and both the pre-discussion agreement and the resolved
codes are reported.

## 7. Procedure

1. **Pilot** (not part of the confirmatory sample): at least two teams at the
   longest delay, to check timing, clients, logging, coding reliability and
   scenario difficulty. Revise materials, then freeze them.
2. **Preregister** the frozen protocol, materials, sample size and analysis
   code, for example on OSF.
3. **Session 0:** consent, demographics, role assignment, protocol training,
   interface tutorial for the first interface.
4. **Sessions 1 to 3:** one interface each, in the assigned order, each with its
   scenario form and the team's delay. Short tutorial before each new
   interface. NASA-TLX and post-session questionnaire after each session.
5. **Debrief** after the last session, including the outage and any details
   withheld during the study.

Sessions for one team should be at least [interval, to be set] apart and within
[window] to limit fatigue and forgetting.

## 8. Analysis plan

All analysis code is written and run on simulated data before
preregistration.

- **H1, H2:** negative binomial generalised linear mixed model of missed-context
  counts with log(cross-site messages) as offset; fixed effects interface
  (treatment-coded, reference C), delay, session order and scenario form;
  random intercept for team. Report rate ratios with 95% confidence intervals.
- **H3:** binomial generalised linear mixed model at item level (correct or
  not); fixed effects as above; random intercepts for team and item.
- **H4:** linear mixed model of raw TLX; fixed effects as above plus role;
  random intercepts for team and for participant within team.
- **Multiplicity:** Holm correction across H1 to H4 at family-wise alpha 0.05.
  Secondary and exploratory analyses are reported without correction and
  labelled as such.
- **RQ3:** add interface by delay interaction terms; exploratory.
- **Interrupted delivery:** compare missed-context rates in the window from the
  outage start to one round trip after it ends against the rest of the session;
  exploratory.
- **Missing data:** mixed models use all available sessions. No imputation for
  the primary analysis. A sensitivity analysis restricted to teams with all
  three sessions is reported.
- **Deviations** from the preregistration are listed in the report with
  reasons.

## 9. Exclusion and stopping rules

**Session-level exclusion** (decided from logs and notes before any outcome is
examined, by someone not scoring outcomes):

- relay or client failure causing more than [5] minutes of unscripted message
  loss or delay, shown in the log;
- a participant absent for more than [10] minutes of the session;
- the wrong condition, delay or scenario form run (protocol deviation).

Excluded sessions may be rerun once with a fresh scenario form if one is
available; otherwise the session is missing.

**Team-level exclusion:** a team that completes no valid session. Teams that
under-use the interface feature (manipulation check) are **kept** in the
primary analysis; a per-protocol analysis is secondary.

**Participant-level:** a participant who withdraws is removed from analysis
as the consent form describes; the team's remaining sessions are treated as
excluded because the team structure is broken.

**Stopping rules:**

- Recruitment stops when the preregistered number of teams with valid data is
  reached, or on a preregistered end date, whichever comes first.
- There is **no optional stopping on outcomes** and no interim outcome
  analysis. Interim checks cover data quality and coding reliability only, and
  are done by someone not looking at condition differences.
- The study is paused at once for any adverse event, participant complaint
  that the ethics committee must see, or data breach, and resumes only with the
  committee's agreement.

## 10. Threats to validity

**Conflict of interest.** Fischer et al. (2023) evaluated Space Braiding with
at least two vendor-linked authors. This evaluation would involve InterPlanet's
maintainer, who designed LTX and would design the topic extension. That is the
same kind of conflict. Mitigations:

- a principal investigator and data analyst who are independent of the
  InterPlanet project;
- preregistration of hypotheses, measures, exclusions and analysis code before
  data collection;
- coders who did not build the clients, blind to hypotheses and, where
  possible, to condition;
- all outcomes reported, including null and unfavourable ones;
- open materials, anonymised data and analysis code, subject to ethics
  approval;
- a conflict-of-interest statement naming the maintainer's role;
- optionally, an adversarial collaborator from outside the project reviewing
  the protocol and the report.

**Internal validity.**

- Order and learning effects across three sessions (mitigated by Latin square
  counterbalancing; order is in the models).
- Non-equivalent scenario forms (mitigated by piloting and counterbalancing
  the form-interface pairing; form is in the models).
- The interfaces differ in more than topics: B and C add a schedule and
  registers that A lacks. The C vs B contrast isolates topics; the C vs A
  contrast does not.
- Novelty: participants may favour or struggle with an unfamiliar interface.
- Experimenter effects, especially if the maintainer delivers training (the
  maintainer should not run sessions).

**Construct validity.**

- Missed context is a coded construct; reliability must be shown.
- Automatic markers are crude proxies and are not primary outcomes.
- One NASA-TLX per session measures overall workload, not workload at the
  moments that matter.

**External validity.**

- Lay or student participants are not flight crews or controllers.
- Delays of 5 to 20 minutes over sessions of a few hours differ from analog
  missions with days of delay (Fischer and Mosier 2016 describe 2 to 4 days)
  and from real operations.
- Text only; no voice.
- Fictional scenarios with fixed answers.
- The topic condition is constrained by the patent position (no gating, no
  cycling). Results do not generalise to designs that use those features.

**Statistical conclusion validity.**

- Small number of teams, especially for the between-team delay factor.
- Overdispersed count outcomes.
- Several outcomes: handled with a small confirmatory set and Holm correction.

## 11. Ethics and data

Institutional ethics approval is required before recruitment. Use the consent
template in the replication kit, adapted to this design (three sessions, three
interfaces). Chat logs may contain identifying text and must be reviewed before
any sharing.

## 12. Preregistration checklist

- [ ] #16 topic prototype available and frozen.
- [ ] #14 patent review complete; condition C confirmed or revised.
- [ ] Three concurrent-topic scenario forms written and piloted.
- [ ] Clients for A, B and C built with a common log schema.
- [ ] Pilot complete; coding reliability of at least 0.7 reached.
- [ ] Simulation-based power analysis done; number of teams and smallest effect
      size of interest fixed.
- [ ] Analysis code run on simulated data and archived.
- [ ] Independent PI and analyst named; conflict-of-interest statement written.
- [ ] Ethics approval obtained.
- [ ] Preregistration submitted; link added here.

## References

- Fischer, U. and Mosier, K. (2014). *Proc. HFES* 58(1). doi:10.1177/1541931214581025
- Fischer, U. and Mosier, K. (2015). *Proc. HFES*. doi:10.1177/1541931215591001
- Fischer, U. and Mosier, K. (2016). Protocols for asynchronous communication in
  space operations. NASA Human Research Program task report.
- Mosier, K. and Fischer, U. (2023). *Human Factors* 65(6):1235-1250.
  doi:10.1177/00187208211047085
- Fischer, U., Mosier, K. et al. (2023). *Acta Astronautica* 207:411-424.
  doi:10.1016/j.actaastro.2023.03.023
- Hart, S. G. and Staveland, L. E. (1988). Development of NASA-TLX (Task Load
  Index): results of empirical and theoretical research. In *Human Mental
  Workload*, Advances in Psychology 52, 139-183.
