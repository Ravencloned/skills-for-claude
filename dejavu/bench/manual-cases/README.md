# Manual cases

Eval cases in the `claude plugin eval` format that the headless runner cannot exercise. They are
kept out of `evals/` so the automatic suite does not carry a case that is guaranteed red.

## plan-mode-offers-and-gates

Tests the plan-mode contract: the offer is made once, a skip needs the user's own words, and
`ExitPlanMode` is denied once until a report or a skip exists. Under `claude plugin eval` (2.1.270,
2026-09-13) the child session's tool list has no `EnterPlanMode`, `ExitPlanMode` or
`AskUserQuestion` even when they are granted with `--allow-tools`; the model says so and writes the
plan inline, so all three graders read zero in both arms (6 of 6 runs on 2026-09-13; eval output
stays local, `*/evals/results/` is gitignored).

Run it by hand instead: `bench/playground.sh`, then Session 1 and Session 2 of `bench/PLAYGROUND.md`,
then `bench/evaluate.sh <playground-dir>`. The graders here are `tool_used` and `regex` checks that
cannot see exit codes or files; `evaluate.sh` section 2 (a skip must carry `user_said`) and its
session checks (offered once, gated once) are the authoritative grade. Move the folder back under
`evals/` when a Claude Code release exposes plan-mode tools to headless children.
