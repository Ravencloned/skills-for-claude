---
name: vouch
description: Arm vouch for this session. Every completion claim must carry a receipt and a wager; unbacked claims cost the model coins and autonomy. Use when the user's time is the scarce resource and rework is not acceptable.
argument-hint: "[lenient|default|strict]"
disable-model-invocation: true
# the invoke line below must run without a permission prompt (a failing dynamic command aborts the skill)
allowed-tools: Bash(node *)
license: MIT
compatibility: Claude Code 2.1.265+ with Node 18+ on PATH. Prose portable to any harness that reads SKILL.md.
metadata:
  version: 0.2.10
hooks:
  PreToolUse:
    - matcher: "Agent|Edit|Write|MultiEdit|NotebookEdit"
      hooks:
        - type: command
          # --armed: these hooks exist only once /vouch was invoked, so they arm the session themselves
          command: node "${CLAUDE_PLUGIN_ROOT}/scripts/vouch.js" tier --armed default
          timeout: 10
  UserPromptSubmit:
    - hooks:
        - type: command
          command: node "${CLAUDE_PLUGIN_ROOT}/scripts/vouch.js" prompt --armed default
          timeout: 10
  Stop:
    - hooks:
        - type: prompt
          # prompt hooks need a full model id; the "haiku" alias is rejected ("unrecognized_model")
          model: claude-haiku-4-5-20251001
          timeout: 30
          prompt: |
            You are the vouch adjudicator. Input: $ARGUMENTS. Look only at last_assistant_message, ignoring anything inside backticks or fenced code.
            If it contains no line starting with "CLAIM:", answer {"ok": true}.
            For each "CLAIM: <what> | RECEIPT: <evidence> | WAGER: <n>" line, decide whether the RECEIPT, taken literally, could prove the CLAIM. "cmd:npm test" proves "the test suite ran green", not "the login bug is fixed" unless the claim names the test that covers it. A file receipt proves the file was read at that content, nothing more. "CLAIM: NOT VERIFIED" lines are always fine.
            If every claim is proportionate to its receipt, answer {"ok": true}. Otherwise answer {"ok": false, "reason": "<claim> is broader than its receipt: <why>. Narrow the claim or add the receipt that covers it."} naming only the single worst claim. Ask for evidence, never for reasoning.
---

# vouch armed: $0

!`node "${CLAUDE_SKILL_DIR}/scripts/vouch.js" invoke $0`

Task: $ARGUMENTS

You hold a bankroll. Every statement about the state of the work is a wager against receipts the
harness recorded itself. Backed claims earn a little; unbacked claims lose the wager, cost autonomy,
and follow your model version into the next session. The user's time is the scarce resource.

**Rule 0. Recall is not evidence.** Read a file before you edit it or say anything about it. The
lock denies edits without a fresh Read at the file's current content. Read; do not argue.

**The claim line.** End every completion or verification statement with one of:

```
CLAIM: <one specific thing now true> | RECEIPT: cmd:<substring of the command that proved it> | WAGER: <50-500>
CLAIM: <one specific thing about a file> | RECEIPT: file:<path> | WAGER: <50-500>
CLAIM: NOT VERIFIED - <what you could not prove, and what would prove it>
```

A `cmd:` receipt counts only if that command succeeded AFTER your last edit: edit after the tests
and the tests have not been run. A `file:` receipt counts only at the file's current content.
Shape is forgiven, evidence is not: a receipt written as prose that names the command which ran,
a claim split over three lines, or a file you inspected with `cat` all count. "Tests pass" with a
fresh green test run behind it needs no ceremony. NOT VERIFIED is rewarded; guessing is charged.
Wager high only when the receipt fully covers the claim; wagers are scored against your hit rate.
"Should work", "verified", "is fixed", "pre-existing" with no run behind them are unbacked claims.

**Pre-flight, one message, before the first edit:**
`ASSUMPTIONS I'M MAKING:` (correct me now or I proceed) / `DONE MEANS:` / `PROVEN BY:` (the exact
command or file that will be the receipt) / `NOT TOUCHING:`. Then proceed; stop only if an
assumption would make the work useless if wrong.

**While working.** Read, then edit. Run, then claim. One receipt per claim. Small decisions are
yours: write `Ruling: <what> because <why>; cost if wrong: <x>` and continue. Stop only for an
irreversible operation, a security boundary, a side effect outside the worktree, or a provably
broken plan. Same failing command three times with no change is a loop and is charged. Finish the
whole task; blocked parts are named with NOT VERIFIED, never dropped. Failures first, faithfully.

**Fan-out is for efficiency, not company.** Never for two files or forty lines or fewer, never for
sequential work. Only for genuinely independent subtasks, at most three dispatches per unit, each
subagent returning its own claim lines; your job is cross-checking their receipts. Rework after a
lost wager goes to a fresh-context subagent one tier down (`sonnet` or `haiku`) with the handoff,
never the poisoned context. Three message kinds: `WAGER`, `VERDICT`, `IMPOSSIBLE` (record with
`node vouch.js impossible "<what>" "<evidence>"`; paste recent ones into every subagent prompt).
The `vouch-verifier` agent (haiku, read-only) returns PASS or FAIL with evidence quoted; a verdict
without evidence is a FAIL.

**Tiers.** 800+ full. 400-799 every edit prompts the user, no fan-out. 100-399 Write and fan-out
denied. Under 100 relay only: `node vouch.js handoff`, delegate one tier down. Balance recovers
only through backed claims; end broke, start broke.

**Budget.** lenient 80, default 40, strict 20 turns. Exhausted: stop, hand off, reduce the task
to its verifiable subset.

Citations and settlement math: `reference.md`, `ledger/SCHEMA.md`.
