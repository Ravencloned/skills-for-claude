# dejavu log schema (v0.1)

All state lives under `<project>/.dejavu/` (gitignored by install) plus an error log at
`~/.claude/dejavu/errors.log`. The committed artifact is `docs/dejavu/<slug>.md`. Check logs are
append-only JSONL; the small state files are JSON written tmp+rename. Hooks write state and log
rows; hooks never read the network. Fields marked `?` are optional.

## `.dejavu/sessions/<session_id>.json`

```json
{ "offered": false, "gate_denied": false, "checks": ["<slug>"], "skip": null,
  "seen": { "<tool_use_id or event key>": 0 } }
```

`offered` is set by `prompt` the first time it speaks in plan mode. `gate_denied` is set by `gate`
before the deny is emitted, so a plan cycle sees at most one deny. `enter` resets both when the
session is still unsatisfied (no reported check, no skip), which gives a second plan cycle one more
offer and one more deny. `skip` is `{ "ts", "reason", "user_said" }` once a skip is adopted
(`user_said` is the user's own answer, required by `skip --user-said`). `seen`
de-duplicates hook deliveries (the plugin's `hooks.json` and the SKILL.md-level hook can both
deliver the same PostToolUse) by `tool_use_id`.

## `.dejavu/checks/<slug>.json`

```json
{ "slug": "token-bucket-rate-limiter-express", "topic": "token bucket rate limiter for an Express API",
  "depth": "quick|default|deep", "langs": ["javascript"], "project_license": "MIT",
  "framings": { "problem": "", "mechanism": "", "category": "" }, "synonyms": [],
  "status": "open|reported", "verdict": null, "recommend": null, "opened": 0, "reported": null, "session": null }
```

`open` writes it (`session` is the session id when one is known, else null); `frame` fills
`framings` and `synonyms`. `report` sets `status: "reported"`, `verdict` (the validated one),
`claimed_verdict`, `recommend`, `summary`, `reported` (ts), `report` (`.dejavu/checks/<slug>.md`),
`docs` (`docs/dejavu/<slug>.md`, or null with `--no-docs`) and `published` (ts, or null); `publish`
fills `docs` and `published` later; `recheck` adds `rechecked` (ts).

Slug: lower-case topic, non-alphanumerics collapsed to `-`, cut at the last word boundary at or
before 60 characters; a collision with a reported check appends `-2`, `-3`.

## `.dejavu/checks/<slug>.jsonl`  (one row per event, ordered)

| kind      | fields                                                                                             | written by |
|-----------|----------------------------------------------------------------------------------------------------|------------|
| `query`   | `ts, source, tier, framing?, q, request, hits, top[], ms, agent?, error?`                          | `query`, `log query`, `receipt` (WebSearch, `source: "websearch"`), `recheck` |
| `fetch`   | `ts, url, via, request?, target?, final_url?, status?, title?, bytes?, ms?, agent?`                | `fetch` (`via: engine`), `inspect` (`via: inspect`, `target` as typed), `receipt` (WebFetch, `via: WebFetch`) |
| `meta`    | `ts, url, name, source, license?, updated?, stars_or_downloads?, archived?, open_issues?, language?, downloads_last_month?, repo?, agent?` | `inspect` (`source`: gh-repos, npm, crates, pypi or web) |
| `finding` | `ts, name, url, closeness, reusable, evidence, license?, updated?, stars?, source?, framing?, agent?` | `log finding` |
| `note`    | `ts, text, agent?`                                                                                 | `log note` |
| `recheck` | `ts, since, source, tier, q, request, hits, top[], ms, error?` (one row per re-run query; `hits` and `top[]` are the new rows only) | `recheck` |

`request` is the exact URL or `gh` command line the engine ran (an errored row still carries the
request it attempted), so the query can be repeated by hand. For `gh-repos` and `gh-code` each word
of `q` is a separate search term; a `"quoted phrase"` inside `q` stays one term. `fetch` of a
github.com repo URL keeps the URL as typed in `url` and the README route it read in `request`
(`gh api repos/<o>/<r>/readme`, `GET https://api.github.com/...` without `gh`, or the raw file for a
blob URL). `top[]` holds up to `limit` normalized rows:

```json
{ "name": "", "url": "", "desc": "", "stars_or_downloads": 0, "updated": "YYYY-MM-DD",
  "license": "", "source": "gh-repos", "evidence": "listed" }
```

`evidence` on a finding is set by the engine, never by the caller: `fetched` if a `fetch` or `meta`
row carries the same URL (normalized: scheme and trailing slash dropped, host lower-cased),
`listed` if any `query` row's `top[]` carries it, else `recalled`. A finding with no URL is refused
(exit 1). A `query` row with `error` set counts as a query for budget purposes and as a gap for
coverage purposes; the error is reported in the Coverage section.

Sources: `gh-repos`, `gh-code`, `gh-topics`, `npm`, `pypi`, `crates`, `hn`, `so`, `openalex`,
`arxiv` (engine), `websearch` (from the receipt hook or `log query`), and whatever name `log query`
was given for a tier-0 search (`self`, `grep`, `git-log`). `crates` search rows always carry
`license: null` (the crates.io search API has no license field); `inspect crate:<name>` fills it
from the version record. Tiers: 0 self, 1 GitHub, 2 registries, 3 discussion, 4 papers, 5 general
web. Framings: `problem`, `mechanism`, `category`.

## `.dejavu/checks/<slug>.md`

The canonical report, always written by `report`. `docs/dejavu/<slug>.md` is a copy of it, written
by `report` unless `--no-docs`, or by `publish` later. `recheck` appends to both copies.

## `.dejavu/current.json`

```json
{ "slug": "", "depth": "", "ts": 0, "adopted_by": null }
```

The open check. CLI subcommands run through Bash, where `CLAUDE_SESSION_ID` is not reliable, so
checks are keyed by slug and the first hook that carries a `session_id` within 2 hours adopts the
open check into that session's `checks[]` (`adopted_by` stamped). `report` closes it. Two sessions
in one project can cross-adopt; documented, not prevented.

## `.dejavu/pending-skip.json` and `.dejavu/skips.jsonl`

```json
{ "ts": 0, "reason": "", "user_said": "", "session": null }
```

Written by `skip --user-said "<the user's own words>" "<reason>"`; without `--user-said` the engine
writes nothing and exits 1 (the model recommends, the user decides). Consumed (adopted into
`session.skip`, file removed) by the next hook that has a session id, within the same 2 hour window.
`skips.jsonl` keeps every skip with its reason and the user's words.

## `.dejavu/pending-invoke.json`

```json
{ "ts": 0, "depth": "quick|default|deep", "session": null }
```

Written by `invoke` (the SKILL.md `!` line) so the depth the user typed reaches `open`, which runs
in a later Bash call: `open` without `--depth` takes it while the file is under 10 minutes old,
then removes it.

## `.dejavu/ratelimit.json`

`{ "<source>": <last call ts>, "<source>_backoff_until"?: <ts> }`. The engine spaces calls per
source: arXiv 3 s, `gh-code` 6 s, `gh-repos` and `gh-topics` 2 s, crates.io 1 s; npm, pypi, hn, so
and openalex are not spaced. A `backoff` field in a StackExchange answer is honoured through
`so_backoff_until` (capped at 600 s). A 429 or 403 from a source is an `error` on the query row
(a failed `inspect` also leaves a `note`), never a retry loop. The one retry: arXiv, which answers a
throttled IP with a 429, a 503 page or a held connection at random, is tried once more after 3 s on
a 429, 503 or timeout (the `request` then ends in `(retried once after 3 s)`), then the error stands.

## `~/.claude/dejavu/errors.log`

One line per engine exception: `ts subcommand message`. Hooks always exit 0; an exception in a
hook is logged here and the hook stays silent.

## Config keys (`dejavu.config.json` in the project root, merged over defaults)

| key | default | meaning |
|---|---|---|
| `report_dir` | `docs/dejavu` | where `report` and `publish` write the committed copy |
| `budgets` | `{ "quick": 10, "default": 25, "deep": 40 }` | query budget per depth (advisory to the model; the `NOVEL` check uses half of it) |
| `tiers_required` | `{ "quick": [0,1,2], "default": [0,1,2,3,4,5], "deep": [0,1,2,3,4,5] }` | tiers that must each have at least one query for `NOVEL` |
| `offer` | `true` | `prompt` speaks in plan mode |
| `gate` | `true` | `gate` denies ExitPlanMode once per plan cycle |
| `sources_off` | `[]` | sources `query` and `recheck` refuse without a network call: an `error` row on the check log and an `error` in the summary line, exit 0 (like any other source failure); e.g. behind a proxy |

## Verdict validation (`report`)

| requested | needs | else |
|---|---|---|
| `EXISTS` | one finding with closeness >= 4 and `evidence: fetched` | `PARTIAL`, reason printed; the `PARTIAL` rule then applies |
| `PARTIAL` | one finding with closeness >= 2 and evidence `listed` or `fetched` | `NOVEL`, reason printed; the `NOVEL` rule then applies (so `UNKNOWN` unless the search was complete) |
| `NOVEL` | no listed or fetched finding with closeness >= 2 (a fetched closeness >= 4 finding turns it into `EXISTS`, a listed or fetched closeness >= 2 finding into `PARTIAL`, reason printed); every tier in `tiers_required[depth]` has >= 1 non-errored query row, and non-errored query rows >= half of `budgets[depth]` | `UNKNOWN` with "tiers not covered: ..." and/or "queries n < need" |
| `UNKNOWN` | nothing | stays |

`recalled` findings never count toward any verdict and are listed under "Recalled, not fetched".

## Report template (generated by the engine from the log)

```
# dejavu: <topic>
- **Slug:** <slug>
- **Date:** <YYYY-MM-DD>
- **Depth:** <depth> (<n> of <budget> queries used)
- **Verdict:** <VERDICT>
- **Recommendation:** adopt|fork|wrap|assemble|build
- **Project license:** <L> | languages: <langs>

## Verdict
**<VERDICT>** — <summary>
Engine check: dejavu check: verdict <V> (as claimed | claimed <C>) | findings n (fetched, listed, recalled) | queries n [+ n errored] of <budget> | tiers covered … [| missing …]
- Downgrade: <reason>            (only when the engine changed the verdict)
<one line defining EXISTS / PARTIAL / NOVEL / UNKNOWN>

## Framings
| Framing | Text |                  (problem, mechanism, category)
Synonyms: …

## Closest matches
| # | Name | URL | License | Last activity | Stars/downloads | Closeness | Evidence | Reusable |

## Recommendation
**adopt|fork|wrap|assemble|build** — <summary>
Cost if wrong: <--cost, or _not stated_>

## Reusable parts
- <name>: <reusable>

## License compatibility
Project license: <L>
| Name | License | Compatibility |   (permissive / copyleft / unknown; a flag, not legal advice)

## Search log
| # | Tier | Source | Query | Hits | When | Agent | Request |   (When is `YYYY-MM-DD HH:MM UTC`; Hits reads `error: …` on an errored row)

## Fetched
| URL | Title / name | When | Via |   (Via: engine, inspect or WebFetch, the agent id in parentheses)

## Recalled, not fetched (not evidence)
| Name | URL | Closeness claimed |

## Coverage
- Tiers required / covered / missing
- Sources: <source (n)>, …
- Errors and rate limits: …
- Queries used: n of <budget> (+n errored)
Notes: …                         (the `log note` rows)

## Decision
_Filled by the plan or the user …_

## Re-check
node "<engine>" recheck <slug>
```

`recheck` appends `## Re-check <date>` with the new hits only, and lists the WebSearch queries
that must be re-run by hand.
