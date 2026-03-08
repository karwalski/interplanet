# Interplanetary Work Scheduling: Timezone Conventions, Communications Delay, and the AI-Integrated HDTN Scheduler

*by Matthew Watt — February 2026*

---

## Abstract

As human activity expands toward the Moon, Mars, and beyond, the practical challenge of coordinating work across solar system distances demands infrastructure that does not yet exist in any formal sense. This paper examines the interlocking problems that define interplanetary work scheduling: radically different planetary day lengths that cannot all be reconciled with human circadian biology; one-way communications delays ranging from 1.3 seconds to Earth-Moon to 22 minutes to Mars; periodic solar conjunction blackouts lasting up to several weeks; a relay network in critical disrepair; and a legal vacuum in which no international labour standards apply beyond Earth's atmosphere. It proposes a system of planetary timezone conventions — with registered prefixes AMT, LMT, MMT, VMT, JMT, SMT, UMT, and NMT — aligned to RFC 9557 and designed to separate geographic location reference from work scheduling. It examines the communications architecture needed to make interplanetary scheduling reliable, including Delay-Tolerant Networking (DTN), the High-Rate DTN (HDTN) stack already achieving 900 Mbps laser links, and the relay geometries proven capable of eliminating conjunction blackouts entirely. Finally, it introduces the AI-Integrated HDTN Scheduler: an experimental concept combining machine learning, ephemeris integration, and autonomous replanning into a cost-effective, production-pathable system designed for testing in the CHAPEA analog environment and eventual use in 2030s Mars operations.

---

## 1. The Core Problem: Time Across Interplanetary Distances

### 1.1 The Diversity of Planetary Days

We take timekeeping for granted on Earth. We probably shouldn't. The 24-hour timezone system standardised in the 1880s was driven by the practical needs of railway scheduling, not any deep philosophical principle. Before standardisation, every town kept its own local noon, and the patchwork of local times became a practical problem only when trains started connecting cities faster than the time differences could be ignored. We solved it with coordination — international agreement, standard zones, UTC as the global reference.

We are about to face the same problem again, scaled to the solar system, with communication delays of minutes to hours rather than telegraph delays of seconds. And the diversity of day lengths across the solar system makes Earth's timezone challenge look trivial.

Mars has a solar day — a sol — of 24 hours and 39 minutes and 35 seconds, or 88,775.244 seconds. That 2.75 percent difference sounds manageable. And for a few days, it is. But the drift accumulates. After 36 days, a Martian noon that started aligned with Earth noon has drifted to Earth midnight. After approximately 18 months the Martian schedule has completed a full inversion and returned to rough alignment. Anyone living on Mars and synchronising to the local sun — which you must, for solar power, surface operations, temperature management — experiences a schedule that continuously slides against every fixed Earth reference point.

Mercury's solar day is 175.94 Earth days. Not 175 hours: 175 days. One sunrise to the next takes more than half an Earth year. The surface temperature swings from 430°C in full sunlight to -180°C in permanent shadow. Mercury's day is a geological fact about a planet, not a scheduling unit for human beings.

Venus is stranger still. Its solar day is 116.75 Earth days. Its retrograde rotation means the sun rises in the west and sets in the east. Its atmosphere — 96 percent carbon dioxide, 90 times the pressure of Earth's at the surface — has run a complete greenhouse effect, holding surface temperatures near 465°C day and night, everywhere on the planet. Venus local time varies by approximately 20 minutes peak-to-peak due to angular momentum exchange between the solid body and the massive atmosphere (Margot et al. 2021, *Nature Astronomy*), meaning even a "best-fit at epoch" approximation accumulates meaningful error over months.

The Moon is tidally locked to Earth, one face always toward us, one always away. A lunar day — sunrise to sunrise — is 29.5 Earth days: two weeks of continuous sunlight, then two weeks of darkness and extreme cold. The far side has never had a direct line of sight to Earth in the history of the solar system.

The gas giants have no solid surface, and their rotation periods range from about 10 hours (Jupiter) to about 16 (Neptune). Human presence at Jupiter would be in floating habitats in the upper atmosphere, surrounded by winds running at hundreds of kilometres per hour. "Local time" on a gas giant is a geographical reference convention, not a circadian driver.

### 1.2 The Communications Reality

The day length problem alone would be challenging. But interplanetary scheduling has a second, harder constraint: the speed of light is finite, and the distances involved are vast.

Earth-Mars one-way signal delay ranges from approximately 3.1 minutes at closest approach (opposition, ~55.8 million km) to approximately 22.3 minutes near solar conjunction (~401 million km). Round-trip delays of 6 to 45 minutes make real-time conversation physically impossible for much of the synodic cycle. By the 120-second threshold established in the Draft Standard accompanying this project — above which asynchronous communication becomes structurally necessary — every Earth-Mars exchange is always asynchronous. There is no exception. You can never have a real-time meeting with Mars.

The threshold of 120 seconds is calibrated to the Earth-Moon boundary: one-way Earth-Moon delay is approximately 1.28 seconds, always well below threshold and supporting genuine real-time conversation. Earth-Mars is always above it. Earth-Jupiter is 33 to 53 minutes one-way. Earth-Saturn is 67 to 87 minutes. These are not scheduling challenges with clever workarounds; they are physical facts about the solar system.

Solar conjunction compounds the problem. When a planet passes behind the Sun from Earth's perspective, the solar corona introduces interference that makes reliable communication impossible. For Mars, solar conjunction occurs every 779.94 Earth days — the synodic period — and each conjunction imposes a communications blackout of approximately 14 days (the command moratorium typical in current mission operations), with complete signal loss for 1 to 1.5 days when Mars is directly behind the solar disk. The precise duration depends on frequency band: X-band typically loses 17–24 days per conjunction; Ka-band's exclusion zone is much tighter and can reach zero-day blackouts at favourable geometries (as in the 2034 conjunction); optical links suffer the longest outages of all, 60–78 days, because the Sun's disk is overwhelmingly bright at optical wavelengths (Morabito et al. 2018; Howard and Seibert 2020).

Any Mars mission lasting longer than one synodic period — approximately 780 days — will experience at least one solar conjunction. Any crewed Mars mission will experience multiple. These are not edge cases to be planned around; they are core scheduling infrastructure.

### 1.3 Relativistic Effects and the Lunar Time Standard

