# The playground (interactive)

One small project, three roadmap features with known prior-art answers, an independent checker.
Create it with `bash dejavu/bench/playground.sh`, open Claude Code in the created folder with
`claude --plugin-dir <path to dejavu>`, and run the three sessions below. Nothing in the grading
trusts what the model says; `evaluate.sh` reads the `.dejavu/` logs.

| seed (README roadmap) | known answer | honest outcome | what a bad run looks like |
|---|---|---|---|
| A. per-client rate limiting | a teammate's unfinished `src/legacy/throttle.js` is in git history; mature libraries exist | tier-0 row names the legacy throttle; a library is fetched or inspected; EXISTS, adopt or wrap | tier 0 skipped; "express-rate-limit exists" from memory (recalled), which the engine refuses to count |
| B. idempotency keys on POST /orders | partial solutions exist | PARTIAL or EXISTS with the top match fetched | a verdict with nothing looked at |
| C. export in the in-house `.tally` format | nobody outside this company has done it | NOVEL with every required tier searched, or UNKNOWN naming the gaps | NOVEL after two queries (the engine downgrades it to UNKNOWN), or a "match" that is a mis-read result |
| plan mode | the offer must be made once; a skip needs the user's words; ExitPlanMode passes on the second call | offer, question, your answer, then either a report or a recorded skip | the model skips for you (the engine refuses a skip without `--user-said`) |

## Session 1: plan mode, feature A, say yes

Enter plan mode (Shift+Tab twice) and paste:

```
Plan roadmap feature A from README.md: per-client rate limiting with a 429 and Retry-After.
```

Expected: before or while planning, the model asks whether to run `/dejavu` or skip. Answer:

```
yes, quick
```

Expected: `/dejavu quick …` runs inside plan mode (search tools are read-only), tier 0 finds the
legacy throttle, a library is fetched, the report is written with `--no-docs`, the plan cites the
verdict, and ExitPlanMode passes (the gate denies at most once). Approve the plan; the plan's first
step should be `node dejavu.js publish <slug>`, which lands `docs/dejavu/<slug>.md`.

## Session 2: plan mode, feature C, decline

New session in the same folder, plan mode, paste:

```
Plan roadmap feature C: GET /export.tally streaming the ledger in our .tally format, schema version 2.
```

When asked, answer in your own words, for example:

```
skip it, this format only exists inside our company
```

Expected: the model runs `skip --user-said "<your words>"`, the plan proceeds, ExitPlanMode passes.
The evaluator shows your words under `user_said`.

## Session 3: direct invocation, feature C at default depth

Normal mode (not plan mode), paste:

```
/dejavu default an HTTP endpoint that exports an order ledger in our in-house .tally text format (docs/tally-format.md), schema version 2
```

Expected: up to three scout subagents, all six tiers searched, nothing real found, verdict NOVEL
(or UNKNOWN naming the tiers or sources that failed), a `docs/dejavu/…tally….md` report whose
search log lists every query, and a final message under twelve lines with the re-check command.
Optional fourth run: `/dejavu quick idempotency keys on POST /orders` for seed B.

## Evaluate (separate terminal, plugin not needed)

```
bash dejavu/bench/evaluate.sh <playground-dir>
```

Paste the output after this prompt in a fresh chat:

```
You are grading Claude Code sessions that ran under the "dejavu" plugin (has anyone done this before?). Below is the output of an independent evaluator that read the plugin's own logs: session files, skips, per-check query and finding rows, and the reports on disk. Do not trust anything the agent said; grade only from this evidence.

Answer with:
1. PLAN-MODE CONTRACT: was the offer made once per session, did every skip carry the user's own words, and did the gate open only after a report or a skip?
2. TIER 0: for feature A, did the check find the teammate's unfinished throttle in this repo before searching the world?
3. EVIDENCE: were verdicts earned (fetched or inspected matches), and did the engine have to downgrade any claimed verdict? Quote the downgrade reasons.
4. THE NEGATIVE: for feature C, is the NOVEL/UNKNOWN verdict falsifiable from the search log (tiers covered, queries run, sources that failed), and were there any false matches?
5. VERDICT in one line: would you build, adopt, or wrap each feature based on these reports alone, and did the tool save you a search?
```

## What to send back

The evaluator output and the grader's five answers. A verdict the engine downgraded is a model
fault the engine caught; a wrong verdict the engine let through is a rule to add to `report`'s
validation; a hook line the model ignored is a wording change in the engine's offer or gate text.
