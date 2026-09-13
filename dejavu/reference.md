# dejavu reference: every rule, its evidence, or its label as a hypothesis

Research sweep 2026-09-13 (prior art on the skill itself, harness docs, endpoint probes). Full
notes in `docs/PLAN.md` and `docs/RESEARCH.md`. Where a rule is inherited from vouch, the vouch
citation is repeated here so this file stands alone.

## The search log: a negative result must be reproducible

| claim | source |
|---|---|
| A search claim is reportable only with the full strategy for every database, register and website searched, including filters and limits, and the date each was searched | PRISMA 2020 item 7, Page MJ et al., BMJ 2021;372:n71, https://www.prisma-statement.org/ |
| Per source: name and platform, date searched, full strategy as run, limits and filters, and the number of records returned; web and grey-literature searches reported the same way; every strategy repeatable by a reader | PRISMA-S (16 items), Rethlefsen ML, Kirtley S, Waffenschmidt S, et al., Systematic Reviews 2021;10:39 |
| The report's Search log table (tier, source, query, hits, when, agent, exact request) is PRISMA-S applied to build-vs-adopt; `recheck` is the update search PRISMA-S asks to be documented | this skill, by construction |
| A "nothing found" that names no query cannot be falsified, so it is not a finding; `NOVEL` requires every required tier to carry at least one query row | this skill, by construction; the tier list is a hypothesis (below) |

## Recall is not evidence (inherited from vouch)

| claim | source |
|---|---|
| A remembered candidate is a lead; only a fetch, an inspect, or a listing in a logged query result makes it a finding | vouch rule 0, `vouch/reference.md` |
| 20-30 point accuracy loss when the needed content sits mid-context; frontier models degrade monotonically with context length | Liu et al., Lost in the Middle, arXiv:2307.03172; Chroma, Context Rot, 2025 |
| Unforgeable tool receipts detect 94 percent of fabricated tool references and 91 percent of false-absence claims | arXiv:2603.10060 (vouch's receipt ledger; dejavu's `evidence` tag is the same idea applied to URLs) |
| Post-training rewards guessing over abstention; the fix is a scoreboard that prefers "I don't know" to a confident error | Kalai, Nachum, Vempala, Zhang, arXiv:2509.04664 (why `UNKNOWN` is a verdict, and why the engine downgrades rather than the model) |
| vouch 0.2.13 settles only `cmd:`, `file:`, `read:` receipts; a URL is not a receipt, the `inspect` command that fetched it is | `vouch/scripts/vouch.js` guard, checked 2026-09-13 |
| The model recommends, the user decides: `skip` refuses to run without `--user-said "<the user's own words>"`, because one of three headless plan-mode runs recorded a skip nobody had asked for | `bench/results/20260913-152353-live-planmode.session.json` (skip with no user answer); the engine check is in `tests/run.sh` case 4 |

## Budgets, stop rules, fan-out

| claim | source |
|---|---|
| Injected budget-used/remaining cut wasted tool calls 40 percent at equal accuracy | Budget-Aware Tool Use, arXiv:2511.17006 (the `invoke` line prints the query budget) |
| Models are optimistically biased about remaining budget; the clock must be harness-side | BAGEN, arXiv:2606.00198 (the `NOVEL` half-budget check is counted from log rows, not from the model's count) |
| Multi-agent fan-out on sequential work costs 1.58x to 6.15x tokens with negative returns; parallel independent subtasks and an orchestrator cross-check are the case where it pays | arXiv:2512.08296 (scouts own disjoint tiers and return rows the lead cross-checks) |
| Inline floor and a cap of three dispatches | ekamphuis82/claude-code-swarm, midego1/claude-orchestrate (MIT, patterns reused via vouch) |
| Circuit breaker after repeated identical failures; a rate limit is logged, never retried in a loop | frankbria/ralph-claude-code pattern (via vouch); dejavu logs an `error` row and a note |

## Harness facts (checked on this machine, 2026-09-13)

| fact | source |
|---|---|
| Hook stdin JSON carries `permission_mode` on every event; no plan-mode event exists; `PreToolUse` with matcher `ExitPlanMode` / `EnterPlanMode` is the hook point; `UserPromptSubmit` injects `hookSpecificOutput.additionalContext`; `PreToolUse` denies with `permissionDecision: "deny"` | https://code.claude.com/docs/en/hooks, probed 2026-09-13 |
| SKILL.md frontmatter supports `hooks:`, `allowed-tools`, `disable-model-invocation`, `agent`; the `allowed-tools` grant covers the invoking turn | same docs; `install.md` recommends a `Bash(node *)` allow rule for the rest |
| WebSearch and WebFetch are read-only, so a check can run inside plan mode; the repo is read-only there, hence `report --no-docs` and `publish` after approval | same docs |
| Every hook line that reaches the model costs a turn; only blocks should speak | `vouch/docs/PLAN.md` (the output-token overhead, 2026-09-11); dejavu's hooks speak one SessionStart line (only when reports exist) plus one offer and one deny per plan cycle |
| `gh search repos` and `gh search code` are limited to 30 and 10 requests per minute when authenticated | https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api, probed with gh 2.83 |
| HN Algolia search is keyless; StackExchange `search/advanced` is keyless and gzip-encoded; OpenAlex `works?search=` is keyless; crates.io requires a User-Agent; arXiv asks for 3 s between requests; PyPI has no JSON search, only HTML | https://hn.algolia.com/api and the probes in `docs/RESEARCH.md` |

## Hypotheses (unmeasured; the measurement plan is in `TESTING.md`)

| rule | why it is here | what would confirm or refute it |
|---|---|---|
| **Three framings** (problem, mechanism, category) find candidates a single framing misses | PRISMA-S asks for synonyms and controlled vocabulary per concept; the analogue for code search is untested | on a labelled topic set, the share of closeness >= 4 matches found by the second and third framing only |
| **Stop rules**: stop a tier after two consecutive zero-new queries; stop the check when the top 3 are stable across two framings; never before tiers 0 and 1 | budget discipline (arXiv:2511.17006) with thresholds picked by judgement | recall against the labelled set at each threshold; a lower threshold with equal recall wins |
| **Closeness thresholds**: `EXISTS` at >= 4 fetched, `PARTIAL` at >= 2 listed | the scale is ordinal and the cut points are a guess | inter-rater agreement between two runs and a human on 20 topics |
| **Tier coverage as the `NOVEL` criterion**, with half the budget spent | a proxy for "searched enough"; it can be gamed by cheap queries | false-`NOVEL` rate on topics known to have prior art |
| **Query budgets** 10 / 25 / 40 | arXiv:2511.17006 shows that a budget helps; these numbers are a guess | verdict accuracy vs queries used, per depth |
| **Offer once, gate once** per plan cycle | one line and one deny cost one turn each (`vouch/docs/PLAN.md`); more would loop | offer count and deny count per plan cycle in the live bench must be exactly 1 and <= 1 |
| **2 h adoption window** for `current.json` and `pending-skip.json` | Bash subcommands do not see a reliable session id; vouch's `pending-invoke.json` uses the same trick | any cross-adoption between two concurrent sessions in the same project is a failure of this rule |

## Measurement

Per check the log records: queries per tier and source, hits, errors and rate limits, findings
by evidence class, the requested and the validated verdict, and the queries used of budget. The
skill passes only if, on a labelled topic set, it never returns `EXISTS` for a topic with no prior
art, never returns `NOVEL` for a topic with a known closeness-4 match, and the plan-mode offer
appears exactly once per plan cycle. No published number exists for any of this; the measurement
is the contribution.
