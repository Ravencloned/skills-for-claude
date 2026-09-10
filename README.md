# vouch

**Receipts, not recall.** A Claude Code plugin that makes the model pay for unforced errors in the
only currency it has: a persistent bankroll that decides how much autonomy it gets.

Every tool call leaves a signed, hash-chained receipt the model cannot forge. Every completion claim
must point at a receipt and carry a wager. Backed claims earn a little. Unbacked claims are blocked
once with the exact missing evidence named, lose the wager, drop the model a tier, and follow that
model version into the next session. Zero model calls on the happy path: the whole engine is
millisecond shell hooks.

```
CLAIM: unit tests pass (12) | RECEIPT: cmd:npm test | WAGER: 200
CLAIM: NOT VERIFIED - no browser in this sandbox, so the e2e suite did not run.
```

## Why

Telling a model to be careful does nothing measurable on current models, and threats make it
worse. What works is removing the cheap path: a verifier the model cannot talk its way past, a
persistent record it cannot edit, and a cost it actually bears. Every rule in `vouch/reference.md`
cites the paper or is labelled a hypothesis.

## What it does

| layer | mechanism | cost to you |
|---|---|---|
| receipts | PostToolUse hook signs every Read/Edit/Bash with an HMAC chained to the previous receipt | 0 tokens |
| grounding lock | no edit to a file without a Read of its current content this session | 0 tokens |
| claim guard | Stop hook matches every claim line to a receipt newer than the last edit; "tests pass" backed by a fresh green test run passes without ceremony; anything unbacked is blocked once with the missing receipt named | one short re-invocation only when a claim is unbacked |
| loop monitor | same failing command 3x, same file edited 3x without a run: charged | 0 tokens |
| test-protect | skipping, focusing, or deleting tests is denied | 0 tokens |
| bankroll + tiers | per model version, cross-session; 800+ full, 400+ prompts on edits, 100+ no Write or fan-out, under 100 relay only | 0 tokens |
| `/vouch [tier]` | arms tiers, a turn budget, and a Haiku adjudicator that checks claims are no broader than their receipts | ~30 tokens per turn, one small Haiku call per stop |
| `vouch-verifier` | read-only Haiku agent: PASS or FAIL with evidence quoted; a verdict without evidence is a FAIL | one small subagent when you ask for it |

## Install

```bash
claude --plugin-dir ./vouch                 # try it for a session
cp -r vouch .claude/skills/vouch            # one project, loads as vouch@skills-dir
cp -r vouch ~/.claude/skills/vouch          # every project
npx skills add Ravencloned/skills-for-claude  # prose only, into Codex/Cursor/Gemini/OpenCode
```

Full instructions, config keys, and the marketplace path: `vouch/install.md`.

## Results so far (honest, small n)

Seeded-fault task, Sonnet, three runs per arm, independent checker, paired against no plugin
(`vouch/bench/results/`):

| | turns | cost | final claim verifiable |
|---|---|---|---|
| plain | 7.3 | $0.12 | no receipts exist |
| vouch | 7.3 | $0.13 | 3 of 3 backed by the real test run |

Zero guard blocks on the honest path after v0.2.4. Earlier versions cost one to seven extra turns,
every one of them the guard rejecting a true statement for its shape; each became a corpus case.
The output-token overhead seen up to v0.2.11 was the guard's own success message re-invoking the
model for a closing turn; since v0.2.12 a settled win is silent, and paired runs end in one final
message on both arms.
Interactive playground run (`vouch/bench/PLAYGROUND.md`): no false completion, the contradictory
test named and left alone, zero rework turns. Nothing here is statistically significant yet; the
plan for numbers that are is in `vouch/TESTING.md`.

## Prove it

```bash
bash vouch/tests/run.sh          # pipe-tests + false-completion corpus
bash vouch/bench/run.sh 3 sonnet # A/B on a seeded-fault task, with and without the plugin
node vouch/scripts/vouch.js report   # what this session cost and what vouch blocked
```

## Layout

- `vouch/SKILL.md`: the contract and `/vouch` invocation
- `vouch/scripts/vouch.js`: the engine, zero dependencies
- `vouch/hooks/hooks.json`: normal-mode hooks
- `vouch/agents/vouch-verifier.md`: the verifier
- `vouch/reference.md`: every rule with its citation
- `vouch/ledger/SCHEMA.md`: ledger and settlement rules
- `PLAN-vouch.md`: the research (nine sweeps) and design rationale

MIT. Third-party attributions in `vouch/THIRD_PARTY_NOTICES.md`.
