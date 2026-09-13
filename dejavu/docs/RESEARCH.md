# dejavu: research notes (2026-09-13)

Idea: a skill that answers "has anyone done this before, and can we adopt, fork, wrap, or
assemble it instead of building it?" before any feature, app, library or tool gets built, with a
search log that makes a negative answer falsifiable, and a plan-mode hook that offers the check
once and gates `ExitPlanMode` until it ran or was skipped.

## Verdict on prior art

Nothing found combines: multi-tier keyless search + a falsifiable negative (search log) +
engine-enforced evidence tagging + license and health check + a committed decision record + a
plan-mode gate + a re-check later. Pieces exist separately; the prose-only "check first" skills
have no sources, no log, no hooks and no gate. Caveat: this was a one-evening sweep by hand (GitHub
search, the skill registries, WebSearch); the skill itself, once built, is run on the same question
and its report is pasted below.

## Closest matches

| Repo | What | Close (1-5) | Reusable |
|---|---|---|---|
| [ShanedevPro/dont-reinvent-the-wheel-skill](https://github.com/ShanedevPro/dont-reinvent-the-wheel-skill) (MIT, 2 stars) | prose-only "check mature solutions first" | 2 | the framing sentence; no sources, no search log, no hooks, no plan-mode tie-in |
| [majiayu000/claude-skill-registry, skills/development/prior-art-search](https://github.com/majiayu000/claude-skill-registry/blob/main/skills/development/prior-art-search/SKILL.md) | a **patent** prior-art skill (BigQuery, CPC codes) | 1 | different domain; confirms `priorart` would have been a confusing name |
| AutoSearch / Deep-Research style skills (several, registries) | general web research with a summary | 2 | tiering idea only; not a build-or-adopt decision, no log, no gate |
| vouch (this repo) | receipts, recall-is-not-evidence, hook engine shapes | 3 | helper functions, the pending-file adoption trick, the claim grammar, the test skeleton |
| PRISMA-S (Rethlefsen et al. 2021, Systematic Reviews 10:39) | reporting standard for literature searches | 4 (for the log) | the per-source strategy, date, filters and record counts became the Search log table |

## Verified facts this design relies on (probed on this machine, 2026-09-13)

| fact | how verified | source |
|---|---|---|
| Hook stdin JSON carries `permission_mode` (`"plan"` in plan mode) on every event; no plan-mode event exists; `PreToolUse` with matcher `ExitPlanMode` / `EnterPlanMode` is the hook point; `UserPromptSubmit` injects `hookSpecificOutput.additionalContext` | a logging hook in a plan-mode session | https://code.claude.com/docs/en/hooks |
| SKILL.md frontmatter supports `hooks:`, `allowed-tools`, `disable-model-invocation`, `agent` | vouch's SKILL.md loads with `hooks:` and `allowed-tools`; docs | same docs |
| WebSearch and WebFetch are read-only, so the whole check can run inside plan mode | plan-mode session | same docs |
| Every hook line that reaches the model costs a turn; only blocks should speak; hooks never touch the network (10 s timeout); recall is not evidence | vouch 0.2.12 build notes (unchanged in 0.2.13) | `vouch/docs/PLAN.md`, "The output-token overhead, explained" |
| vouch 0.2.13 resolves only `cmd:` / `file:` / `read:` receipts, so findings claim with `cmd:dejavu.js inspect <url>`, not a `url:` form | read of `vouch/scripts/vouch.js` guard | this repo |

## Keyless endpoints that answered (2026-09-13)

| source | endpoint | auth | observed | notes |
|---|---|---|---|---|
| GitHub repos, code, topics | `gh search repos\|code --json ...`, `gh api` | the user's `gh` login (gh 2.83 here) | answered | 30 repo and 10 code queries per minute; https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api |
| npm | `registry.npmjs.org/-/v1/search?text=` | none | answered | JSON, includes `links.repository`, `date`, `license` in the package object |
| PyPI | `pypi.org/search/?q=` | none | HTML only | no JSON search API; parsed best-effort, degrades to WebSearch `site:pypi.org` |
| crates.io | `crates.io/api/v1/crates?q=` | none, User-Agent required | answered with UA, refused without | `updated_at`, `downloads`, `repository` per crate |
| Hacker News | `hn.algolia.com/api/v1/search?query=&tags=show_hn` | none | answered | `created_at_i` supports the since-filter for `recheck`; https://hn.algolia.com/api |
| StackExchange | `api.stackexchange.com/2.3/search/advanced?site=stackoverflow` | none | answered, gzip body | `fromdate` for `recheck`; `quota_remaining` in every response |
| OpenAlex | `api.openalex.org/works?search=` | none | answered | `from_publication_date` filter for `recheck` |
| arXiv | `export.arxiv.org/api/query?search_query=` | none | answered, throttles | 3 s spacing between requests, Atom XML |
| grep.app | raw API | none | bot-blocked | MCP endpoint `https://mcp.grep.app` exists; optional, not in v0.1 |

## Naming

`priorart` collides with the patent skill above. `dejavu` was chosen with the user on 2026-09-13
(the feeling of "I have seen this before" is exactly the question). Decided at the same time: plan
mode asks once and gates `ExitPlanMode` until a check ran or the user explicitly skipped; reports
are committed under `docs/dejavu/`; the default depth covers all source tiers.

## Avoid

Prompt-only "search first" instructions (no log, unfalsifiable); a `url:` receipt form that vouch
would not settle; retry loops on a rate limit (log a note instead); hooks that reach the network;
a gate that can deny twice in one plan cycle (the loop risk in `docs/PLAN.md`).

## The skill run on itself

Run by hand on 2026-09-13 (reviewer, Windows, gh 2.83, Node 22) in an empty temp project, following
SKILL.md step by step: `open`, `frame` (three framings), engine queries against gh-repos, gh-code,
gh-topics, npm, crates, pypi, hn, so, openalex, arxiv, two WebSearches logged with `log query
websearch`, `inspect` on the top two, `fetch` of two READMEs, seven `log finding` rows, then
`report --verdict PARTIAL --recommend build --no-docs`. The report below is pasted verbatim from
`.dejavu/checks/<slug>.md`. Two things the run itself exposed, both visible in the search log:
gh-repos queries 1-3 and 18 are 0-1 hits because the engine hands `gh` one quoted argument (an
exact-phrase search), while query 16 (same words, `--since` present, so `gh` does not quote) and
query 17 (one hyphenated keyword) found the real candidates; and tier 0 is "missing" because
SKILL.md never says how to log a `git log -S` / Grep query (`log query grep 0 <hits> "<q>"` works).
The strongest match, r14dd/patent (526 stars, Rust CLI, 19 sources, semantic ranking,
Open/Crowded/Saturated verdict, "never certifies absence"), was found only through gh-topics and the
single-keyword query, not through any of the natural-language gh-repos queries.

# dejavu: a Claude Code skill that checks whether anyone has already built the feature you are about to build, with a plan-mode gate

- **Slug:** a-claude-code-skill-that-checks-whether-anyone-has-already-b
- **Date:** 2026-09-13
- **Depth:** default (18 of 25 queries used)
- **Verdict:** PARTIAL
- **Recommendation:** build
- **Project license:** MIT | languages: javascript

## Verdict

**PARTIAL** — Several Claude skills tell the agent to search first (search-first, dont-reinvent, dont-reinvent-the-wheel) and r14dd/patent is a real 19-source CLI with a semantic verdict, but none combines a keyless multi-tier engine with an append-only search log, engine-tagged evidence, license and health checks, a committed report and a plan-mode gate on ExitPlanMode. Build, and borrow patent's source list and verdict flooring plus dont-reinvent's vetting checklist.

Engine check: dejavu check: verdict PARTIAL (as claimed) | findings 7 (fetched 3, listed 4, recalled 0) | queries 18 + 2 errored of 25 | tiers covered 1,2,3,4,5 | missing 0

EXISTS: a fetched candidate with closeness >= 4. PARTIAL: a listed or fetched candidate with closeness >= 2. NOVEL: every required tier searched and at least half the budget used with no such candidate. UNKNOWN: the search does not support a negative claim.

## Framings

| Framing | Text |
|---|---|
| problem | developers rebuild libraries and tools that already exist because nobody searched before writing the plan |
| mechanism | tiered keyless search across GitHub, package registries, HN, StackOverflow, OpenAlex and the web with an append-only search log and a PreToolUse hook that denies ExitPlanMode once |
| category | prior art search skill / don't reinvent the wheel / build vs buy check for Claude Code |

Synonyms: prior-art, reinvent-the-wheel, build-vs-buy, existing-solutions, similar-projects, alternativeto

## Closest matches

| # | Name | URL | License | Last activity | Stars/downloads | Closeness | Evidence | Reusable |
|---|---|---|---|---|---|---|---|---|
| 1 | r14dd/patent | https://github.com/r14dd/patent | Apache-2.0 | 2026-09-08 | 526 | 4 | fetched | the fan-out list of 19 sources, the Open/Crowded/Saturated verdict floored against similarity data, the 'never certifies absence' stance, stale-flag rule |
| 2 | Emanuelel/dont-reinvent | https://github.com/Emanuelel/dont-reinvent | MIT | 2026-08-28 | 36 | 3 | fetched | vetting checklist (license, maintenance, security) for each candidate instead of star count |
| 3 | shimo4228/search-first | https://github.com/shimo4228/search-first | ? | ? | ? | 3 | listed | source priority order (repo, registries, MCP servers, installed skills, OSS templates); articulate the requirement in plain text before any tool call |
| 4 | Muurrphy/dont-reinvent-the-wheel | https://github.com/Muurrphy/dont-reinvent-the-wheel | ? | ? | ? | 2 | fetched | search before you debug as well as before you build; a project log of known dead ends |
| 5 | ShanedevPro/dont-reinvent-the-wheel-skill | https://github.com/ShanedevPro/dont-reinvent-the-wheel-skill | MIT | ? | ? | 2 | listed | the one-sentence framing |
| 6 | UditAkhourii/neuroarxiv | https://github.com/UditAkhourii/neuroarxiv | ? | ? | ? | 2 | listed | arXiv-only prior-art check before designing an architecture; tier 4 idea |
| 7 | programming-advisor (dev.to write-up) | https://dev.to/gaupoit/vibe-coding-is-great-but-we-dont-need-to-build-anything-from-scratch-2adb | ? | ? | ? | 2 | listed | comparison table of existing solutions shown before writing code |

## Recommendation

**build** — Several Claude skills tell the agent to search first (search-first, dont-reinvent, dont-reinvent-the-wheel) and r14dd/patent is a real 19-source CLI with a semantic verdict, but none combines a keyless multi-tier engine with an append-only search log, engine-tagged evidence, license and health checks, a committed report and a plan-mode gate on ExitPlanMode. Build, and borrow patent's source list and verdict flooring plus dont-reinvent's vetting checklist.

Cost if wrong: a week of engine work duplicated if a maintained skill with a log and a gate turns up

## Reusable parts

- r14dd/patent: the fan-out list of 19 sources, the Open/Crowded/Saturated verdict floored against similarity data, the 'never certifies absence' stance, stale-flag rule
- Emanuelel/dont-reinvent: vetting checklist (license, maintenance, security) for each candidate instead of star count
- shimo4228/search-first: source priority order (repo, registries, MCP servers, installed skills, OSS templates); articulate the requirement in plain text before any tool call
- Muurrphy/dont-reinvent-the-wheel: search before you debug as well as before you build; a project log of known dead ends
- ShanedevPro/dont-reinvent-the-wheel-skill: the one-sentence framing
- UditAkhourii/neuroarxiv: arXiv-only prior-art check before designing an architecture; tier 4 idea
- programming-advisor (dev.to write-up): comparison table of existing solutions shown before writing code

## License compatibility

Project license: MIT

| Name | License | Compatibility |
|---|---|---|
| r14dd/patent | Apache-2.0 | ok (permissive) |
| Emanuelel/dont-reinvent | MIT | ok (permissive) |
| shimo4228/search-first | unknown | unknown: confirm the license before adopting |
| Muurrphy/dont-reinvent-the-wheel | unknown | unknown: confirm the license before adopting |
| ShanedevPro/dont-reinvent-the-wheel-skill | MIT | ok (permissive) |
| UditAkhourii/neuroarxiv | unknown | unknown: confirm the license before adopting |
| programming-advisor (dev.to write-up) | unknown | unknown: confirm the license before adopting |

## Search log

| # | Tier | Source | Query | Hits | When | Agent | Request |
|---|---|---|---|---|---|---|---|
| 1 | 1 | gh-repos | prior art search skill / don't reinvent the wheel / build vs buy check for Claude Code | 0 | 2026-09-13 09:50 | lead | gh search repos "prior art search skill / don't reinvent the wheel / build vs buy check for Claude Code" --limit 10 --sort stars --order desc --json fullName,u… |
| 2 | 1 | gh-repos | claude code skill prior art | 0 | 2026-09-13 09:50 | lead | gh search repos "claude code skill prior art" --limit 10 --sort stars --order desc --json fullName,url,description,stargazersCount,pushedAt,updatedAt,license,i… |
| 3 | 1 | gh-repos | don't reinvent the wheel claude skill | 0 | 2026-09-13 09:50 | lead | gh search repos "don't reinvent the wheel claude skill" --limit 10 --sort updated --order desc --json fullName,url,description,stargazersCount,pushedAt,updated… |
| 4 | 1 | gh-code | ExitPlanMode prior art | 0 | 2026-09-13 09:51 | lead | gh search code "ExitPlanMode prior art" --limit 5 --json path,repository,url |
| 5 | 1 | gh-topics | claude-code-skills | 10 | 2026-09-13 09:51 | lead | gh search repos --topic claude-code-skills --limit 10 --sort stars --order desc --json fullName,url,description,stargazersCount,pushedAt,updatedAt,license,isAr… |
| 6 | 1 | gh-topics | prior art | 5 | 2026-09-13 09:51 | lead | gh search repos --topic prior-art --limit 5 --sort stars --order desc --json fullName,url,description,stargazersCount,pushedAt,updatedAt,license,isArchived,lan… |
| 7 | 2 | npm | claude code skill prior art search | 5 | 2026-09-13 09:52 | lead | GET https://registry.npmjs.org/-/v1/search?text=claude%20code%20skill%20prior%20art%20search&size=5 |
| 8 | 2 | npm | dont reinvent the wheel | 5 | 2026-09-13 09:52 | lead | GET https://registry.npmjs.org/-/v1/search?text=dont%20reinvent%20the%20wheel&size=5 |
| 9 | 2 | crates | prior art search | 5 | 2026-09-13 09:52 | lead | GET https://crates.io/api/v1/crates?q=prior%20art%20search&per_page=5 |
| 10 | 2 | pypi | prior art search | error: pypi search is behind a JS client challenge; use WebSearch "site:pypi.org prior… | 2026-09-13 09:52 | lead | pypi prior art search |
| 11 | 3 | hn | prior art search dev tool | 0 | 2026-09-13 09:52 | lead | GET https://hn.algolia.com/api/v1/search?query=prior%20art%20search%20dev%20tool&tags=show_hn&hitsPerPage=5 |
| 12 | 3 | hn | don't reinvent the wheel check before building | 0 | 2026-09-13 09:52 | lead | GET https://hn.algolia.com/api/v1/search?query=don't%20reinvent%20the%20wheel%20check%20before%20building&tags=story&hitsPerPage=5 |
| 13 | 3 | so | check if a library already exists before writing code | 5 | 2026-09-13 09:52 | lead | GET https://api.stackexchange.com/2.3/search/advanced?order=desc&sort=relevance&q=check%20if%20a%20library%20already%20exists%20before%20writing%20code&site=st… |
| 14 | 4 | openalex | prior art search software reuse code search before building | 5 | 2026-09-13 09:52 | lead | GET https://api.openalex.org/works?search=prior%20art%20search%20software%20reuse%20code%20search%20before%20building&per-page=5&select=id,doi,title,display_na… |
| 15 | 4 | arxiv | code search prior art reuse | error: timeout after 15 s: https://export.arxiv.org/api/query?search_query=all%3Acode%… | 2026-09-13 09:52 | lead | arxiv code search prior art reuse |
| 16 | 1 | gh-repos | reinvent wheel skill | 5 | 2026-09-13 09:54 | lead | gh search repos "reinvent wheel skill pushed:>2020-01-01" --limit 5 --sort stars --order desc --json fullName,url,description,stargazersCount,pushedAt,updatedA… |
| 17 | 1 | gh-repos | prior-art | 5 | 2026-09-13 09:54 | lead | gh search repos prior-art --limit 5 --sort stars --order desc --json fullName,url,description,stargazersCount,pushedAt,updatedAt,license,isArchived,language |
| 18 | 1 | gh-repos | prior art claude | 1 | 2026-09-13 09:54 | lead | gh search repos "prior art claude" --limit 5 --sort stars --order desc --json fullName,url,description,stargazersCount,pushedAt,updatedAt,license,isArchived,la… |
| 19 | 5 | websearch | Claude Code skill "prior art" check before building search existing solutions plan mode | 8 | 2026-09-13 09:55 | lead | manual |
| 20 | 3 | websearch | site:reddit.com Claude Code skill "don't reinvent the wheel" search before building | 6 | 2026-09-13 09:55 | lead | manual |

## Fetched

| URL | Title / name | When | Via |
|---|---|---|---|
| https://github.com/r14dd/patent | r14dd/patent | 2026-09-13 09:54 | inspect |
| https://github.com/Emanuelel/dont-reinvent | Emanuelel/dont-reinvent | 2026-09-13 09:54 | inspect |
| https://crates.io/crates/patent | patent | 2026-09-13 09:54 | inspect |
| https://github.com/Muurrphy/dont-reinvent-the-wheel | GitHub - Muurrphy/dont-reinvent-the-wheel: Claude skill: search before you build, search before you debug - external libraries, your own project log, and known dead ends, with a reuse/fork/build verdict · GitHub | 2026-09-13 09:54 | engine |
| https://raw.githubusercontent.com/r14dd/patent/HEAD/README.md |  | 2026-09-13 09:54 | engine |

## Recalled, not fetched (not evidence)

_none_

## Coverage

- Tiers required: 0, 1, 2, 3, 4, 5; covered: 1, 2, 3, 4, 5; missing: 0
- Sources: gh-repos (6), gh-code (1), gh-topics (2), npm (2), crates (1), pypi (1), hn (2), so (1), openalex (1), arxiv (1), websearch (2)
- Errors and rate limits: pypi: pypi search is behind a JS client challenge; use WebSearch "site:pypi.org prior art search" or insp…; arxiv: timeout after 15 s: https://export.arxiv.org/api/query?search_query=all%3Acode%20AND%20all%3Asearch…
- Queries used: 18 of 25 (+2 errored)

Notes:
- arxiv: timeout after 15 s on the single tier-4 arXiv query (tarpit); tier 4 covered by openalex only
- pypi: search behind a JS client challenge; no pypi query possible, tier 2 covered by npm and crates
- gh-repos: multi-word queries are sent as one quoted argument, gh turns that into an exact-phrase search (q=%22...%22); 3 of the first 4 gh-repos queries returned 0 hits, the same words with --since or as a single hyphenated keyword returned the real candidates

## Decision

_Filled by the plan or the user: what was decided (adopt / fork / wrap / assemble / build), why, and when._

- 

## Re-check

```
node "C:/Users/<user>/Desktop/Skills for claude/dejavu/scripts/dejavu.js" recheck a-claude-code-skill-that-checks-whether-anyone-has-already-b
```
