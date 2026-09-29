# Discoverability measurement baseline

**Baseline date:** 29 September 2026
**Repository:** https://github.com/karwalski/interplanet
**Website:** https://interplanet.live/
**Related:** [Discoverability audit and LTX topic research](2026-09-29-discoverability-and-ltx-topics.md) (section 1 and story IP-D6)

This file records where InterPlanet's discoverability stood on 29 September
2026, which numbers to track, how to collect each one, and blank checkpoints at
30, 60 and 90 days. Stars and downloads are recorded as reach, not as evidence
of adoption. A value that could not be measured is written as **unknown** and is
never estimated.

---

## 1. Baseline (29 September 2026)

Repository figures come from the GitHub API on 29 September 2026, taken
**before** the maintainer's session filed the backlog issues #2 to #22 that
same day.

| Metric | Baseline | Source |
|--------|----------|--------|
| Stars | 1 | GitHub API `stargazers_count` |
| Forks | 0 | GitHub API `forks_count` |
| Watchers | 1 | GitHub API `subscribers_count` |
| Issues (open and closed) | 0 | GitHub API, before #2 to #22 were filed |
| External pull requests | 0 | GitHub search (the only PR, #1, was opened by the owner on 2021-05-22) |
| About: homepage | Set (`https://interplanet.live/`) | GitHub API `homepage` |
| About: description | Empty | GitHub API `description` |
| Topics | None | GitHub API `topics` |
| Discussions | Disabled | GitHub API `has_discussions` |
| Git tags / releases | None | `git tag`, GitHub releases |
| Packages on public registries | None (PyPI, npm, crates.io and RubyGems lookups all 404) | Registry APIs, see [docs/RELEASING.md](../RELEASING.md) |
| Conformance CI | No runs; the workflow was added on 29 Sep 2026. Local run: 12 of 21 ports pass | [LANGUAGE-SUPPORT.md](../../LANGUAGE-SUPPORT.md#conformance) |
| GitHub traffic (views, clones, referrers) | **Unknown** (owner-only API, not collected) | `traffic/*` API |
| Google Search Console | **Unknown** whether configured; no data | Owner account |
| Web analytics | **Unknown** whether configured; no evidence in the repository | Owner account |
| Website pages indexed | **Unknown** | Search Console |

---

## 2. Metrics to track

| # | Metric | Why it matters | How to get it |
|---|--------|----------------|---------------|
| M1 | Stars, forks, watchers | Reach on GitHub | `gh api repos/karwalski/interplanet --jq '{stars: .stargazers_count, forks: .forks_count, watchers: .subscribers_count}'` |
| M2 | Issues and pull requests opened by people other than the maintainer | Evidence that others use or contribute | `gh api "search/issues?q=repo:karwalski/interplanet+-author:karwalski+created:>=2026-09-29" --jq .total_count` (add `+is:pr` or `+is:issue` to split them) |
| M3 | Distinct external contributors with a merged PR | Contribution, not just interest | `gh api "search/issues?q=repo:karwalski/interplanet+is:pr+is:merged+-author:karwalski" --jq '[.items[].user.login] \| unique \| length'` |
| M4 | GitHub views and unique visitors (14 days) | Traffic to the repository | `gh api repos/karwalski/interplanet/traffic/views` (needs push access; GitHub keeps only 14 days, so record it at every checkpoint) |
| M5 | GitHub clones and unique cloners (14 days) | Developers trying the code | `gh api repos/karwalski/interplanet/traffic/clones` |
| M6 | Top referrers and popular paths (14 days) | Where visitors come from | `gh api repos/karwalski/interplanet/traffic/popular/referrers` and `.../traffic/popular/paths` |
| M7 | About description and topics set | Findability in GitHub search and topic pages | `gh api repos/karwalski/interplanet --jq '{description, topics}'` |
| M8 | Discussions enabled; number of threads | Place for questions and research talk | `gh api repos/karwalski/interplanet --jq .has_discussions`; count threads in the Discussions tab |
| M9 | Packages published, and downloads per package (last 30 days) | Install reach once packages exist | npm: `curl -s https://api.npmjs.org/downloads/point/last-month/<name>`; PyPI: `curl -s https://pypistats.org/api/packages/<name>/recent`; crates.io: `curl -s https://crates.io/api/v1/crates/<name>` (`downloads`, `recent_downloads`). Record "not published" until a release exists |
| M10 | Conformance: ports passing in the latest CI run | Public, reproducible quality evidence | Latest run of the [Conformance workflow](https://github.com/karwalski/interplanet/actions/workflows/conformance.yml), summary table |
| M11 | Search Console: clicks, impressions, average position (last 28 days) | Organic search reach for the website | Search Console, Performance report for `https://interplanet.live/`. Record "not configured" if there is no property |
| M12 | Search Console: indexed pages, and whether the sitemap was read | Whether the site can be found at all | Search Console, Pages (indexing) report and Sitemaps report |
| M13 | Search Console: top queries | Which topics bring people in (for example "mars time", "interplanetary meeting") | Search Console, Performance report, Queries tab |
| M14 | Web analytics: visitors and top pages (30 days) | Website use | The privacy-respecting analytics tool, if one is configured. Record "not configured" otherwise; do not estimate |
| M15 | Mentions and backlinks | Recognition by others | Manual search for "interplanet.live" and "karwalski/interplanet" on GitHub, the web and relevant forums; list new ones with dates |

Record exactly what the source reports on the checkpoint date. If a source is
unavailable, write **unknown** and why.

---

## 3. Checkpoints

Fill in each table on (or as close as possible to) its date, and note the
actual collection date if it differs.

### 30 days: 2026-10-29

| Metric | Value | Notes |
|--------|-------|-------|
| M1 Stars / forks / watchers | | |
| M2 External issues / PRs | | |
| M3 External contributors (merged) | | |
| M4 Views / unique visitors (14 d) | | |
| M5 Clones / unique cloners (14 d) | | |
| M6 Top referrers / paths | | |
| M7 Description and topics set | | |
| M8 Discussions enabled / threads | | |
| M9 Packages published / downloads | | |
| M10 Conformance ports passing (CI) | | |
| M11 Search clicks / impressions / position | | |
| M12 Indexed pages / sitemap read | | |
| M13 Top queries | | |
| M14 Analytics visitors / top pages | | |
| M15 New mentions and backlinks | | |

### 60 days: 2026-11-28

| Metric | Value | Notes |
|--------|-------|-------|
| M1 Stars / forks / watchers | | |
| M2 External issues / PRs | | |
| M3 External contributors (merged) | | |
| M4 Views / unique visitors (14 d) | | |
| M5 Clones / unique cloners (14 d) | | |
| M6 Top referrers / paths | | |
| M7 Description and topics set | | |
| M8 Discussions enabled / threads | | |
| M9 Packages published / downloads | | |
| M10 Conformance ports passing (CI) | | |
| M11 Search clicks / impressions / position | | |
| M12 Indexed pages / sitemap read | | |
| M13 Top queries | | |
| M14 Analytics visitors / top pages | | |
| M15 New mentions and backlinks | | |

### 90 days: 2026-12-28

| Metric | Value | Notes |
|--------|-------|-------|
| M1 Stars / forks / watchers | | |
| M2 External issues / PRs | | |
| M3 External contributors (merged) | | |
| M4 Views / unique visitors (14 d) | | |
| M5 Clones / unique cloners (14 d) | | |
| M6 Top referrers / paths | | |
| M7 Description and topics set | | |
| M8 Discussions enabled / threads | | |
| M9 Packages published / downloads | | |
| M10 Conformance ports passing (CI) | | |
| M11 Search clicks / impressions / position | | |
| M12 Indexed pages / sitemap read | | |
| M13 Top queries | | |
| M14 Analytics visitors / top pages | | |
| M15 New mentions and backlinks | | |