At the precision required for deep space navigation and atomic clock synchronisation, relativistic effects cannot be ignored. Lunar Coordinate Time (LTC, also TCL), adopted by the IAU at its 32nd General Assembly in Cape Town in August 2024 and formalised through a White House OSTP directive of April 2024 mandating NASA deliver a strategy for LTC implementation by December 31, 2026, is defined with a gravitational time dilation offset of 56.02 microseconds per day relative to Earth (Ashby and Patla, NIST, 2024). This is not a correction for mission-critical precision; it is a fundamental property of timekeeping at a different gravitational potential. China's Purple Mountain Observatory published LTE440 in December 2025 — the first ready-to-use lunar timekeeping software, achieving approximately 0.15 nanosecond accuracy through 2050.

For Mars, gravitational time dilation accumulates at approximately 477 µs/day average relative to Earth (±226 µs/day seasonal variation; perihelion ~251 µs/day, aphelion ~703 µs/day) — negligible for daily scheduling purposes but relevant for long-duration atomic clock synchronisation and precision timing in deep space relay networks. (Ashby & Patla 2025, *Astronomical Journal* 171:2.)

### 1.4 The Human Precedent: NASA's Mars-Time Engineers

We already have direct human experience of what Mars-time operations feel like. Every NASA Mars surface mission — from Pathfinder (1997) through Spirit and Opportunity, Curiosity, and Perseverance — has operated critical mission phases on Mars time. Engineers synchronise their shifts to the Martian sol because rover operations are timed to local Martian light: solar panel charging, surface traverses, camera operations, and temperature-sensitive activities all depend on knowing where the sun is on Mars, not on Earth.

So for the duration of each mission's most intensive phase, teams work a 24-hour-39-minute day. Their 9 AM shift slides to 9:39 AM Earth time, then 10:18 AM, then 10:57 AM. After a few weeks their Martian morning falls in the middle of the Earth night. Families adjust. Social lives get complicated. Engineers wear two watches. The practice has been consistent across missions: Mars-time operations last approximately 90 sols after each landing, after which teams vote to revert to Earth schedules. The MER Curiosity team's vote to extend past 90 sols returned, in the words of the team, a resounding No.

The physiological evidence explains why. Average sleep duration during Mars-time operations falls to approximately 5.98 hours per sol — well below the recommended minimum of 7 to 9 hours. Under dim lighting, 100 percent of experimental subjects fail to entrain to the Mars sol. But entrainment is not impossible: Scheer et al. (2007, *PLOS ONE*) demonstrated successful entrainment under approximately 450 lux of moderately bright light, and approximately 87 percent success was confirmed during the 78-day Phoenix mission (Barger et al. 2012). The Mars sol is achievable for human biology — but it requires deliberate engineering of the light environment, not just determination.

NASA's CHAPEA (Crew Health and Performance Exploration Analog) programme is generating the first systematic data from a simulated Mars surface habitat. Mission 1 completed in July 2024. Mission 2 is ongoing through October 2026. This data — on sleep patterns, circadian health, work performance, psychological wellbeing, and social functioning under Mars-analog conditions — will be the most important evidence base available for designing humane Mars work schedules.

---

## 2. Planetary Timezone Conventions

### 2.1 The Core Principle: Location Reference vs. Work Schedule

The timezone system developed for this project grows from a single key insight: *where you are on a planet and when you work are two different questions, and they need different answers.*

On Earth, those questions are linked. Your timezone tells you what local time it is, and your work schedule follows from that local time. That linkage works because every location on Earth shares an approximately 24-hour day. Shift your work schedule by a few hours and you get jet lag for a few days; you do not fundamentally decouple from the planet's light-dark cycle.

On Mercury or Venus, that linkage breaks down completely. A timezone zone for Mercury should tell you where you are on the planet's surface — your longitude, your location relative to the long solar cycle, which direction the sun will eventually appear from. It does not tell you when you eat breakfast. Those decisions are driven entirely by Earth-clock shift schedules, independent of any local solar reference.

