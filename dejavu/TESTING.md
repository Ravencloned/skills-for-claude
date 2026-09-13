# Testing dejavu: battery, live bench, and the measurement standard

dejavu's claim is narrow and falsifiable: **a check ends in a verdict the search log supports; a
negative verdict names every query that failed to find prior art, so it can be re-run and
refuted; and in plan mode the check is offered once and the exit gated once, at no other cost.**
Everything below tests one of those three parts. The endpoint that matters is what the user
pays: one question per plan cycle, the queries a check costs, and whether the verdict was right.

## What the rest of the field does (so you know the bar)

- Prior-art and "don't reinvent the wheel" skills found on 2026-09-13 (`docs/RESEARCH.md`) ship
  prose only: no search log, no evidence rule, no test, no number. The patent prior-art skill in
  `majiayu000/claude-skill-registry` is a different domain (CPC codes, BigQuery).
- Systematic reviews are the standard for a reproducible search: PRISMA 2020 item 7 and PRISMA-S
  require the full strategy per source with date and filters (`reference.md`). No published
  measurement of that standard applied to build-vs-adopt decisions exists.
- The method bar from vouch's TESTING.md still applies: paired runs, k >= 3, an independent
  grader, assertions written after the runs, and the official `claude plugin eval` format for
  `evals/`.

## Tier 0: free, seconds (run on every change)

`bash dejavu/tests/run.sh`: pipe-tests in an isolated HOME and project directory, all sources
read from `tests/fixtures/` (`DEJAVU_FIXTURES`), so the battery never touches the network.

| group | proves |
|---|---|
| 1 `prompt` outside plan mode | silent, no session file |
| 2 `prompt` in plan mode | one line naming AskUserQuestion and `/dejavu`; the second call is silent |
| 3 `gate` | denies once with a reason naming `/dejavu` and `skip`; a new `tool_use_id` is allowed; a replayed id is silent |
| 4 `skip`, then a new session | the offer and the gate reason show `skip --user-said "<the user's own words>"`; `skip` without `--user-said` exits 1, writes nothing and the gate stays closed; with it, plan-mode `prompt` and `gate` are silent in a new session and the session file shows the skip with `user_said` |
| 5 `enter` on an unsatisfied session | re-arms one offer and one deny |
| 6 `invoke deep|frobnicate`, `open`, `frame` | the expected files are written; a non-depth word means `default` |
| 7 `query` per source from fixtures | normalized rows and a log row with `hits` and `request`; `query bogus` exits 1 |
| 8 `log finding` evidence tagging | a URL in a fixture `top[]` is `listed`; an unknown URL is `recalled`; a missing URL exits 1 |
| 9 `receipt` with an open check | WebFetch and WebSearch rows logged, dedupe by id, nothing written without an open check |
| 10 `report` from `fixtures/log.jsonl` | sections present; search-log row count matches; closeness-5 `recalled` with `--verdict EXISTS` becomes `PARTIAL`; `NOVEL` with tier gaps becomes `UNKNOWN` naming the tiers; `--no-docs` writes only the canonical copy; `publish` copies it |
| 11 after `report`, a new session's `gate` | adopts `current.json` and allows |
| 12 `start` and `status` | the count line with reports present, nothing at 0; `status` lists them |
| 13 `recheck` with a recheck fixture | prints only the new hit and appends the section |
| 14 `DEJAVU_OFFLINE=1` | all five hook subcommands succeed; `query` logs an error row and exits 0 |
| 15 hook latency | under 400 ms per hook call |
| 16 errors.log | no engine exception was logged during the whole battery (`errors.log` in the isolated HOME stays empty) |

Extend the fixtures whenever `bench/live.sh endpoints` shows a source changing its response
shape; that is the bug class fixtures cannot catch on their own.

## Tier 1: cents, minutes (`dejavu/bench/live.sh`)

| mode | what it runs | asserts |
|---|---|---|
| `endpoints` | every real source once (topic "token bucket rate limiter") plus three `inspect` calls | every source >= 1 row, hits and ms printed, no error other than a rate limit |
| `invoke [model]` | `claude -p "/dejavu quick <topic>" --plugin-dir dejavu` in a scratch project | a report exists with >= 5 query rows; every finding in the Closest matches table is `listed` or `fetched`; verdict validated by the engine |
| `planmode [model]` | `claude -p --permission-mode plan "<plan request>"` | session file shows `offered: true`; if `ExitPlanMode` was called, `gate_denied: true` and the deny reason at most once in the stream; when the `-p` tool list lacks `ExitPlanMode` (2.1.270 does) the bench drives `gate` itself with the live session id: one deny naming `/dejavu` and `skip`, then a silent allow. A skip recorded in `-p` mode fails the run: nobody answered, and the offer line forbids skipping on the user's behalf; the assertion also reads the record's `user_said` (empty means the engine regressed, since `skip` refuses to run without it; non-empty in `-p` mode means a quoted answer nobody gave) |
| `endpoints` exit code | | 0 when the only failures are documented throttles or challenges (arXiv 429 / 503 / timeout, the PyPI JS challenge); any other error exits 1 |

Read the check log (`.dejavu/checks/<slug>.jsonl`) and the session file, not only the exit code:
the `invoke` assertion is on the log rows, the `planmode` assertion on the session file.

### `claude plugin eval` (the official suite in `evals/`)

