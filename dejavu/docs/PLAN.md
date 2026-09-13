# Plan: dejavu, built 2026-09-13

## Build status (2026-09-13)

- Built per the sequence below. Deviations from the plan, all deliberate:
  - `skip` takes `--user-said "<the user's own words>"` and refuses to run without it (exit 1);
    the plan had `skip "<reason>"`. Reason: in one of three headless plan-mode runs the model
    recorded a skip on the user's behalf. The user's requirement is that the model recommends and
    the user approves or declines, so the engine now enforces it; `user_said` is stored in
    `pending-skip.json`, `skips.jsonl` and the session file, and the offer and gate reason show the
    exact form.
  - `gh-repos` / `gh-code` send each word of the query as a separate `gh` term (a `"quoted phrase"`
    stays one term). The plan's single quoted argument made every multi-word query an exact-phrase
    search: 3 of the first 4 gh-repos queries in the skill's own self-run returned 0 hits.
  - `inspect pypi:<name>` (PyPI JSON API) and `inspect <url>` were added to the plan's
    GitHub / npm / crates.io list; `fetch` of a github.com repo URL reads the README through the
    contents API instead of the 200 KB page.
  - `sources_off` yields an error row and exit 0 (like any other source failure), not exit 1.
  - A `PARTIAL` claim with no listed or fetched closeness >= 2 finding falls to `NOVEL` and is then
    held to the `NOVEL` rule (usually `UNKNOWN`), and a `NOVEL` claim contradicted by evidence is
    raised to `PARTIAL` or `EXISTS`; the plan only listed the downgrades.
  - Tier 0 has no engine source; it is recorded with `log query self 0 <hits> "<terms>"` (the
    self-run showed tier 0 "missing" until SKILL.md said so). Engine-run tier 0 is a v0.2 item.
  - arXiv is retried once after 3 s on a 429, 503 or timeout (the plan said never retry; one retry is
    not a loop, and the host answers a throttled IP at random per request).
- Verified (2026-09-13): `bash dejavu/tests/run.sh` -> `passed 173 failed 0` (16 groups; the arXiv
  happy-path case is skipped, no fixture); `bash dejavu/bench/live.sh endpoints` (16:34) ->
  `errors=0 rate-limited=2`, exit 0: gh-repos 10, gh-code 10, gh-topics 10, npm 10, crates 10, hn 8,
  so 10, openalex 10 hits; pypi 0 (JS client challenge), arxiv 0 (two 15 s timeouts around the 3 s
  retry); three `inspect` calls each one `fetched` row; `claude plugin validate dejavu` ->
  "Validation passed". Live `claude -p` runs (Sonnet, `bench/results/`): `invoke` 15:19, verdict
  EXISTS / adopt, 6 of 10 queries, 3 inspects, all Closest-matches rows `fetched`, report committed,
  12 turns, $0.24; `planmode` 15:21, 15:23, 15:34: `offered: true` 3 of 3, the gate driven by the
  bench (the `-p` tool list lacks ExitPlanMode and AskUserQuestion) denied once then allowed in both
  runs where it was driven; run 2 (15:23) recorded a skip with no user answer, which `--user-said`
  now prevents. The skill run on itself (by hand, default depth): PARTIAL / build, 18 of 25 queries,
  pasted in `docs/RESEARCH.md`.
- Not verified in this pass: an interactive plan-mode session (accept path: `/dejavu` inside plan
  mode, `--no-docs`, then `publish` after approval; decline path with a real user answer), the
  skills-dir install path, the arXiv happy path against a real Atom feed, the self-run repeated
  with the fixed `gh` quoting, and every number in `TESTING.md` tier 2 (verdict accuracy on a
  labelled set).