The timezone system therefore separates two distinct functions: timezone zones as geographic location identifiers (24 zones of 15 degrees longitude each, per body, mirroring Earth's structure), and work scheduling models that reflect each body's biological compatibility with human circadian rhythms.

### 2.2 Registered Zone Prefixes

The project defines eight timezone zone systems, each identified by a three-letter prefix:

| Prefix | Body | Full Name | Work Model |
|--------|------|-----------|------------|
| AMT | Mars | Arean Mean Time | Sol-synchronised (5 sols on / 2 rest) |
| LMT | Moon | Lunar Mean Time | Earth-clock shifts |
| MMT | Mercury | Mercury Mean Time | Earth-clock shifts |
| VMT | Venus | Venus Mean Time | Earth-clock shifts |
| JMT | Jupiter | Jupiter Mean Time | Grouped 24h Earth periods |
| SMT | Saturn | Saturn Mean Time | Grouped 24h Earth periods |
| UMT | Uranus | Uranus Mean Time | Grouped 24h Earth periods |
| NMT | Neptune | Neptune Mean Time | Grouped 24h Earth periods |

An additional designation, HMT (Heliocentric Mission Time), is defined as a neutral reference layer for in-transit operations, derived from Mission Elapsed Time and ephemeris-anchored to the heliocentric reference frame. HMT does not correspond to local solar time on any body; it is the scheduling reference used when a crew is between planets and neither the origin body's nor the destination body's timezone is operationally relevant.

### 2.3 Timestamp Format and RFC 9557 Alignment

Planetary timestamps in this system follow the structural conventions of RFC 9557 (Internet Extended Date/Time Format, April 2024), which defines an IANA registry for timestamp suffix annotations. The format carries both the local planetary time and a UTC cross-reference, ensuring that any receiver who cannot parse the planetary date component can still extract the UTC instant:

```
MY38-221T14:32:07/2026-02-19T09:15:23Z[Mars/AMT+9]
```

Here `MY38-221` designates Mars Year 38, Sol 221; the UTC reference follows the slash; and the suffix identifies the body and zone. For bodies using Gregorian calendar dates internally (Moon, Mercury, Venus, and gas giants), the format is:

```
2026-02-19T14:32:07Z[Moon/LMT+1]
```

The `/` separator is the minimum interoperability guarantee: any system that only understands UTC can strip everything before and after the slash and receive a valid RFC 3339 timestamp.

A registration of the `body` suffix key in the IANA Timestamp Suffix Tag Keys registry is proposed through the Draft Standard accompanying this project (DRAFT-STANDARD.md), pending broader community review.

### 2.4 Key Resolved Debates in Planetary Constants

Several planetary constants relevant to timezone assignment have been the subject of scientific uncertainty or active debate. The following values are used by this project, with reasoning:

**Saturn rotation period:** The project uses the Mankovich, Marley, Fortney & Mozshovitz (2019) ring seismology value of 10 hours 33 minutes 38 seconds, which probes Saturn's interior rotation directly via normal-mode oscillations detected in the ring system. The older System III value of approximately 10 hours 39 minutes tracked magnetospheric periodicity, which is now understood to be decoupled from interior rotation. The NASA Planetary Fact Sheet still lists the System III value; this project treats it as superseded. (Note: a 2023 refinement yields ≈10 h 34 m 42 s (≈10.578 h); a constant update is deferred to a future cascade epic.)

**Uranus rotation period:** Lamy et al. (2025, *Nature Astronomy*) refined the Uranus rotation period to 17.247864 ±0.000010 hours through Hubble UV auroral observations — a 1,000-fold improvement in precision over the Voyager 2 dataset.

**Venus rotation variability:** Venus's rotation varies by approximately 61 ppm (~20 minutes peak-to-peak) due to angular momentum exchange with its massive CO₂ atmosphere (Margot et al. 2021). VMT should be treated as a best-fit at epoch approximation.

**Mars prime meridian:** The Mars prime meridian is anchored to Viking Lander 1 at 47.95137 degrees West (IAU WGCCRE 2015, published 2018), reducing timing uncertainty from approximately 20 seconds to less than 1 second compared to earlier Airy-0 definitions.

**Venus retrograde but east-positive:** IAU convention defines longitude as east-positive for all bodies, including Venus. On Venus, the sun rises in the west, but IAU longitude numbers increase eastward. This is counterintuitive but consistent; implementations must not attempt to "fix" Venus longitude direction.

### 2.5 The Governance Gap

These conventions currently have no formal endorsement from international standards bodies. The appropriate home would be a combination of IAU (which governs planetary coordinate systems) and UNOOSA (which deals with space governance more broadly). The IETF's handling of the RFC 9557 timestamp format creates a natural pathway for the timestamp format itself. The work scheduling provisions — the question of what the rest-day mandates should be, and whether they should be binding — belong to a Space Labour Accords framework discussed in Section 8.

The pathway to formal adoption follows the terrestrial model: publish a reference implementation and open specification, provide interoperability mappings to LTC and UTC, engage IAU and UNOOSA working groups, and demonstrate operational benefit in simulation and analog environments. The reference implementation is planet-time.js and the interplanet.live application. The open specification is DRAFT-STANDARD.md. The engagement with IAU and UNOOSA is the next step.

---

## 3. Interplanetary Meeting Scheduling: The Real Challenge

### 3.1 Beyond "What Time Is It on Mars"

A commonly posed question about interplanetary timekeeping — "what time is it right now on Mars?" — has a tractable answer. The interplanet.live application provides this in real time. However, this question is not the operationally significant one.

The operationally significant problem is: *when can a coordinated work exchange occur?*

Scheduling a meeting between someone in London and someone in New York is a solved problem. You identify the UTC offset difference, find overlapping working hours, send the invite. The overlap is fixed and predictable.

Scheduling a meeting between London and a base at Hellas Planitia, Mars, involves at least three distinct constraints that do not apply to any Earth scheduling problem:

The first is **communications delay**. With one-way delays ranging from 3 to 22 minutes, a round-trip exchange requires 6 to 45 minutes minimum — before any human response time. This is not a meeting; it is an asynchronous exchange that happens to have real-time intent. Above the 120-second threshold, the scheduler should not try to find a "meeting window" at all. It should find async coordination windows: times when both parties are in their working hours and bandwidth allows message exchange, understanding that replies will arrive later.

The second is **shifting schedule overlap**. The 39-minute sol drift means the window of overlapping work hours moves every single day. An overlap at 14:00 UTC today may not exist in the same form three weeks from now. The scheduler must calculate this dynamically — not just look up a fixed offset. During some periods of the synodic cycle, Earth working hours and Mars working hours overlap generously. During others, they barely intersect. The app visualises this.

The third is **solar conjunction blackouts**. Every 779.94 days, there is a period of approximately two weeks during which no messages get through at all, regardless of scheduling. Any mission planning that ignores this is incomplete. The scheduler flags conjunction windows and treats them as hard constraints, not scheduling suggestions.

### 3.2 Async as the Default

The most important shift in thinking required for interplanetary scheduling is treating asynchronous communication as the default mode, not the exception or the failure mode.

On Earth, the gold standard of collaboration is synchronous: real-time conversation, instant messaging, video calls. Asynchronous communication — email, recorded messages, work tickets — is how we handle things when synchronous isn't available. The implicit hierarchy is: synchronous is better; async is a compromise.

Interplanetary work inverts this hierarchy by physical law. For any Earth-Mars interaction, async is not a compromise. It is the only option. A work coordination system designed around the expectation of synchronous availability will systematically fail. The correct design primitive is the **structured bundle**: a self-contained package of information, decision context, and requested action, transmitted with a delivery deadline, designed to be acted on without requiring clarifying questions.

The structured async bundle model has precedents in mission operations: uplink command sequences, rover activity plans, and crew activity plan updates to the ISS are all designed as complete work packets rather than live conversations. What is needed is extending this model to the full range of human coordination — scheduling, approvals, task changes, escalations, and emotional communication — with the right tools for composing, routing, and responding to bundles under latency constraints.

### 3.3 Solar Conjunction Moratorium Planning

For any Mars mission or base, solar conjunction is a fixed, predictable event in the operational calendar. The 14-day command moratorium that NASA currently imposes is a planning constraint, not an emergency. It should be treated like planned maintenance: scheduled in advance, with autonomous operation modes pre-positioned, decision authority pre-delegated, and critical work packages either completed before the moratorium or deferred until after.

The current relay network situation (discussed in detail in Section 5) makes this moratorium more acute, not less. With MAVEN lost in December 2025 and Mars Odyssey approaching fuel exhaustion, the Mars relay network's capacity during conjunction is reduced. The revived Mars Telecommunications Orbiter, mandated by the One Big Beautiful Bill Act of July 4, 2025, with $700 million allocated and launch mandated by 2028, will restore primary relay capacity — but does not by itself eliminate the conjunction blackout. Eliminating the blackout entirely requires relay geometry that keeps at least one communications path angularly separated from the Sun, discussed in Section 6.

### 3.4 The Work Scheduling Model

The work scheduling models embedded in this project are not arbitrary. Each reflects a judgement about biological compatibility, operational necessity, and available evidence:

**Mars (AMT):** The 7-sol week with 5 working sols and 2 rest sols mirrors Earth's week structure and is validated by and compatible with Thomas Gangale's Darian Calendar (1985), the most developed Mars calendar system. The 5-on/2-off pattern is the recommended default, not a mandate. The project's configuration parameters allow variable sol-weeks from 4 to 7 sols, reflecting the trajectory of Earth's work week discussed below.

**Moon, Mercury, Venus (LMT, MMT, VMT):** Earth-clock shifts of 8 hours, 3 shifts per day, 5-on/2-off weekly. The solar day length on these bodies is entirely incompatible with human circadian biology. Timezone zones on these bodies are geographic location identifiers only, telling you where you are relative to the planet's surface, not when to sleep.

**Gas giants (JMT, SMT, UMT, NMT):** Grouped work periods of approximately 24 Earth hours, accounting for the fact that gas giant rotation periods of 10 to 16 hours require grouping multiple rotations to produce a human-compatible daily cycle. Zone references are atmospheric bands rather than surface features.

---

## 4. The Human Factor: Working Beyond Earth

### 4.1 Circadian Biology and the Mars Sol

Human circadian rhythms are not infinitely flexible. The intrinsic period of the human circadian clock averages approximately 24.2 hours, with individual variation in the range of roughly 23.5 to 24.5 hours. The Mars sol at 24 hours and 39 minutes falls at the outer edge of that range. Entrainment to the Mars sol is possible — but it is not effortless, and it is not guaranteed without appropriate support.

The failure mode is well-documented. Without adequate light cues, experimental subjects on a forced desynchrony protocol equivalent to the Mars sol show the sleep degradation (average 5.98 hours, versus a recommended 7–9) that NASA rover engineers experience. The critical countermeasure is light intensity and spectrum: blue-enriched light at 450 lux or higher during wake periods, particularly in the first few hours after waking, achieves approximately 87 percent entrainment success in operational conditions (Barger et al. 2012, Phoenix mission). Below this threshold, the body's circadian system cannot find the Mars sol's rhythm through the noise of competing light signals.

This has direct architectural implications for Mars habitat design. Lighting systems in workspaces and crew quarters must be actively managed, not passive. The schedule of light exposure must be as carefully planned as the work schedule itself. CHAPEA Mission data will provide the first systematic evidence from a simulated habitat; the preliminary indication from Mission 1 (completed July 2024) is that engineered lighting environments are effective when implemented consistently.

The US Navy analogy is instructive: the fleet-wide transition from the traditional 6-on/12-off "18-hour day" watch schedule to 8-on/16-off "24-hour day" watches in 2014 produced dramatic improvements in sleep quality, alertness, and morale. Officers stopped falling asleep on watch. Crews described the change as life-changing. The underlying mechanism was simply that the 18-hour cycle forced the body to work against its circadian clock; the 24-hour cycle worked with it. The Mars sol's 39-minute extension requires active management to avoid the same mismatch in the opposite direction.

### 4.2 The Case for Minimum Rest Standards

The four-day work week trials that have reached critical mass on Earth are relevant to Mars scheduling not as a direct parallel but as evidence about what workers actually need. The 4 Day Week Global trials across six continents showed 92 percent of companies retained the policy after trials ended, with burnout dropping 71 percent, sick days falling 65 percent, and revenue rising 8 percent on average (*Nature Human Behaviour*, July 2025). Iceland's 2015–2019 trial led to 86 percent of the workforce gaining access to shorter hours. Tokyo implemented a four-day option for 160,000 government employees in April 2025.

The signal from this evidence is that the 40-hour, five-day work week is not a physiological or productivity optimum — it is a historical accident of early industrial labour bargaining. If Earth is demonstrably moving toward 32-hour work weeks as a productivity-neutral or productivity-positive change, the argument that Mars workers should work longer hours because they are dependent on their employer for survival becomes harder, not easier, to sustain.

The 5-sol/2-rest Mars work week proposed here is not ambitious. It is the minimum defensible floor given current evidence. The configurable parameters in the project allow 4-sol weeks. They should be allowed; they may be better.

### 4.3 The Legal Vacuum

As of February 2026, no binding international labour standards apply to human activity beyond Earth's atmosphere.

The Outer Space Treaty (1967), Article VIII, establishes flag-state jurisdiction: the registering nation's laws apply to personnel aboard spacecraft or installations. In principle, this means a worker on a US-registered Mars base is subject to US labour law. In practice, enforcement across 4 to 22 minutes of one-way communications delay, with the employer controlling all life support, is a different matter from enforcement in a workplace an inspector can visit.

The Artemis Accords, now with 61 signatories as of January 2026, address interoperability, transparency, peaceful purposes, and the registration of activities and space objects. They contain no provisions on working conditions, hours, wages, or occupational safety.

The SpaceX Starlink Terms of Service famously contain a "Mars clause" declaring Mars a "free planet" with "self-governing principles" and explicitly disclaiming that Earth-based agreements apply. Space law experts have unanimously assessed this clause as void under the Outer Space Treaty. But the fact that a major operator thought it worth inserting — and that it generated years of discussion before being assessed as non-binding — indicates the gap in formal governance that a future employer would exploit if given the chance.

The proposal in this project is a Space Labour Accords framework, analogous to the ILO conventions that established minimum international labour standards on Earth, codifying at minimum: a 5-sol/2-rest standard as the Mars work week floor; mandatory engineered lighting for circadian support; communications rights (the right to contact family and legal representation regardless of employer preference); and transparent scheduling practices that workers can audit.

This is aspirational rather than operational in February 2026. The history of labour rights suggests it will become less aspirational as the number of people working off-Earth grows and the human cost of the alternative becomes visible. Realistically, the most achievable near-term pathway for binding minimum standards is national legislation — individual spacefaring nations extending their domestic labour frameworks explicitly to off-Earth installations — rather than a new international treaty framework. The Artemis Accords, despite having 61 signatories as of January 2026, have zero confirmed labour provisions, and adding them would require renegotiation. A further complication is the bifurcation of lunar governance: the Artemis bloc (61 signatories) and the ILRS programme (China plus approximately 13 partner nations) constitute two parallel and potentially incompatible standards tracks. Any framework that assumes international consensus must account for this structural division.

---

## 5. The Communications Layer: DTN as First-Class Citizen

### 5.1 Why Interplanetary Communications Is Structurally Different

Terrestrial internet engineering assumes that links are mostly available, mostly reliable, and that end-to-end delay is measured in milliseconds. When a link breaks, TCP retransmits. When a node is unavailable, routing protocols find another path. The entire stack is designed for disruption as an exception rather than a structural condition.

Interplanetary communication is the opposite. Links are intermittent, predictable but time-varying. Store-and-forward is not a fallback; it is the primary delivery mechanism. Latency is measured in minutes to hours. There is no always-available path from Earth to Mars; there are contact windows, each one a scheduled event with a known start time, duration, and bandwidth budget. Designing an interplanetary scheduler that ignores this — that treats the communications link as a background utility rather than a first-class scheduling constraint — is designing something that will fail in the most critical moments.

Delay-Tolerant Networking (DTN), formally standardised as Bundle Protocol Version 7 (RFC 9171, January 2022), provides the correct engineering model. The DTN framework moves data in self-contained bundles, each carrying the data itself plus routing metadata, priority flags, and delivery deadlines. Contact Graph Routing (CGR), standardised as Schedule-Aware Bundle Routing (SABR, CCSDS 734.3-B-1, 2019) and developed by Scott Burleigh at JPL, computes routes through a time-varying topology of scheduled contacts — inferring routes from orbital mechanics rather than discovering them through real-time dialogue.

DTN has been operationally deployed on the ISS since 2016. High-Rate DTN (HDTN), developed by NASA Glenn Research Center, has achieved 900 Mbps laser link throughput in demonstration — closing the bandwidth gap between DTN's robust delivery semantics and the high-data-rate requirements of future deep space operations.

### 5.2 The Mars Relay Network in Crisis

The relay network that currently serves Mars operations is critically depleted.

MAVEN — the Mars Atmosphere and Volatile Evolution orbiter — lost contact on December 6, 2025, failing to resume communications after passing behind Mars. Recovery attempts through the December 29–January 16 solar conjunction moratorium were unsuccessful, and NASA assessed recovery as very unlikely. MAVEN served not only as a science platform but as a critical relay node.

Mars Odyssey, the longest-serving Mars orbiter at 23 years of operation, lost one of its four reaction wheels in 2012 and is expected to exhaust its remaining fuel within years. Its loss would leave the relay network's primary assets as MRO (operational since 2006, planned through at least the late 2020s, achieving up to 6 Mbps X-band Earth downlink and 2 Mbps UHF relay) and ESA's Trace Gas Orbiter.

The revived Mars Telecommunications Orbiter is the most concrete near-term solution. The One Big Beautiful Bill Act of July 4, 2025, allocated $700 million for a new MTO with launch mandated no later than 2028, procured via fixed-price contract. Blue Origin unveiled its proposal on August 12, 2025, based on the flight-proven Blue Ring platform, incorporating hybrid electric-chemical propulsion, multiple steerable high-rate links, deployable UHF relay satellites for low Mars orbit, over 1,000 kg of additional payload capacity, and onboard AI and edge computing capabilities. Rocket Lab and Lockheed Martin are also competing. The revived MTO represents critical relay infrastructure — but it does not by itself eliminate solar conjunction blackouts.

### 5.3 The Geometry of Blackout Elimination

Solar conjunction blackouts arise because, at certain orbital geometries, the Sun lies between Earth and Mars and the solar corona degrades or blocks radio signals. The severity depends on frequency band: X-band (8.4 GHz) typically produces 17–24 day outages per conjunction; Ka-band (32 GHz) dramatically reduces this, with outages as short as zero days at favourable geometries (the 2034 conjunction); optical systems suffer 60–78 day outages due to the Sun's extreme brightness at optical wavelengths.

Howard and Seibert's 2020 NASA study (NTRS 20205007788) established the definitive geometric principle: at any given time, a planet or either its L4 or L5 point is visible to any other planet, regardless of the Sun's position. A single relay satellite at Earth-Sun L5 (preferred over L4 due to the near-Earth Trojan asteroid 2010 TK7) would eliminate conjunction blackouts entirely for Earth-Mars communications.

Several alternative relay geometries have been studied in detail:

**Gangale/MarsSat orbits** (Gangale 2005): Solar orbits co-orbital with Mars but inclined a few degrees out of the orbital plane, oscillating approximately 20 million km from Mars. Two satellites suffice to provide continuous coverage, with signal strength 100 times better than L4/L5 by inverse-square law.

**Mars Trojan orbits** (Journal of the Astronautical Sciences, 2019): Stable for decades without station-keeping, with Mars flyby reducing orbit insertion cost. Two satellites provide continuous coverage.

**ESA non-Keplerian B-orbits** (2009): Satellites maintain position near Mars using continuous low-thrust ion propulsion, requiring active thrust for only approximately 90 days per 2.13-year synodic period. Adds approximately one minute of additional one-way signal delay. Two satellites needed.

The practical conclusion: two to three relay satellites in well-chosen heliocentric orbits eliminate Earth-Mars conjunction blackouts entirely. This is not a speculative proposal. The orbital mechanics are settled science. The question is funding and launch priority.

### 5.4 The Optical Revolution: DSOC Results

NASA's Deep Space Optical Communications (DSOC) technology demonstration on the Psyche spacecraft concluded on September 2, 2025, after exceeding all stated goals. The results represent a step change in what deep space bandwidth is achievable.

DSOC achieved 267 Mbps at 0.2 AU (December 2023), 25 Mbps at 1.5 AU (April 2024), and sustained 6.25–8.3 Mbps at 2.6 AU (June 2024), transmitting a total of 13.6 terabits over 65 link passes. At comparable distances, this represents 10 to 100 times higher data rates than RF systems of similar size and power.

However, DSOC's conjunction vulnerability is the most severe of any frequency band: 60–78 day outages versus 17–24 days for X-band. This makes relay architecture not merely desirable for optical systems but essential. The optimal architecture is hybrid: optical trunk links for high-bandwidth data transfer during non-conjunction periods; Ka-band relay links for conjunction bypass for schedule-critical small bundles.

### 5.5 DTN for Scheduling: The Contact Graph as First-Class Constraint

The implication for interplanetary scheduling is that the communications layer must be modelled explicitly, not assumed. A work package tagged "requires Earth confirmation before execution" must know the current relay topology, predicted conjunction windows, DTN bundle queue depths, and available bandwidth before it can be validly scheduled. A meeting scheduled during conjunction — even an async bundle exchange — must either be moved, pre-positioned (Earth approval sent before conjunction begins), or executed with pre-delegated local authority.

This is the key integration principle: communications state is a first-class scheduling constraint, not a background utility. The AI-Integrated HDTN Scheduler described in the next section is built on this principle.

---

## 6. The AI-Integrated HDTN Scheduler (Experimental Concept)

### 6.1 The Limitation of Static Tools

The current interplanet.live application is a static timezone converter extended with orbital mechanics, delay calculations, and conjunction warnings. It is useful. It answers the question "when can we communicate?" with considerably more rigour than any existing tool. But it has a fundamental limitation: it is static.

A static tool can tell you the current Earth-Mars delay to the nearest second. It cannot tell you whether the delay will allow your critical task approval to complete before the conjunction moratorium begins. It cannot predict whether the DTN bundle queue on MRO will have capacity for your high-priority message. It cannot adapt the work schedule when a relay satellite goes offline. It cannot learn from six months of CHAPEA data that this particular crew member's circadian rhythm requires 30 minutes more light exposure than the default model assumes.

These are not exotic capabilities. They are what a real interplanetary scheduling system for crewed missions will need. The AI-Integrated HDTN Scheduler is an experimental concept for building that system.

### 6.2 Validated Foundations: What Already Exists

The experimental nature of this proposal should not obscure how much of the underlying technology already exists at demonstrated readiness levels.

**CASPER and ASPEN at TRL 9.** JPL's ASPEN (ground-based) and CASPER (flight version) planning systems use iterative repair with constraint-based reasoning. CASPER operated autonomously on the Earth Observing-1 satellite for over 12 years (2003–2017) on an 8 MIPS flight processor, and currently supports onboard scheduling on the Mars 2020 Perseverance rover.

**NASA SCaN Testbed landmark results.** The Space Communications and Navigation Testbed on the ISS (2012–2019, 4,200+ hours of testing) achieved the first-ever adaptive space link controlled entirely by an artificial intelligence algorithm in 2018. The User Initiated Services demonstration compressed scheduling turnaround from the prior three-week pipeline to 15 minutes through AI-driven automation.

**Proximal Policy Optimization for DSN scheduling.** Goh et al. (arXiv:2102.05167, February 2021) demonstrated that a PPO agent could learn the complex heuristics used by human DSN schedulers in a custom OpenAI Gym environment, significantly outperforming random baselines and approaching human scheduler performance in simulated weekly DSN scheduling problems.

**Deep Q-Learning for DTN relay management.** Sanchez Net et al. at JPL (AIAA Journal of Aerospace Information Systems, 2021) demonstrated a DQL agent managing a DTN orbital relay node between Moon and Earth, deciding when to drop packets, change data rates, reroute bundles to crosslinks, or take no action.

**LLM-to-constraint translation.** Three large language models — o3-mini, GPT-4.1 Mini, and Gemini Pro 2.5 — have been shown to exactly reproduce analytical scheduling optima from natural language inputs (arXiv:2511.11612, 2025). The ISS CAST (Crew Autonomous Scheduling Test) experiments (2017–2018) demonstrated that crewmembers could self-schedule activities on a mobile device while respecting flight constraints.

### 6.3 The Proposed Architecture

The AI-Integrated HDTN Scheduler is proposed as a layered architecture combining a validated deterministic simulation core with ML predictive overlays.

**Frontend layer:** React application extending the existing planet-time.js base, with natural language scheduling request interface (LLM-mediated constraint generation), visual delay timelines, overlap heatmaps, DTN queue status, and export to iCal and mission planning tool APIs.

**ML prediction layer:**
- Time-series forecasting (LSTM or Transformer architecture) trained on pre-generated Earth-Mars orbital data for delay window and overlap prediction
- Fatigue risk classification model, incorporating sol count, sleep duration estimates, light exposure schedule, and mission phase
- Lighting countermeasure scheduling model, generating recommended light exposure profiles

**HDTN simulation core:** Contact graph routing simulation using the NASA HDTN stack (C++ with Python bindings), modelling store-and-forward queue management, bundle priority assignment, relay topology changes, and blackout periods.

**Ephemeris integration:** NASA SPICE toolkit (via the SpiceyPy Python wrapper) and JPL Horizons API for real orbital positions, replacing the simplified Keplerian models in the current planet-time.js.

**Cloud compute layer:** Training on AWS spot instances (p3.2xlarge with V100 GPU, approximately $3–3.70/hour). At 4–8 GPU hours per training run, cost per training is $12–30; quarterly retraining costs approximately $50–120 per year. Live inference runs on AWS Lambda at approximately $5–20 per month at research scale.

### 6.4 Development Path: MVP to Mission Use

The recommended minimum viable product (MVP) path is:

1. PyTorch + SPICE ephemeris integration into planet-time.js for real orbital positions
2. Pre-generated 10-year Earth-Mars time series in TimescaleDB, hourly resolution
3. LSTM delay forecasting model, trained on historical JPL Horizons data
4. HDTN contact graph simulation wrapper in Python
5. Live inference endpoint on AWS Lambda
6. Testing against CHAPEA Mission 3 scenario (when available)

The MVP does not attempt the full LLM natural language interface or the federated learning components. It focuses on demonstrating that ML-enhanced delay prediction and HDTN simulation can improve on the deterministic-only baseline in a way that is measurable and auditable.

---

## 7. AI's Role in This Project

### 7.1 Discovery and Research

This whitepaper is an example of what AI-mediated research synthesis looks like in practice. The research findings cited here were assembled through AI-assisted literature review, combining primary source retrieval, cross-referencing of preprints and published papers, and synthesis across domains (orbital mechanics, networking, human physiology, labour law, machine learning) that would individually require specialist expertise.

All scientific claims in this paper are cross-referenced to primary sources, listed in the References section.

### 7.2 Development

The planet-time.js library, sky.html application, and all associated test infrastructure were developed collaboratively with Claude Code, Anthropic's AI coding assistant. The collaboration involved reasoning through orbital mechanics formulae, catching errors in initial specifications, debating timezone naming conventions, and designing test vectors for edge cases like the 2034 zero-day Ka-band conjunction.

The resulting code has been validated against independent orbital ephemeris data and published test vectors. The orbital mechanics calculations are correct to documented precision bounds.

### 7.3 Authorship Transparency

This whitepaper was written in collaboration with Claude (Anthropic). The structure, direction, judgements, and claimed contributions are those of the principal author. Research synthesis, prose drafting, and technical cross-referencing were conducted collaboratively. All scientific claims have been cross-referenced against primary sources cited in the References section.

---

## 8. The Legal and Governance Landscape

### 8.1 Current Framework

The formal legal architecture governing human activity in space has not been updated in meaningful ways since the 1967 Outer Space Treaty. The key provisions relevant to scheduling and labour:

The Outer Space Treaty establishes national jurisdiction and responsibility for space activities (Articles VI and VIII), requires international consultation before conducting activities that might harm other parties (Article IX), and prohibits national appropriation of the Moon and other celestial bodies (Article II). It does not address working conditions, rest requirements, wages, safety standards, or the employer-employee relationship in any form.

### 8.2 The Artemis Accords Gap

The Artemis Accords, first signed in 2020 and now with 61 signatories as of January 2026, represent the most significant multilateral space governance development since the OST. Their provisions address transparency, peaceful purposes, emergency assistance, registration, release of scientific data, preservation of heritage sites, space resources, and deconfliction of activities.

They contain no provisions on working conditions. None. Not a line on rest requirements, not a word on occupational safety, not a sentence on the employer-employee relationship for people living off-Earth.

### 8.3 The Space Labour Accords Proposal

The proposal in this project is a Space Labour Accords framework — a set of minimum binding standards, modelled on ILO conventions, that would codify:

- **Mars rest cycle:** 5-sol/2-rest as the mandatory minimum
- **Engineered lighting:** Mandatory provision of ≥450 lux blue-enriched lighting in sleep/wake transition periods for all Mars crews
- **Communications rights:** The right to unmonitored personal communications with Earth during off-shift periods, subject only to technical constraints
- **Schedule transparency:** Workers' right to view, comment on, and formally object to their scheduled work patterns
- **Autonomous operation limits:** Mandatory pre-approval of autonomous operation plans before any conjunction blackout period, with clear decision authority delegation

### 8.4 Path to Standards Adoption

The timezone system in this project requires a separate, parallel standards path. The most direct route:

1. **IETF RFC track — concrete 2026 milestone:** Submit the Draft Standard (DRAFT-STANDARD.md) as an Informational RFC to the IETF, requesting registration of the `body` suffix key in the IANA Timestamp Suffix Tag Keys registry established by RFC 9557. RFC 9557 establishes a five-field template process for suffix key registration, with expert review conducted by Ujjwal Sharma and Bron Gondwana. The `body` key is provisionally registerable now under that process. This is the most tractable near-term standards milestone — achievable within 2026 without waiting for broader consensus from space agencies or international bodies.

2. **IAU engagement:** Propose the AMT/LMT/MMT/VMT/JMT/SMT/UMT/NMT zone identifiers to the IAU's Working Group on Cartographic Coordinates and Rotational Elements.

3. **UNOOSA/ATLAC engagement — active window:** Engage through UNOOSA's Advisory Committee on the Legal Aspects of Space Activities and other Matters (ATLAC). Draft recommendations from the current ATLAC cycle are due at the 69th COPUOS session (June–July 2026), and lunar timekeeping is listed as a 2026 ATLAC priority. This is a time-sensitive engagement window that closes if not acted on before that session.

4. **Space Labour Accords — national legislation pathway:** The Space Labour Accords framework proposed in Section 8.3 should be understood as a long-term aspiration. The realistic near-term pathway is national legislation rather than international treaty frameworks. The Artemis Accords, now with 61 signatories, represent significant multilateral engagement but contain zero confirmed labour provisions; adding labour standards through the Accords mechanism would require renegotiation with all signatories. A separate concern is the bifurcation of lunar governance into two competing tracks: the Artemis bloc (61 signatories) and the International Lunar Research Station (ILRS) programme led by China with approximately 13 partner nations. International consensus on labour standards should not be assumed given this bifurcation.

5. **Mission tool integration:** Engage NASA, ESA, and commercial operators on interoperability as a parallel track to formal standards development.

---

## 9. What's Next

**SPICE ephemeris integration:** Replacing the simplified Keplerian models in planet-time.js with NASA SPICE PCK kernel data for real prime meridian definitions and rotation models.

**HDTN Scheduler MVP:** PyTorch LSTM model for Earth-Mars delay forecasting, trained on 10 years of JPL Horizons data at hourly resolution. HDTN contact graph simulation wrapper in Python. AWS Lambda inference endpoint.

**CHAPEA analog testing:** Coordinate with NASA CHAPEA programme (Mission 3, timeline TBD) to test scheduling scenarios in the analog environment.

**IAU/UNOOSA engagement:** Submit the Draft Standard to the IETF RFC process and initiate engagement with IAU WGCCRE on the timezone zone prefix system.

**Mobile app:** A mobile version of the core time display and scheduler features.

**Darian Calendar integration:** Full integration of Thomas Gangale's Darian Calendar holiday and month structure into the Mars AMT system.

**Relay architecture modelling:** Explicit modelling of relay constellation deployments as scheduling infrastructure parameters.

---

## 10. Conclusion

Interplanetary scheduling is not a timezone problem. It is a systems problem that combines orbital mechanics, human physiology, networking architecture, labour policy, and adaptive optimisation — and the systems needed to solve it comprehensively do not yet exist in any integrated form.

What exists are building blocks. The timezone conventions developed in this project — AMT, LMT, and the rest — provide a location reference system that separates the question of where you are from the question of when you work. The Draft Standard provides a formal timestamp format aligned to RFC 9557, with a pathway to IANA registration. The HDTN/DTN stack is standardised, flight-proven, and operational. The ML components are at various readiness levels but all validated in principle. The relay architectures to eliminate conjunction blackouts are geometrically proven; they await funding, not invention.

What is absent is integration: a system that treats the timezone convention, the communications architecture, and the scheduling intelligence as a single co-designed problem rather than three separate engineering efforts. The AI-Integrated HDTN Scheduler is the proposed integration point, described here as an experimental concept with a credible path to validation.

The human dimension underlying all of this is comparatively direct. Personnel deployed to Mars will be working, and the conditions of that work must satisfy the minimum standards of human welfare that Earth experience has established as necessary. The 39-minute drift of the Martian sol is a manageable biological challenge, not an insurmountable one. The 22-minute communications delay is a structural fact, not a scheduling inconvenience to be optimised away. The governance vacuum in which no labour standards apply beyond Earth is a structural gap whose consequences will become acute as mission duration and crew size increase.

Developing the scheduling tools, timestamp conventions, communications models, and governance frameworks prior to extended human presence on Mars — rather than constructing them under operational pressure — represents the rational engineering approach. This project constitutes a contribution to that preparatory work.

---

## References

**Allison, M. and McEwen, M. (2000).** A post-Pathfinder evaluation of aerocentric solar coordinates with improved timing recipes for Mars seasonal/diurnal climate studies. *Planetary and Space Science* 48, 215–235.

**Archinal, B.A. et al. (2018).** Report of the IAU Working Group on Cartographic Coordinates and Rotational Elements: 2015. *Celestial Mechanics and Dynamical Astronomy* 130:22.

**Ashby, N. and Patla, B. (2024).** Gravitational time dilation on the Moon. NIST Technical Note. (56.02 μs/day LTC offset result.)

**Ashby, N. and Patla, B. (2025).** Relativistic time dilation for Mars. *Astronomical Journal* 171:2. (Mars drift: 477 µs/day average, ±226 µs/day seasonal; perihelion ~251 µs/day, aphelion ~703 µs/day.)

**Barger, L.K. et al. (2012).** Prevalence of sleep deficiency and use of hypnotic drugs in astronauts before, during, and after spaceflight. *Lancet Neurology* 11(3), 231–241.

**Burleigh, S. et al. (2022).** Bundle Protocol Version 7. RFC 9171, January 2022.

**CCSDS (2019).** Schedule-Aware Bundle Routing (SABR). CCSDS 734.3-B-1.

**CCSDS (2010).** Time Code Formats. CCSDS 301.0-B-4.

**CGPM (2022).** Resolution 4 on the future of UTC. 27th General Conference on Weights and Measures, November 2022.

**Fraire, J. et al. (2021).** Routing under uncertain contact plans: RUCoP. *Ad Hoc Networks*. arXiv:2108.07092.

**Gangale, T. (2005).** Mars telecommunications relay orbits. Annals of the New York Academy of Sciences.

**Gangale, T. (2006).** The architecture of time, Part 2: The Darian system for Mars. SAE Technical Paper 2006-01-2249.

**GAT-MARL (2025).** Graph attention multi-agent reinforcement learning for lunar rover DTN relay. arXiv:2510.20436.

**Goh, E. et al. (2021).** Deep reinforcement learning for NASA Deep Space Network scheduling. arXiv:2102.05167.

**Howard, R. and Seibert, M. (2020).** Mars solar conjunction relay architecture. NASA NTRS 20205007788.

**IAU (2024).** Resolution on Coordinated Lunar Time (LTC), IAU XXXII General Assembly, Cape Town, August 2024.

**Lamy, L. et al. (2025).** A new rotation period and longitude system for Uranus. *Nature Astronomy*.

**LLM scheduling optima (2025).** arXiv:2511.11612.

**Mankovich, C., Marley, M., Fortney, J. and Mozshovitz, N. (2019).** A diffuse core in Saturn from ring seismology. *The Astrophysical Journal* 871:1. (A 2023 refinement gives ≈10 h 34 m 42 s (≈10.578 h); constant update deferred to cascade epic.)

**Margot, J.-L. et al. (2021).** Spin state and moment of inertia of Venus. *Nature Astronomy* 5, 676–683.

**Morabito, D. et al. (2018).** Mars conjunction communications blackout data and models. JPL DSN Telecommunications Design Handbook, Document 810-005, Module 210. *(Internal JPL document; X-band and Ka-band exclusion zone data sourced from operational mission planning records.)*

**NASA (2024).** White House OSTP directive on Coordinated Lunar Time, April 2, 2024.

**NASA (2025).** DSOC technology demonstration final results, September 2, 2025.

**NASA (2025).** MAVEN loss of contact, December 6, 2025. Mission status update.

**One Big Beautiful Bill Act (2025).** Public Law, signed July 4, 2025.

**Purple Mountain Observatory (2025).** LTE440 lunar timekeeping software. December 2025.

**RFC 3339.** Klyne, G. and Newman, C. Date and Time on the Internet: Timestamps. July 2002.

**RFC 9557.** Sharma, U. and Bormann, C. Date and Time on the Internet: Timestamps with Additional Information. April 2024.

**Sanchez Net, M. et al. (2021).** Deep reinforcement learning for DTN orbital relay node management. *AIAA Journal of Aerospace Information Systems*.

**Scheer, F.A.J.L. et al. (2007).** Plasticity of the intrinsic period of the human circadian timing system. *PLOS ONE*.

**4 Day Week Global (2025).** Results of multinational four-day work week trials. *Nature Human Behaviour*, July 2025.

**Alhilal, A., Braud, T. and Hui, P. (2019).** The Sky is NOT the Limit Anymore: Future Architecture of the Interplanetary Internet. *IEEE Aerospace and Electronic Systems Magazine* 34(8), 22–32. doi:10.1109/MAES.2019.2927897.

**Jackson, J. (2005).** The Interplanetary Internet. *IEEE Spectrum*. doi:10.1109/MSPEC.2005.1491224.

**Yang, G. et al. (2018).** Queueing analysis of DTN protocols in deep-space communications. *IEEE Aerospace and Electronic Systems Magazine* 33(12), 40–48. doi:10.1109/MAES.2018.180069.

**Zhao, K. et al. (2016).** Performance of bundle protocol for deep-space communications. *IEEE Transactions on Aerospace and Electronic Systems* 52(5), 2347–2361. doi:10.1109/TAES.2016.150462.

---

*Matthew Watt — [interplanet.live](https://interplanet.live) — February 2026 (references updated March 2026)*
