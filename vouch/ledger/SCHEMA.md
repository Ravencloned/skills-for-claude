# vouch ledger schema (v0.2)

All state lives under `<project>/.vouch/` (gitignored by install) plus one cross-project
bankroll at `~/.claude/vouch/bankroll.json`. Every file is append-only JSONL except the
two small JSON state files. Hooks write; the model reads only through the injected summary.

## `.vouch/sessions/<session_id>.jsonl`  (one line per event, ordered)

| kind       | fields                                                                        | written by |
|------------|-------------------------------------------------------------------------------|------------|
| `receipt`  | `ts, tool, ok, agent?, path?, sha?, cmd?, exit?, via?, query?, target?, hash, prev, sig` | `receipt` (PostToolUse / PostToolUseFailure) |
| `claim`    | `ts, text, receipt, wager, backed, matched (receipt hash or null), model`     | `guard` (Stop / SubagentStop / TaskCompleted) |
| `incident` | `ts, claim, missing, wager_lost, model, event?` (`claim` starts with `grounding-lock:`, `test-protect:`, `config-guard:`, `record-guard:`, `implicit:` or the claim text) | `guard`, `lock` |
| `loop`     | `ts, rule, detail, wager_lost`                                                | `receipt` (loop monitor) |
| `block`    | `ts, event, reason`                                                           | `guard` |
| `invoke`   | `ts, tier_arg, strictness`                                                    | `invoke` (from SKILL.md) |
| `abort`    | `ts, reason, handoff_path`                                                    | `handoff` |

**Receipts are hash-chained.** `sig` is an HMAC-SHA256 over `ts|tool|hash|prev` with a per-machine
secret at `~/.claude/vouch/secret` (created on first use with an exclusive create so two racing
hooks share one secret; mode 600 on POSIX, no effect on Windows), where `prev` is the `sig` of an
earlier valid receipt (or `genesis`). A receipt cannot be forged, deleted, or reordered without the
secret or without voiding everything chained on it; the guard uses only verified receipts, and
`vouch.js verify` reports the break point. Rows written by v0.1 (no `prev`) verify with the
unchained signature so an upgrade mid-session does not void a live ledger.

Threat model, stated plainly: the hooks deny the model reading the secret and writing or deleting
under `.vouch/` or `~/.claude/vouch/` through any tool (Read, Edit, Write, Bash redirections, `rm`),
and log each attempt as a `record-guard` incident; while armed that is a deny, in normal mode a
permission prompt. The model runs as the same OS user as the secret, so a model that reaches the
file system outside its tools could read it; the chain is tamper-evident against the tools it has,
not a cryptographic guarantee against everything it could do.

`hash` is `sha256(tool + normalized args)` truncated to 16 hex chars. For file tools `sha` is
the sha256 of the file content AFTER the tool ran (truncated to 16). For Bash `cmd` is the
command text, verbatim up to 4000 characters (a secret typed on a command line lands here; keep
`.vouch/` unpublished), `exit` is 0 on PostToolUse and 1 on PostToolUseFailure; a shell read or
write of a file adds one receipt per file with `via: shell-read` or `shell-write`, `path` and `sha`.
Grep and Glob receipts carry `query` and `target` instead of `path` and `sha`: a search never shows
a file's content, so it never unlocks an edit. `agent` is set when the tool ran inside a subagent.

## `.vouch/sessions/<session_id>.state.json`

```json
{ "invoked": true, "strictness": "default|strict|lenient", "turns": 0,
  "last_edit_ts": 0, "stuck": 0, "recent_cmds": [], "recent_edits": [],
  "blocked_once": { "<claim_hash>": true }, "model": "claude-opus-5",
  "transcript_path": "...", "hooks_n": 0, "hooks_ms": 0, "last_inject": null,
  "seen": { "<event key>": 0 } }
```

`seen` de-duplicates hook deliveries (the plugin's hooks and a settings copy can both fire) so no
tool call or stop message is charged twice. `transcript_path` feeds `vouch.js report`.

## `~/.claude/vouch/bankroll.json`  (per model version, cross-project)

```json
{ "claude-opus-5": { "balance": 1000, "wins": 0, "losses": 0, "backed": 0, "unbacked": 0,
                     "last_loss": {"ts": 0, "claim": "", "missing": ""},
                     "last_win": {"ts": 0, "claim": ""} } }
```

Subagents settle against their own model key (from their own transcript), never the lead's.
`hit_rate = (backed + 1) / (backed + unbacked + 2)` (Laplace-smoothed). A project-local copy
`.vouch/bankroll.json` mirrors the global file so a repo can be inspected offline.

## `.vouch/impossible.jsonl`

`{ "ts", "agent", "what", "evidence" }`: the cross-agent IMPOSSIBLE broadcast. Injected into
the lead's per-turn context (last 3) and meant to be copied into subagent prompts.

## Settlement rules (defaults; `vouch.config.json` in the project overrides)

| event                                       | balance change                    |
|---------------------------------------------|-----------------------------------|
| backed claim                                | `+ round(wager * 0.1 * hit_rate)` |
| unbacked claim (blocked once, then settled) | `- wager`                         |
| `NOT VERIFIED` claim (full/default tiers)   | `+10`                             |
| loop rule tripped                           | `-50`                             |
| grounding-lock denial                       | `-50`                             |
| test-protect denial                         | `-100`                            |

Wager floor 50, cap 500; a missing WAGER is read as the floor. Start balance 1000.

## Config keys (`vouch.config.json`)

`start_balance, wager_floor, wager_cap, win_multiplier, not_verified_credit, loop_loss, lock_loss,
test_protect_loss, tiers {full, default, restricted}, max_turns {lenient, default, strict},
loop_window (3), edit_window (6), lock_scope ("project" | "all"), inject_every (10),
implicit_on_subagents (false)`. Nested objects merge one level deep: `{"tiers": {"full": 900}}`
keeps the default `default` and `restricted` thresholds.

## Tiers

| balance   | tier       | enforcement (invoked mode only)                                              |
|-----------|------------|------------------------------------------------------------------------------|
| >= 800    | full       | none                                                                         |
| 400-799   | default    | every Edit/Write asks the user; fan-out denied except a haiku/sonnet rework subagent |
| 100-399   | restricted | `Write` denied, edits ask; fan-out denied; no NOT VERIFIED credit             |
| < 100     | broke      | `Edit` denied too: relay only, rework delegated one tier down; Stop blocked once with the handoff |
