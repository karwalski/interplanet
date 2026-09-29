# InterPlanet replication kit

**Status:** materials only, 2026-09-29 (story IP-R2, issue #19). **No study has
been run with this kit and no results are claimed.**

## Purpose

This kit lets a human-factors researcher run a team communication study under
signal delay, in a design that follows the published work of Fischer and Mosier
closely enough that results can be compared with it. It provides:

- two fictional life-support fault scenarios with scripted fault injections and
  ground-truth answers,
- a condition matrix for one-way delay, protocol use and interrupted delivery,
- a small Node relay that holds text messages for the configured delay and
  writes JSONL logs,
- a scoring script for task completion, response accuracy, missed-context
  markers and NASA-TLX workload,
- an ethics and consent template.

The kit does not reproduce the Fischer and Mosier scenarios, protocols or
materials. The scenarios and procedures here were written for this kit. No
endorsement by the authors, their institutions or NASA is implied.

## Background

From `docs/research/2026-09-29-discoverability-and-ltx-topics.md`, section 3.2
(abstract-level evidence):

- Fischer and Mosier (2014), *Proc. HFES* 58(1), doi:10.1177/1541931214581025:
  24 teams of three (two crew, one flight controller) solved simulated
  spacecraft life-support failures. Medium (text or voice) was between groups
  and delay presence within groups. Under delay, no differences were found
  between voice and text.
- Fischer and Mosier (2015), *Proc. HFES*, doi:10.1177/1541931215591001:
  communication protocols under asynchronous conditions.
- Fischer and Mosier (2016), NASA HRP task report: structured communication
  templates, with training before analog missions that had 2 to 4 days of
  delayed communication.
- Mosier and Fischer (2023), *Human Factors* 65(6):1235-1250,
  doi:10.1177/00187208211047085: 24 teams of three, voice or text, protocol
  training between groups. The authors describe the protocols as feasible,
  usable and effective and state that they were adopted for training in NASA
  analog simulations.

## Design

| Factor | Levels in this kit | Suggested allocation |
| --- | --- | --- |
| One-way delay | 0, 5, 10, 20 minutes | Within teams, counterbalanced |
| Medium | Text only | Fixed. Voice is **out of scope** for this kit unless the researcher runs it with external tooling that applies the same delays and logging. |
| Protocol | Off (free text) or on (structured templates) | Between teams, as in Mosier and Fischer (2023) |
| Delivery | Continuous, or interrupted (link outages) | Additional conditions at 10 minutes |

**Roles.** Each team has three people: two crew members on the spacecraft site
and one flight controller on the ground site. Messages between the two crew
members are immediate. Messages between sites are held for the one-way delay.

**Information split.** The crew see telemetry and alerts. The flight controller
holds the troubleshooting tables. Neither side can answer alone, so every
correct answer depends on at least one exchange across the delay.

**Scenario variants.** `co2-removal` and `o2-pressure` are parallel forms for
counterbalancing when delay is varied within teams. Their equivalence in
difficulty has **not** been established; pilot them first. A four-level
within-team delay factor needs four forms or a reduced design, which the
researcher must decide and preregister.

**Session length.** Each scenario runs for 150 minutes of scenario time with
fault deadlines at 90 and 140 minutes. At 20 minutes one-way delay a question
and answer take at least 40 minutes, so the deadlines are tight by design.
Pilot the timing before data collection.

## Files

```
conditions.json            condition matrix (delay, protocol, interruptions)
scenarios/co2-removal.json scenario A: CO2 removal and condensate faults
scenarios/o2-pressure.json scenario B: oxygen generation and pressure faults
relay/relay.js             delay-injecting relay (library and CLI)
relay/client.html          minimal text client served by the relay
scoring/score.js           scoring (library and CLI)
scoring/tlx-template.csv   header for NASA-TLX data entry
ethics/consent-template.md ethics and consent template
tests/                     node tests for relay and scoring
```

### Conditions

| Id | One-way delay | Protocol | Delivery |
| --- | --- | --- | --- |
| D0-P0, D0-P1 | 0 min | off, on | continuous |
| D5-P0, D5-P1 | 5 min | off, on | continuous |
| D10-P0, D10-P1 | 10 min | off, on | continuous |
| D20-P0, D20-P1 | 20 min | off, on | continuous |
| D10-P0-INT, D10-P1-INT | 10 min | off, on | outages at 30-50 and 95-105 min; messages held until the outage ends |
| D10-P0-DROP | 10 min | off | exploratory: messages that would arrive during the 30-50 min outage are lost |

An outage applies to arrivals at the receiving site. A message whose arrival
time falls inside an outage is either held until the outage ends (`hold`) or
lost (`drop`). Same-site messages are never affected.

## Running a session

Requires Node 18 or later. There are no dependencies.

```bash
cd research/replication-kit
node relay/relay.js --condition D10-P1 --team T01 --scenario scenarios/co2-removal.json
# Each participant opens http://127.0.0.1:8787/?role=crew1 (or crew2, fc)
# on their own machine or screen. Use a reverse proxy or SSH tunnel for
# remote participants; the relay binds to 127.0.0.1 only.
curl -X POST http://127.0.0.1:8787/start   # start the clock and fault injections
# Ctrl+C ends the session and closes the log.
```

Options: `--port`, `--log <path>` (default `logs/<team>-<condition>-<scenario>.jsonl`),
`--conditions <path>`, and `--time-scale <k>` which multiplies every duration.
Use `--time-scale` only for piloting and testing (for example `0.1` runs a
150-minute scenario in 15 minutes). Record the value; the scorer reads it from
the log.

The participant page never shows the configured delay. In the protocol-on
condition it offers plain-text skeletons for question, action, status and
acknowledgement messages, following the parts used by
`javascript/ltx/ltx-protocol-templates.js` (context restatement, numbered items,
readback, explicit reply time). Protocol training itself (what to say and why)
is delivered by the researcher before the session; the training texts in that
module can be used as a starting point.

Answers are submitted through the answer form (fault id, item id, answer). They
go straight to the log and are not delayed, because they represent reports to
the experimenter rather than messages across the link.

### Log format

One JSON object per line. Every event has `t` (ISO time), `tMs` (ms since
session start), `event`, `teamId` and `conditionId`. Event types:
`config`, `session_start`, `inject`, `send` (with `sentMs`,
`scheduledDeliverMs`, `heldMs`, `dropped`), `deliver`, `drop`,
`interruption_start`, `interruption_end`, `answer`, `client_connect`,
`client_disconnect`, `session_end`. A message to several recipients is logged
as one `send` per recipient, sharing a `msgId`.

## Scoring

```bash
node scoring/score.js --log logs/T01-D10-P1-co2-removal.jsonl \
  --scenario scenarios/co2-removal.json \
  --tlx tlx.csv --coding-sheet coding/T01-D10-P1.csv --out results/T01-D10-P1.json
```

| Measure | Definition in `score.js` |
| --- | --- |
| Task completion | A fault is completed when every item has an answer at or before the fault deadline. `completedCorrectly` additionally requires every final answer to be correct. |
| Response accuracy | Proportion of items whose last on-time answer matches the scenario's accepted answers (case and spacing ignored). Time to first correct answer is reported per item. |
| Missed-context markers | Provisional automatic proxies on cross-site messages: `clarification_request` (matches a scenario pattern such as "say again"), `crossed_message` (sent while a message from the recipient to the sender was still in transit), `no_context_restatement` (mentions none of the context keywords of the faults active at that time). |
| Workload | NASA-TLX: raw TLX (mean of six 0-100 subscales), and weighted TLX when the 15 pairwise-comparison weights are present. |

The automatic missed-context markers are crude and will produce false positives
and false negatives. `--coding-sheet` writes one CSV row per message copy with
the automatic markers and empty `coder_markers` and `coder_id` columns, so that
two independent coders can code missed context by hand and inter-rater
agreement can be reported. Use the hand-coded values for analysis and report
the automatic ones only as a check.

NASA-TLX data are entered by the researcher into a copy of
`scoring/tlx-template.csv` (one row per participant per session). Administer the
official NASA-TLX instrument; this kit only imports the numbers.

## Tests

```bash
node tests/run.js
```

The tests use delays of tens of milliseconds and a tiny time scale. They check
the delay and outage logic, SSE delivery, logging, and the scoring rules. They
say nothing about any study outcome.

## Ethics

A study with participants needs approval from the researcher's institutional
ethics committee (IRB or equivalent) before any recruitment.
`ethics/consent-template.md` is a starting template only. Running a study is a
separate step taken by a qualified researcher; it is not part of this
repository's work.
