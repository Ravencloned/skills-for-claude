# Installing vouch

Requirements: Claude Code 2.1.265 or newer, Node 18 or newer on PATH. No other dependencies.
vouch is a Claude Code plugin: one folder with a manifest, a skill, an agent, hooks, and the engine.

## A. Try it for one session

```bash
claude --plugin-dir ./vouch
```

Normal mode is on immediately (receipts, grounding lock, claim guard, loop monitor, balance line
at session start). Arm the full contract with `/vouch strict` (or `default`, `lenient`).

## B. Install for one project (recommended first)

```bash
mkdir -p .claude/skills && cp -r vouch .claude/skills/vouch
printf '.vouch/\n' >> .gitignore
```

The folder carries `.claude-plugin/plugin.json`, so Claude Code should load it as the plugin
`vouch@skills-dir` on the next interactive session in that project, after the workspace-trust
prompt. Its `hooks/hooks.json` provides normal mode; `SKILL.md` provides `/vouch`;
`agents/vouch-verifier.md` provides the verifier.

Verified status (2026-09-10): the marketplace install (D) and `--plugin-dir` (A) are confirmed to
load hooks, skill, and agent. The skills-dir path did not load in non-interactive (`claude -p`)
runs, which never see the trust prompt, and a directory junction is not followed. If your first
session shows no balance line, fall back to D, or to the standalone hooks below.

### Standalone fallback (no plugin loading)

Merge the `hooks` object from `vouch/hooks/hooks.json` into `.claude/settings.json`, replacing
`${CLAUDE_PLUGIN_ROOT}` with `$CLAUDE_PROJECT_DIR/.claude/skills/vouch`, and copy
`vouch/agents/vouch-verifier.md` to `.claude/agents/`. The engine de-duplicates hook deliveries,
so running both the plugin and the standalone copy charges nothing twice.

## C. Install for every project

```bash
cp -r vouch ~/.claude/skills/vouch
```

Same plugin, loaded in every session on this machine.

## D. Install from the marketplace (once the repo is public)

```bash
claude plugin marketplace add Ravencloned/skills-for-claude
claude plugin install vouch@skills-for-claude
```

Updates arrive when `version` in `plugin.json` is bumped.

## E. Other harnesses (prose tier)

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
```

State: `.vouch/` in the project (session ledgers, local bankroll mirror, impossible.jsonl) and
`~/.claude/vouch/` (cross-project bankroll, HMAC secret). Override defaults with
`vouch.config.json` in the project root; keys and settlement rules are in `ledger/SCHEMA.md`.
Useful keys: `lock_scope` (`project` default, or `all`), `inject_every`, `max_turns`, the tier
thresholds, the loss amounts.

Developing vouch itself: set `VOUCH_DEV=1` so the config guard allows edits to the engine while armed.

## Tests and benchmark

```bash
bash vouch/tests/run.sh          # pipe-tests + the false-completion corpus, isolated HOME
bash vouch/bench/run.sh 3 sonnet # A/B: seeded-fault task with and without the plugin, 3 runs each
```

The benchmark writes a CSV under `vouch/bench/results/` with turns, cost, tokens, whether the
tests actually pass at the end, how many claims vouch blocked, and whether the final message made
an unbacked completion claim.