- Live incidents during the build:
  - vouch 0.2.13 (the ledger is a tree): the moment this build's parallel subagents started
    appending receipts, two vouch hooks chained onto the same ledger tail; the old verifier voided
    every receipt after the fork (2/280 valid), the grounding lock denied every edit for the rest
    of the session and charged 50 coins each time, and `writeJson` lost state to `EPERM` on the
    rename. Fixed in vouch 0.2.13 (a receipt is valid when its `prev` is any earlier valid row;
    rename retried); dejavu's own `writeJson` carries the same retry.
  - `gh` exact-phrase quoting (above), found by the skill's own search log on itself.
  - arXiv throttled this IP all day: 429 `Rate exceeded.`, 503 pages, or a held connection, at random
    per request; no `arxiv.xml` fixture could be captured (six tries in the morning, one more with a
    10 s retry at 16:30). The engine now retries once; the bench classifies all three forms as
    RATE-LIMITED.
  - PyPI serves a JS client challenge on `/search` to non-browsers; `pypi` is best-effort, the
    exact-name JSON endpoint and `inspect pypi:` still answer.
  - `claude -p` (2.1.270) lists neither ExitPlanMode nor AskUserQuestion in plan mode, so the
    plan-mode bench drives `gate` itself with the live session id.
  - The `invoke` run was denied once for `cd <plugin> && node ...` (outside `Bash(node *)`);
    SKILL.md now says to run the absolute engine path from the project root, never `cd`.
  - One headless plan-mode run skipped on the user's behalf (above); `skip --user-said` is the fix.
- Docs corrected to match the engine in the closing pass: the `PARTIAL` downgrade target, the
  `sources_off` exit code and the `recheck` row shape in `log/SCHEMA.md`; no `mailto` config and no
  low-quota note in `THIRD_PARTY_NOTICES.md`; keyless `api.github.com` (60/h) for `inspect` without
  `gh` in `install.md`; the hooks' speaking budget in `README.md` and `reference.md`; vouch cited as
  0.2.13.

### v0.2 follow-ups

- Engine-run tier 0: a `query self` source that runs `git log -S`, a repo grep and
  `docs/dejavu/` itself, so tier 0 is logged with a real request instead of `log query self`.
- Re-run the skill on itself with the fixed `gh` quoting and commit the report under
  `docs/dejavu/` (the current one in `docs/RESEARCH.md` was made with the exact-phrase bug and
  `--no-docs`).
- arXiv resilience: capture the Atom fixture once the throttle lifts and make the happy-path test
  unconditional; consider OpenAlex as the tier-4 fallback when arXiv errors twice in one check, and a
  `mailto` config key for OpenAlex's polite pool.


## Context

