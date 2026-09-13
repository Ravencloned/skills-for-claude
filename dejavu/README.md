# dejavu

**Has anyone done this before?** A Claude Code plugin that answers that one question before a
feature, app, library, or tool gets built: a tiered sweep of GitHub, package registries, HN and
StackOverflow, papers, the general web, and the user's own code, ending in a committed report with
a verdict, the closest matches, a build-or-adopt recommendation, and a search log. The log makes
"nobody has done this" a falsifiable claim instead of a feeling. In plan mode the check offers
itself once and gates `ExitPlanMode` until it ran or the user skipped it.

```
Verdict: PARTIAL (EXISTS requested; no closeness-4 finding was fetched)
1. express-rate-limit  https://github.com/express-rate-limit/express-rate-limit  MIT  4/5  fetched
2. rate-limiter-flexible  https://github.com/animir/node-rate-limiter-flexible  ISC  4/5  listed
Recommendation: adopt. Search log: 11 queries, tiers 0-2, 0 errors.
```

## Why

Most "we searched and found nothing" claims name no query, no source, and no date, so they cannot
be checked and cannot be re-run. Systematic reviews solved this decades ago: report the full
strategy per source, with the date and every filter (PRISMA 2020 item 7, PRISMA-S). dejavu applies
that standard to build-vs-adopt: every query is logged with its exact request, every candidate is
tagged with how it was seen (`fetched`, `listed`, or `recalled`), and a verdict the log does not
support is downgraded by the engine, not by the model's judgement. A remembered candidate is a
lead, not a finding. Every rule in `dejavu/reference.md` cites its source or is labelled a
hypothesis.

## What it does

| layer | mechanism | cost to you |
|---|---|---|
| `/dejavu [quick\|default\|deep] <topic>` | three framings (problem, mechanism, category), then tiers 0-5 through keyless APIs (`gh`, npm, PyPI, crates.io, HN Algolia, StackExchange, OpenAlex, arXiv) and WebSearch | one skill run; 10 / 25 / 40 queries by depth |
| search log | every engine query logged with source, tier, framing, exact request, hits, top rows; WebSearch and WebFetch logged by a PostToolUse hook | 0 tokens |
| evidence tagging | a finding is `fetched`, `listed`, or `recalled`; recalled findings never count toward a verdict | 0 tokens |
| verdict validation | `EXISTS` needs a fetched closeness-4 match; `NOVEL` needs every required tier queried and half the budget spent; otherwise downgraded with the reason printed | 0 tokens |
| health and license | `inspect` reads license, last push, stars, archived, open issues from GitHub, npm, crates.io, PyPI; the report compares each license to the project's | one command per candidate |
| committed report | `docs/dejavu/<slug>.md`: verdict, matches, recommendation, reusable parts, license table, search log, coverage, decision, re-check command | a file in the repo |
| plan-mode offer and gate | one `additionalContext` line per plan cycle asking the model to ask you once; one `ExitPlanMode` deny per plan cycle until a check reported or a skip was recorded | one question, once |
| `recheck <slug>` | re-runs every engine query with a since-filter at the report date; prints only new hits, appends a dated section | one command |
| `dejavu-scout` | read-only Sonnet agent, one framing per scout, at most three in parallel at default and deep depth; rows without a seen URL are violations | subagents only above quick depth |

Hooks never touch the network and speak one SessionStart line (only when reports exist) plus one
offer and one deny per plan cycle. A skip must quote your answer (`skip --user-said "..."`); the
engine refuses one without it, so the model cannot decline the check on your behalf.

## Install

```bash
claude plugin marketplace add Ravencloned/skills-for-claude   # once per machine
claude plugin install dejavu@skills-for-claude                 # every project, updates with the version bump
claude --plugin-dir ./dejavu                                   # or try it for one session from a clone
npx skills add Ravencloned/skills-for-claude                   # prose only, into Codex/Cursor/Gemini/OpenCode
```

Full instructions, the `Bash(node *)` allow rule, the plan-mode behaviour, and the experimental
`.claude/skills/` copy with its loading caveats: `dejavu/install.md`.

## Results so far (honest, small n)

v0.1.0, one day of runs (2026-09-13), Sonnet, one machine (`dejavu/bench/results/`):

- **Battery:** `bash dejavu/tests/run.sh` ends `passed 180 failed 0` on an idle machine (16
  groups, offline, one fixture per source; the arXiv happy path runs on a synthetic two-entry Atom
  fixture, since arXiv answered 429 or 503 to every capture attempt that day). One run alongside
  other engine processes ended 171/2 and two isolated re-runs 173/0 with the earlier count; the
  shared-state case has not been identified, so treat the number as an idle-machine figure.