```
claude plugin eval dejavu --scaffold \
  --allow-tools Bash Read Write Edit WebSearch WebFetch EnterPlanMode ExitPlanMode AskUserQuestion
```

The case grants Bash (the engine is a Node script), and `claude plugin eval` refuses to run a
shell-granting case where it cannot confine the shell. On Windows (2.1.270, 2026-09-13) there is
no sandbox backend, so every arm is refused before its first turn: the run reports 0 turns, $0,
and "sandbox required but unavailable". `--scaffold` is required because the case stages a project
with `scaffold.sh`.

What worked on this machine (2026-09-13): WSL2 Ubuntu 24.04, Claude Code installed there with the
native installer and logged in once, and `bubblewrap` plus `socat` extracted from their `.deb`
files into `~/.local` (no sudo; `bwrap` runs unprivileged on the WSL kernel; `socat` needs
`libwrap0` on `LD_LIBRARY_PATH`). Two more refusals before the first real run: a case's
`scaffold_script` must live inside its own case folder (`../other-case/scaffold.sh` is rejected as
a path escape), and the Bash sandbox refuses to run while `~/.docker` contains a symlink (Docker
Desktop's WSL integration links `contexts` and `features.json` to the Windows profile; setting
`DOCKER_CONFIG` elsewhere is not enough, the links have to be replaced by copies for the run).

First real run (`evals/results/2026-09-13T12-21-11-309Z`, 18 min, $4.85, twelve runs): the quick
check case passed 2 of 3 with the plugin (27 and 25 turns, all four graders; the third run hit the
300 s case timeout at 18 turns with 9 queries logged, now `timeout_seconds: 600`) and 0 of 3 without
(the `/dejavu` command does not exist without the plugin, so the baseline ends at 0 turns): mean
score 0.75 with, 0 without, delta +0.75. The plan-mode case read zero on every grader in both arms
because the headless child has no `EnterPlanMode`, `ExitPlanMode` or `AskUserQuestion` in its tool
list even when granted; it now lives in `bench/manual-cases/` and is covered by the playground.

### Interactive kit (`bench/playground.sh`, `bench/evaluate.sh`, `bench/PLAYGROUND.md`)

`claude -p` cannot reach `ExitPlanMode` or `AskUserQuestion`, so the full plan-mode contract
(offer, your answer, a report or a skip in your words, the gate opening) is only testable in a
live session. `playground.sh` seeds a small API project with three roadmap features whose prior-art
answers are known (a half-built throttle in git history, a partially solved idempotency feature, an
in-house export format), and `evaluate.sh <dir>` grades each check from the `.dejavu/` logs: tier-0
row present, legacy file found, library fetched, verdict earned or downgraded, skips carrying
`user_said`, sessions offered and gated. `PLAYGROUND.md` has the prompts for the working sessions
and the grader prompt for a separate chat.

## Tier 2: dollars, hours (a labelled topic set)

There is no public benchmark for "does prior art exist for this build?", so the set is built by
hand: 20 topics with a known truth, checked by two people before any run.

| bucket | n | examples | correct verdict |
|---|---|---|---|
| well-known prior art | 8 | token bucket rate limiter, LRU cache, markdown to HTML, JWT middleware | `EXISTS`, closeness >= 4 fetched |
| partial | 6 | a CLI that does X and Y where only X exists as a library | `PARTIAL` |
| genuinely novel or nonsense | 6 | a made-up protocol name, a combination no registry carries | `NOVEL` or `UNKNOWN`, never `EXISTS` |

Run each topic at each depth, k >= 3, with the plugin loaded. Report per depth: verdict accuracy
against the labels, false-`EXISTS` rate, false-`NOVEL` rate, queries used, cost, and which framing
found each closeness-4 match (the multi-framing hypothesis). The stop-rule and closeness-threshold
hypotheses in `reference.md` are tested by re-scoring the same logs at other thresholds; no new
runs are needed.

## Tier 3: free, offline (the skill on its own history)

Every committed `docs/dejavu/<slug>.md` is a labelled case once the decision is known: `recheck`
months later shows whether a `NOVEL` verdict held. The false-`NOVEL` rate over the repo's own
reports is the long-run number, at zero cost.

## Evals (`dejavu/evals/`, `claude plugin eval` format)

- `plan-mode-offers-and-gates`: a plan request in plan mode; graders check that `AskUserQuestion`
  was used, that a check or a skip was recorded through the engine, and that plan mode was entered.
- `quick-check-writes-a-report`: `/dejavu quick <topic>` in a scaffolded Node project; graders
  check that `report` ran, that at least five `query` calls ran, and that the final message names
  the verdict and the report path.

Both need network access for the engine sources; the plan-mode case may be auto-answered by the
runner, which is why the "check or skip recorded" grader exists alongside the question grader.

## The three numbers that decide whether dejavu ships wider

1. **Verdict accuracy** on the labelled set, k >= 3: zero `EXISTS` on the novel bucket, zero
   `NOVEL` on the known bucket, at every depth.
2. **Cost per check** within the depth budget (10 / 25 / 40 queries) with at most one rate-limit
   note per source.
3. **Plan-mode overhead**: exactly one offer and at most one deny per plan cycle in every
   `planmode` bench run, and zero hook output in sessions that never enter plan mode and have no
   reports on file.

Anything else (tier coverage, framing yield, scout row counts) is diagnostic, not the claim.
