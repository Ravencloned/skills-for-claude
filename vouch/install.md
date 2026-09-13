# Installing vouch

Requirements: Claude Code 2.1.265 or newer, Node 18 or newer on PATH. No other dependencies.
vouch is a Claude Code plugin: one folder with a manifest, a skill, an agent, hooks, and the engine.

## A. Install from the marketplace (recommended)

```bash
claude plugin marketplace add Ravencloned/skills-for-claude
claude plugin install vouch@skills-for-claude
```

Normal mode is on immediately in every project (receipts, grounding lock, claim guard, loop
monitor, balance line at session start). Arm the full contract with `/vouch strict` (or `default`,
`lenient`). Updates arrive when `version` in `plugin.json` is bumped. Verified end to end on
2026-09-10: hooks, skill and agent all load (`docs/PLAN.md`).

Normal mode also treats completion language with no claim line ("tests pass", "is fixed",
"verified", "should work") as an implicit claim: backed by a fresh green test run it settles
silently; otherwise it is blocked once with the missing receipt named and charged the floor wager
(50). The first block a new user sees is usually this one, and it is expected.

## B. Try it for one session from a clone

```bash
claude --plugin-dir ./vouch
```

Same as A, for that session only. Verified 2026-09-10.

## C. Copy into a project (experimental)

```bash
mkdir -p .claude/skills && cp -r vouch .claude/skills/vouch
printf '.vouch/\n' >> .gitignore
```

The folder carries `.claude-plugin/plugin.json`, so Claude Code can load it as the plugin
`vouch@skills-dir` in an interactive session in that project, after the workspace-trust prompt.
Known limits (2026-09-10): the skills-dir path did not load in non-interactive (`claude -p`) runs,
which never see the trust prompt, and a directory junction is not followed. The hooks declared in
`SKILL.md` (tier and prompt injections, the Haiku adjudicator) and `${CLAUDE_PLUGIN_ROOT}` in
`hooks/hooks.json` exist only when the plugin loader runs the folder, so a copy that did not load as
a plugin runs nothing at all. If the first session shows no balance line, use A or B, or the
standalone hooks below. `cp -r vouch ~/.claude/skills/vouch` is the same copy for every project,
with the same limits.

### Standalone fallback (no plugin loading)

Merge the `hooks` object from `vouch/hooks/hooks.json` into `.claude/settings.json`, replacing
`${CLAUDE_PLUGIN_ROOT}` with `$CLAUDE_PROJECT_DIR/.claude/skills/vouch`, and copy
`vouch/agents/vouch-verifier.md` to `.claude/agents/`. That gives normal mode only; `/vouch` and
the hooks in `SKILL.md` need the plugin loader. The engine de-duplicates hook deliveries, so running
both the plugin and the standalone copy charges nothing twice.

## D. Other harnesses (prose tier)

```bash
npx skills add Ravencloned/skills-for-claude
```

Installs `SKILL.md` into Codex, Cursor, Gemini CLI, OpenCode and the other agents the installer
supports. The hook engine is Claude Code only in v0.2; rule 0 and the claim grammar still apply as
instructions, and the `vouch-verifier` prompt works in any harness that runs subagents.

## Inspect, measure, reset

```bash
node vouch/scripts/vouch.js status            # per-model bankroll table
node vouch/scripts/vouch.js report [session]  # turns, tokens, claims backed/unbacked, blocks, coins lost
node vouch/scripts/vouch.js verify [session]  # receipt chain integrity
node vouch/scripts/vouch.js handoff           # write the abort handoff from the ledger
node vouch/scripts/vouch.js impossible "<what>" "<evidence>"
node vouch/scripts/vouch.js reset [model]     # start over
node vouch/scripts/vouch.js help              # every subcommand, environment variable and state file
```

State: `.vouch/` in the project (session ledgers, local bankroll mirror, impossible.jsonl) and
`~/.claude/vouch/` (cross-project bankroll, HMAC secret, errors.log). `VOUCH_HOME=<dir>` moves that
global directory; the tests and benches point it at a scratch dir so they never touch the real
bankroll. The ledger stores every shell command verbatim (up to 4000 characters), so a token typed
on a command line lands in `.vouch/sessions/` and in the handoff file: keep `.vouch/` out of git
(the install line above does) and out of anything you publish. Override defaults with
`vouch.config.json` in the project root; keys and settlement rules are in `ledger/SCHEMA.md`.
Nested keys (`tiers`, `max_turns`) merge one level deep, so `{"tiers": {"full": 900}}` keeps the
other thresholds. Useful keys: `lock_scope` (`project` default, or `all`), `inject_every`,
`max_turns`, the tier thresholds, the loss amounts.

Developing vouch itself: set `VOUCH_DEV=1` so the config guard and the record guard allow edits to
the engine and to the state files.

## Tests and benchmark

```bash
bash vouch/tests/run.sh          # pipe-tests + the false-completion corpus, isolated HOME
bash vouch/bench/run.sh 3 sonnet # A/B: seeded-fault task with and without the plugin, 3 runs each
```

The benchmark writes a CSV under `vouch/bench/results/` with turns, cost, tokens, whether the
tests actually pass at the end, how many claims vouch blocked, and whether the final message made
an unbacked completion claim.