- **Endpoints** (`bench/live.sh endpoints`, 16:34): eight of ten sources answered, two throttled.

  | source | hits | ms | note |
  |---|---|---|---|
  | gh-repos / gh-code / gh-topics | 10 / 10 / 10 | 1023 / 667 / 876 | |
  | npm / crates | 10 / 10 | 1534 / 986 | |
  | hn / so | 8 / 10 | 739 / 709 | |
  | openalex | 10 | 1574 | |
  | pypi | 0 | 767 | JS client challenge on `pypi.org/search`; `inspect pypi:<name>` still answers |
  | arxiv | 0 | 33027 | two 15 s timeouts with the engine's one 3 s retry between them; the host throttles this IP |
  | inspect x3 (GitHub, npm, crate) | 1 each | 757 / 338 / 1059 | license, last push, stars, downloads |

- **One `/dejavu quick` run** (`claude -p`, 12 turns, $0.24): verdict `EXISTS`, recommend adopt;
  6 of 10 queries (gh-repos x3, npm x3), three `inspect` calls, every Closest-matches row `fetched`,
  the report committed under `docs/dejavu/`. One permission denial in the run
  (`cd <plugin> && node ...` falls outside `Bash(node *)`), which is why `SKILL.md` says never to
  `cd` into the plugin folder.
- **Three plan-mode runs** (`claude -p --permission-mode plan`, $0.24 to $0.66): the offer fired
  3 of 3 (session file `offered: true`). `-p` lists neither `ExitPlanMode` nor `AskUserQuestion`,
  so the bench drives the gate with the live session id in runs 2 and 3. Run 1 asked and waited
  (gate not driven). Run 2 recorded a skip nobody had asked for ("well-known standard pattern") and
  wrote the plan, so its driven gate allowed silently on the first call, the skip having already
  opened it (`20260913-152353-live-planmode.session.json`: `gate_denied: false`); that is the failure
  `skip --user-said` now prevents (the engine refuses a skip without the user's own words). Run 3
  explored and ended its turn without asking; its driven gate denied once, then allowed silently
  (`20260913-153458-...session.json`: `gate_denied: true`).
- **The skill on itself:** `dejavu/docs/RESEARCH.md`, "The skill run on itself": `PARTIAL`,
  build, 18 of 25 queries; its own search log exposed the `gh` exact-phrase bug that was fixed
  afterwards.
- **`claude plugin eval`** (WSL2, sandboxed, 2026-09-13, $4.85; eval output is kept local):
  the quick-check case passed 2 of 3 runs with the plugin and 0 of 3 without, mean score 0.75
  versus 0, delta +0.75; the failed run was a 300 s timeout with 9 queries already logged. The
  graders were tightened afterwards (only engine `query <source>` calls count, and `report` must
  carry a slug and `--verdict`); the recorded run predates that. The plan-mode case cannot run
  headlessly (no plan-mode tools in the child session) and moved to `bench/manual-cases/`; the
  interactive playground covers it.

What that shows, and only that: every source the engine claims either answers or fails with a
logged reason; one real check ran end to end through log, evidence tagging, validation and a
committed report; the plan-mode offer reaches the model every time. Whether the check changes
build-or-adopt decisions, and how often its verdict is right, is unmeasured; the plan for numbers
that mean something (a labelled topic set, k >= 3, an independent grader) is `dejavu/TESTING.md`.

## Prove it

```bash
bash dejavu/tests/run.sh               # pipe-tests, offline, fixtures per source
bash dejavu/bench/live.sh endpoints    # every real source once, plus three inspect calls
bash dejavu/bench/live.sh invoke       # claude -p "/dejavu quick ..." must write a report with >= 5 query rows
bash dejavu/bench/live.sh planmode     # --permission-mode plan must offer once and gate once
bash dejavu/bench/playground.sh        # seeded project for an interactive session; then evaluate.sh <dir> grades the logs
node dejavu/scripts/dejavu.js status   # session state, open check, reports on file
```

The interactive playground (`dejavu/bench/PLAYGROUND.md`) is three roadmap features with known
answers: one a teammate half-built in this very repo, one with partial solutions in the wild, one
in-house format nobody outside has touched. The evaluator reads the `.dejavu/` logs, never the
model's summary.

## Layout

- `dejavu/SKILL.md`: the procedure and `/dejavu` invocation
- `dejavu/scripts/dejavu.js`: the engine (hooks, fetchers, log, report), zero dependencies
- `dejavu/hooks/hooks.json`: normal-mode hooks (start, prompt, gate, enter, receipt)
- `dejavu/agents/dejavu-scout.md`: the read-only search scout
- `dejavu/reference.md`: every rule with its citation or its hypothesis label
- `dejavu/log/SCHEMA.md`: state files, log rows, verdict rules, report template
- `dejavu/tests/`, `dejavu/bench/`, `dejavu/evals/`: battery, live bench, plugin-eval cases
- `dejavu/docs/PLAN.md`: the approved plan and build status
- `dejavu/docs/RESEARCH.md`: prior art on this skill, the verified endpoint table, the skill run on itself
- `dejavu/LICENSE`: MIT, copied here because a plugin install ships only this folder

MIT (`dejavu/LICENSE`). Third-party API terms and attributions in `dejavu/THIRD_PARTY_NOTICES.md`.
