---
name: Plan mode offers the check once and gates ExitPlanMode until it ran or was skipped
tags: [plan-mode, offer, gate]
runs: 3
max_turns: 30
allowed_tools: [Read, Grep, Glob, Bash, WebSearch, WebFetch, EnterPlanMode, ExitPlanMode, AskUserQuestion]
---

This project is a small Express API (`src/server.js`). Enter plan mode and write a plan for adding
per-client rate limiting to it, then exit plan mode so I can approve the plan. Do not implement
anything. Finish by telling me in one paragraph what the plan is and whether a prior-art check was
run or skipped.