The repo is a marketplace of Claude Code plugins, one folder per skill (only `vouch` exists today).
The next skill answers one question before any feature, app, library, or tool gets built: **has
anyone done this before, and can we adopt, fork, wrap, or assemble it instead of building it?** The
model and harness do the sweep (GitHub, registries, discussion sites, papers, the general web, and
the user's own code), then write a report with a verdict, the closest matches, a recommendation,
and a **search log** so that "nobody has done this" is a falsifiable claim, not a feeling.

Second requirement (user): once installed, the skill must surface **automatically in plan mode**.
The harness recommends the check while a plan is being written and gets the user's approval.

Decided with the user (2026-09-13): name **`dejavu`**; plan mode asks once and **gates
ExitPlanMode** until a check ran or the user explicitly skipped; reports are **committed** under
`docs/dejavu/`; the default depth covers **all** source tiers.

### Prior art on this skill itself (checked 2026-09-13)

- `ShanedevPro/dont-reinvent-the-wheel-skill` (MIT, 2 stars): prose-only "check mature solutions
  first". No sources, no search log, no hooks, no plan-mode tie-in.
- `majiayu000/claude-skill-registry … prior-art-search`: a **patent** prior-art skill (BigQuery,
  CPC codes). Different domain; confirms `priorart` would have been a confusing name.
- AutoSearch / Deep-Research skills: general research, not a build-or-adopt decision, no gate.
- Nothing found combines: multi-tier keyless search + falsifiable negative (search log) +
  engine-enforced evidence + license and health check + a committed decision record + a plan-mode
  gate + re-check later. That combination is the skill. (Goes into `dejavu/docs/RESEARCH.md`; the
  built skill is then run on itself and that report is pasted in.)

### Verified facts this plan relies on (probed on this machine, 2026-09-13)

- Hook stdin JSON carries `permission_mode` (`"plan"` in plan mode) on every event. No plan-mode
  event exists; `PreToolUse` with `matcher: "ExitPlanMode"` / `"EnterPlanMode"` is the hook point.
  UserPromptSubmit injects context via `hookSpecificOutput.additionalContext`.
- SKILL.md frontmatter supports `hooks:`, `allowed-tools`, `disable-model-invocation`, `agent`.
- Keyless endpoints that answered: `gh search repos/code --json` (gh 2.83 authenticated here; 30
  and 10 queries/min), npm `registry.npmjs.org/-/v1/search`, crates.io `api/v1/crates?q=` (needs a
  User-Agent), HN Algolia, StackExchange `search/advanced` (gzip), OpenAlex `works?search=`, PyPI
  only as HTML. arXiv throttles (3 s spacing). grep.app raw API is bot-blocked; its MCP endpoint
  `https://mcp.grep.app` exists (optional, not in v0.1).
- WebSearch and WebFetch are read-only, so the whole check can run **inside plan mode**.
- Inherited rules (`vouch/docs/PLAN.md:93`): every hook line that reaches the model costs a turn,
  only blocks speak; hooks never touch the network (10 s timeout); recall is not evidence.
- vouch 0.2.13 (0.2.12 when the plan was written) resolves only `cmd:` / `file:` / `read:`
  receipts, so findings claim with `cmd:dejavu.js inspect <url>`, not a `url:` form.

## What gets built

```
dejavu/
  .claude-plugin/plugin.json      name dejavu, version 0.1.0 (version #1)
  SKILL.md                        /dejavu [quick|default|deep] <what you are about to build> (version #2)
  README.md  install.md  reference.md  THIRD_PARTY_NOTICES.md  TESTING.md
  hooks/hooks.json                normal-mode hooks (below)
  scripts/dejavu.js               zero-dep Node 18 engine: hooks + fetchers + log + report
  agents/dejavu-scout.md          read-only search subagent
  log/SCHEMA.md                   state files, log rows, report template
  tests/run.sh  tests/fixtures/   pipe-test battery, offline (fixtures per source, a full log)
  bench/live.sh                   real endpoints + real `claude -p` runs (invoke, planmode)
  docs/PLAN.md  docs/RESEARCH.md
  evals/<case>/                   plugin-eval cases, same shape as vouch/evals
```
Root edits: `.claude-plugin/marketplace.json` entry (version #3), `README.md` table row and a
wider marketplace description, `.gitignore` (`.dejavu/`, `dejavu/bench/results/*.err`), dogfood
hooks in `.claude/settings.json` + `.claude/agents/dejavu-scout.md` (as vouch does for itself).

### State and outputs

```
.dejavu/sessions/<session_id>.json   {offered, gate_denied, checks[], skip, seen{}}
.dejavu/checks/<slug>.json           {topic, depth, langs, framings, status open|reported, verdict}
.dejavu/checks/<slug>.jsonl          append-only log: query / fetch / finding / note / recheck rows
.dejavu/checks/<slug>.md             canonical report copy (always written)
.dejavu/current.json                 open check {slug, depth, ts, adopted_by}
.dejavu/pending-skip.json            {ts, reason}; consumed by the next hook that has a session id
.dejavu/ratelimit.json               last-call ts per source
docs/dejavu/<slug>.md                the committed report (written by `report`, or by `publish` after plan approval)
```
CLI subcommands run through Bash where `CLAUDE_SESSION_ID` is not reliable, so checks are keyed
by slug and `current.json` / `pending-skip.json` are **adopted** by the first hook that carries a
`session_id` (2 h window, `adopted_by` stamp). Same trick as vouch's `pending-invoke.json`.

### Engine: `scripts/dejavu.js`

Copy vouch's helper shapes from `vouch/scripts/vouch.js`: `readStdin`, `readJson`, `writeJson`
(tmp+rename, add a retry on Windows rename races), `appendLine`, `out`, `ctx`, `seenBefore`,
`main()` that logs to `~/.claude/dejavu/errors.log` and always exits 0 for hooks. Config
`dejavu.config.json` merged over defaults: `report_dir`, `budgets {quick:10, default:25, deep:40}`,
`tiers_required {quick:[0,1,2], default/deep:[0..5]}`, `offer`, `gate`, `sources_off`.

**Hook subcommands** (stdin JSON in, filesystem only, never network):

| cmd | event | behaviour |
|---|---|---|
| `start` | SessionStart | counts `docs/dejavu/*.md`; prints one line only if N>0 (`dejavu: N reports on file, latest <slug> <verdict> <date>`) |
| `prompt` | UserPromptSubmit | if `permission_mode=="plan"`, not yet offered this session, no check/skip recorded, prompt not `/dejavu…` → one `additionalContext` line: "Plan mode: before you write the plan, ask the user once (AskUserQuestion) whether to run `/dejavu [quick\|default\|deep] <what is being built>` or skip it (`node <abs engine> skip "<reason>"`). Do not ask again." Sets `offered`. Otherwise silent. |
| `gate` | PreToolUse `ExitPlanMode` | dedupe by `tool_use_id`; if a reported check or a skip exists for the session, or already denied once → allow (silent). Else set `gate_denied` and return `permissionDecision: "deny"` with the same instruction. **Denies once per plan cycle, so no loop.** |
| `enter` | PreToolUse `EnterPlanMode` | resets `offered` / `gate_denied` if the session is still unsatisfied (a second plan cycle gets one more offer). Never prints. |
| `receipt` | PostToolUse `WebFetch\|WebSearch` | if a check is open, append a `fetch` row (WebFetch url) or a `query` row (source `websearch`) to its log. Never prints. Also declared as a SKILL.md-level hook so skills-dir installs still log; `seenBefore` makes the double delivery harmless. |

**CLI subcommands** (run by the model or the scout via Bash; may use the network):

| cmd | does |
|---|---|
| `invoke <depth>` | SKILL.md `!` line (`$0` only, like vouch). Prints depth, query budget, required tiers, detected languages (package.json / pyproject / Cargo.toml / go.mod), project license, session state, and the next command. Non-depth word → `default`. |
| `open "<topic>" [--depth]` | derives the slug, writes check meta + `current.json`. |
| `frame <slug> "<problem>" "<mechanism>" "<category>" [--syn a,b]` | records the three framings. |
| `query <source> "<q>" [--limit N] [--since date] [--tier N] [--framing F] [--agent id]` | sources `gh-repos`, `gh-code`, `gh-topics` (via `gh`), `npm`, `pypi` (HTML, best-effort), `crates`, `hn`, `so`, `openalex`, `arxiv` (3 s spacing). Node 18 fetch, 15 s abort, UA `dejavu/<ver>`. Prints normalized rows `{name,url,desc,stars_or_downloads,updated,license,source,evidence:"listed"}` + a summary line; appends a `query` row `{source,tier,framing,q,request,hits,top[],ms,error?}`. Unknown source → exit 1; network error → error row, exit 0. `DEJAVU_FIXTURES=<dir>` reads `<dir>/<source>.json` instead of the network; `DEJAVU_OFFLINE=1` throws on any fetch (tests prove hooks never fetch). |
| `fetch <url>` | GET, 200 KB cap, tags stripped, title + first 80 lines; logs a `fetch` row. |
| `inspect <url \| owner/name \| npm:name \| crate:name>` | health and license: `gh api repos/…` (license, pushed_at, stars, archived, open_issues), npm registry doc, crates.io doc. Logs `fetch` + `meta` rows; prints one row with `evidence:"fetched"`. |
| `log query <source> <tier> <hits> "<q>"` / `log finding "<name>" "<url>" --closeness 1-5 --reusable "…" [--license --updated --stars --source --framing]` / `log note "<text>"` | positional args (JSON on a Windows command line is fragile). A finding's `evidence` is set by the engine: `fetched` if a fetch/inspect row has the URL, `listed` if any query's `top[]` has it, else `recalled`. Missing URL → exit 1. |
| `report <slug> --verdict EXISTS\|PARTIAL\|NOVEL\|UNKNOWN --recommend adopt\|fork\|wrap\|assemble\|build --summary "…" [--no-docs]` | assembles the markdown from the log, **validates the verdict** (below), writes `.dejavu/checks/<slug>.md` and, unless `--no-docs`, `docs/dejavu/<slug>.md`; marks the check `reported`, closes `current.json`; prints the path, the final verdict and why, and suggested claim lines. |
| `publish <slug>` | copies the canonical report to `docs/dejavu/` (used after plan approval when the check ran in plan mode with `--no-docs`). |
| `recheck <slug>` | re-runs every engine-runnable query with a since-filter = report date (gh `pushed:>`, HN `created_at_i>`, SO `fromdate`, OpenAlex `from_publication_date`; registries diff by name against the logged `top[]`), lists WebSearch queries for manual re-run, appends `## Re-check <date>` to both report copies, prints only new hits. |
| `skip "<reason>"` | writes `pending-skip.json` + `skips.jsonl`; prints "skip recorded, the plan-mode gate is open". |
| `status` | session state, open check, reports on file. |

**Verdict validation** (what makes a negative result falsifiable):
- `EXISTS` needs ≥1 finding with closeness ≥4 **and** `evidence: fetched`; else downgraded to
  `PARTIAL` with the reason printed.
- `PARTIAL` needs ≥1 finding with closeness ≥2 and evidence `listed` or `fetched`.
- `NOVEL` needs every tier in `tiers_required[depth]` covered by ≥1 query and total queries ≥ half
  the budget; else `UNKNOWN` with "tiers not covered: …" printed.
- `recalled` findings go into a separate "Recalled, not fetched (not evidence)" section and never
  count toward any verdict.

**Report sections** (template in `log/SCHEMA.md`, generated by the JS): title, topic, date, depth;
Verdict (with the engine's check line); Framings; Closest matches table (name, url, license, last
activity, stars/downloads, closeness, evidence, reusable); Recommendation + summary + cost if
wrong; Reusable parts; License compatibility vs the project's license; Search log table (#, tier,
source, query, hits, when, agent, request); Fetched; Recalled, not fetched; Coverage (tiers,
sources, errors and rate limits, queries used of budget); Decision (filled by the plan or user);
Re-check command.

### SKILL.md

Frontmatter: `name: dejavu`; description "Has anyone done this before? Tiered search of GitHub,
package registries, HN and StackOverflow, papers and the web for existing implementations of what
you are about to build; writes docs/dejavu/<slug>.md with a verdict, closest matches, a
recommendation and a search log that makes a negative result falsifiable. Invoke when the user
asks, or after they agree to the plan-mode offer."; `argument-hint: "[quick|default|deep] <what
you are about to build>"`; `allowed-tools: Bash(node *)` (the `!` line must not prompt);
**model-invocable** (no `disable-model-invocation`) so the AskUserQuestion flow can start it;
`license`, `compatibility` (gh optional: Tier 1 degrades to WebSearch), `metadata.version`,
`hooks: PostToolUse WebFetch|WebSearch → receipt`.

Body (<250 lines), in order:
1. `!node "${CLAUDE_SKILL_DIR}/scripts/dejavu.js" invoke $0` then `Task: $ARGUMENTS`.
2. **Open and frame.** `open "<topic>"`, then three one-line framings before any search: the
   *problem* (the pain, in the user's words), the *mechanism* (algorithm / protocol / data
   structure), the *category* (what someone would google). Synonyms, ecosystem jargon, detected
   languages. Most people search only one framing; that is why prior-art checks miss.
3. **Tiers.** 0 self: `git log -S`, `Grep` the repo, `docs/dejavu/` for an earlier report,
   `gh search repos --owner @me`. 1 GitHub: `gh-repos` ×3 framings (by stars and by updated),
   `gh-code` ×1–2, `gh-topics`, awesome-lists (`fetch` the README). 2 registries by language:
   npm / pypi / crates via the engine, Maven / RubyGems / Hex / Go via WebSearch `site:`.
   3 discussion: `hn` (show_hn), `so`, Reddit via WebSearch. 4 papers: `openalex`, one `arxiv`
   query. 5 general web: WebSearch for products, SaaS, `site:alternativeto.net`, "alternatives".
4. **Depths.** quick: tiers 0–2, main agent only, ~10 queries, `inspect` top 1. default: all
   tiers, up to 3 `dejavu-scout` subagents in parallel (A tier 1, B tiers 2–3, C tiers 4–5; the
   lead does tier 0 and merges; only one scout gets `gh-code`), ~25 queries, `inspect` top 3.
   deep: default + `fetch` READMEs of the top 5, `inspect` each, follow one hop of "see also /
   alternatives", ~40 queries.
5. **Stop rules.** Stop a tier after two consecutive queries add no new candidate; stop the check
   when the top 3 are stable across two framings or the budget is spent; never stop before tiers
   0 and 1; a rate limit or error is a `log note`, never silently skipped.
6. **Recall is not evidence.** A remembered candidate is a lead: `query`, `fetch` or `inspect` it
   first. Closeness ≥4 requires `inspect` or `fetch`.
7. **Report.** `report <slug> …`, `Read` it once, then ≤12 lines to the user: verdict, top 3 with
   URLs, recommendation, re-check command. **In plan mode:** pass `--no-docs` (plan mode is
   read-only for the repo), put the verdict and recommendation in the plan's approach section, and
   make `node dejavu.js publish <slug>` the plan's first step.
8. **When vouch is armed:** end with claim lines using `cmd:dejavu.js inspect <url>` and
   `file:docs/dejavu/<slug>.md` receipts, and `CLAIM: NOT VERIFIED - <source> rate-limited`.

### Agent `agents/dejavu-scout.md`

`model: sonnet`, `tools: WebSearch, WebFetch, Bash, Read, Grep, Glob`, `maxTurns: 20` (agent
frontmatter does not take `Bash(gh *)` patterns; restrict by prose: only `node <engine>`, `gh
search|api`, `curl -s`; nothing that writes). Input: engine path, slug, agent id, one framing +
synonyms, tiers, budget, languages. Output: `ROW | name | url | source | listed|fetched | license |
updated | stars | closeness | reusable` lines, then `QUERIES: n run, n zero-hit` and `NOTE:` lines.
A row without a URL it actually saw is a violation; "nothing found" must name the queries. No
build-vs-adopt opinion (the lead decides).

### Hooks `hooks/hooks.json`

```
SessionStart                     → node dejavu.js start
UserPromptSubmit                 → node dejavu.js prompt
PreToolUse  matcher ExitPlanMode → node dejavu.js gate
PreToolUse  matcher EnterPlanMode→ node dejavu.js enter
PostToolUse matcher WebFetch|WebSearch → node dejavu.js receipt
```
Speaking budget: one SessionStart line (silent at 0 reports), one offer line per plan cycle, one
deny per plan cycle. Everything else is silent.

### Tests `tests/run.sh` (vouch skeleton: isolated HOME + project, `cygpath -m`, `ok/bad`, JSON builders; `DEJAVU_FIXTURES` set)

1. `prompt` outside plan mode → silent, no session file.
2. `prompt` in plan mode → one line naming AskUserQuestion and `/dejavu`; second call silent.
3. `gate` → deny once with reason naming `/dejavu` and `skip`; new `tool_use_id` → allow; replayed id → silent.
4. `skip` then, in a new session, plan-mode `prompt` and `gate` both silent; session file shows the skip.
5. `enter` on an unsatisfied session re-arms one offer and one deny.
6. `invoke deep|frobnicate`, `open`, `frame` write the expected files.
7. `query` for every source from fixtures → normalized rows + log row with `hits` and `request`; `query bogus` → exit 1.
8. `log finding` evidence tagging: URL in a fixture `top[]` → `listed`; unknown URL → `recalled`; missing URL → exit 1.
9. `receipt` with an open check logs WebFetch / WebSearch rows, dedupes by id, writes nothing with no open check.
10. `report` from `fixtures/log.jsonl`: sections present, search-log row count matches; closeness-5 `recalled` finding with `--verdict EXISTS` → `PARTIAL`; `--verdict NOVEL` with tier gaps → `UNKNOWN` naming the tiers; `--no-docs` writes only the canonical copy; `publish` copies it.
11. After `report`, a new session's `gate` adopts `current.json` and allows.
12. `start` prints the count with reports present, nothing at 0; `status` lists them.
13. `recheck` with a recheck fixture prints only the new hit and appends the section.
14. `DEJAVU_OFFLINE=1`: all five hook subcommands succeed; `query` logs an error row, exit 0.
15. Hook latency < 400 ms.

`bench/live.sh endpoints` hits every real source once ("token bucket rate limiter") plus three
`inspect` calls, prints hits/ms/errors; `bench/live.sh invoke [model]` runs `claude -p "/dejavu
quick …" --plugin-dir dejavu` (with `MSYS_NO_PATHCONV=1`, `env -u CLAUDECODE`, vouch findings)
and asserts a report with ≥5 query rows and only `listed|fetched` findings in the table;
`bench/live.sh planmode [model]` runs `--permission-mode plan` and asserts `offered: true` and,
if ExitPlanMode was called, `gate_denied: true` followed by a question or a skip.
`evals/`: "quick check writes a report with a search log". The "plan mode offers the check and
gates exit" case lives in `bench/manual-cases/` until headless children expose the plan-mode tools
(2.1.270 does not), and is run through the playground and graded by `bench/evaluate.sh`.

### Docs

`reference.md`: search-log standard → PRISMA 2020 / PRISMA-S (full strategy per database with
date and filters); "recall is not evidence" → vouch; multi-framing and stop rules labelled
hypothesis until measured. `THIRD_PARTY_NOTICES.md`: API terms (npm, crates.io UA policy, HN
Algolia, StackExchange CC BY-SA, OpenAlex, arXiv). `docs/RESEARCH.md`: the prior-art notes above
+ the verified source table + the skill's own report on itself. `install.md`: vouch's A–E paths,
plus a recommended `Bash(node *)` allow rule (the frontmatter grant covers only the invoking turn).

## Implementation sequence

1. Scaffold folder; engine skeleton (helpers, config, state, `adoptPending`, `main`).
2. Hook subcommands + tests 1–5, 9, 12, 14, 15.
3. CLI `invoke`, `open`, `frame`, `skip`, `status`, `log` + tests 6, 8.
4. Source table, `query`, `fetch`, `inspect`, fixtures, rate spacing + test 7.
5. `report` + validation, `publish`, `recheck` + tests 10, 11, 13.
6. `SKILL.md`, `agents/dejavu-scout.md`, `hooks/hooks.json`, `log/SCHEMA.md`.
7. `bench/live.sh endpoints` against the real APIs; fix parsers against real payloads; then the
   `invoke` and `planmode` runs in `playground2`.
8. Docs, root edits (marketplace, README, .gitignore, dogfood hooks), full battery, commit as
   `dejavu 0.1.0: <one line>`.

## Risks

- **Gate loop:** the deny is recorded before it is emitted and never repeats in a plan cycle; a
  double registration (plugin + settings) sees `gate_denied` on the second copy.
- **Plan mode is read-only:** `report --no-docs` + `publish` after approval; the gate reads
  `.dejavu/checks/<slug>.json`, never `docs/`.
- **Two sessions in one project** can cross-adopt `current.json`; documented, 2 h window.
- **Source drift** (PyPI HTML, WebSearch shape): fixtures cannot catch it; `bench/live.sh endpoints`
  runs before every release; `query` never crashes, it logs an error row.
- **Model-invocable skill** means the model could run it unasked; the description scopes it to
  "when the user asks or agrees to the offer" and the offer line says to ask first.

## Verification

1. `bash dejavu/tests/run.sh` → `passed N failed 0`.
2. `bash dejavu/bench/live.sh endpoints` → every source ≥1 row, no non-rate-limit errors.
3. `claude --plugin-dir ./dejavu` in `playground2`, enter plan mode, "add a rate limiter": the
   model asks whether to run `/dejavu`; decline → skip recorded, ExitPlanMode passes; accept →
   `/dejavu quick …` writes the report with a search log, ExitPlanMode passes, `publish` lands it in
   `docs/dejavu/`.
4. New session: SessionStart prints the reports-on-file line; `recheck <slug>` prints only rows
   newer than the report date.
5. Version present in `plugin.json`, `SKILL.md`, `marketplace.json`; `claude plugin validate`
   passes; the skill run on itself produces the RESEARCH.md report.
