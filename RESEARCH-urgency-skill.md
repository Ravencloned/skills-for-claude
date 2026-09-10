# Urgency skill: research notes (2026-09-09)

Idea: an invocable skill ("urgency + value of the user's time") that makes the model treat the
session as high-stakes, avoid unforced errors, verify before claiming done, finish the whole task,
and that carries a USER-DEFINED real-time consequence ladder (strikes -> escalation -> block)
enforced by harness hooks.

## Verdict on prior art
Nobody found has built the combination (invocable skill + user-defined consequence ladder enforced
by hooks). Pieces exist separately. Code-search probes for `stop_hook_active` + `strike` returned
zero hits. Caveat: GitHub code search indexes default branches only; a few queries were rate-limited.

## Closest matches
| Repo | What | Close (1-5) | Reusable |
|---|---|---|---|
| obra/superpowers verification-before-completion (MIT) | "Iron Law": no completion claims without fresh verification evidence | 3 | checklist, rationalization table |
| Swader/skill-be-thorough | user-invoked "be thorough": mission contract, scope tripwires, requirement ledger, "done is a verified state not a feeling" | 3 | invocation pattern, final gate |
| VoDaiLocz/kilo-kit-mcp | MCP sentinel: grounding lock, circuit breaker after 3 identical loops, low-confidence escalator | 3 | only mechanical strike-like device found; author-fixed thresholds |
| bradmcnew/yolo-agent-template AGENTS.md | "Three Strikes Rule" prose | 2 | wording |
| anthropics/claude-code plugins/ralph-wiggum (commercial terms, NOT reusable) | Stop hook loop, --max-iterations, blocks exit | 2 | pattern only, re-implement |
| karanb192/claude-code-hooks (MIT) | dead-end-registry, nerf-receipts (failure-rate ledger), protect-tests, config-guard | 2 | rework accounting, anti-fake-green |
| AlethiaQuizForge/claude-guard-hooks (MIT, new) | verify-tracker ledger + Stop verify-guard that blocks "verified/tests pass" claims with empty ledger; proof-guard; claim-guard | 3 (mechanically) | strike/ledger skeleton |
| sadovsky/make-no-mistakes | hook appends "Make no mistakes." (satire) | 1 | shows the naive form already exists as a joke |

## Research on threats/stakes wording
- EmotionPrompt (Li 2023, arXiv:2307.11760) and NegativePrompt (Wang 2024, arXiv:2405.02814): gains on OLD models.
- Bsharat 2023 (arXiv:2312.16171) "you will be penalized": ~45% on GPT-4, weak baselines, treat as uncertain.
- Wharton Prompting Science Report 3 (Meincke/Mollick 2025, arXiv:2508.00614): threats + tips on current
  models -> NO aggregate effect, per-question swings +36/-35, unpredictable. Recommendation: clear instructions.
- Patel 2026 (arXiv:2604.07369): positive emotional stimuli raise accuracy but INCREASE sycophancy.
CONCLUSION: the wording is not the lever. Mechanical gates (hooks) and concrete verification steps are.

## Mergeable skills by bucket (all opened, licenses checked)
A Verification: superpowers verification-before-completion (merge verbatim); everything-claude-code
  verification-loop (steal report format); addyosmani agent-skills definition-of-done (adapt).
B Debugging: superpowers systematic-debugging ("3 failed fixes = stop, question architecture") merge;
  addyosmani debugging-and-error-recovery stop-the-line + non-repro tree (adapt).
C Pre-flight: addyosmani using-agent-skills "ASSUMPTIONS I'M MAKING" block (merge verbatim);
  superpowers brainstorming classification (adapt, drop approval gate); ECC gateguard PreToolUse
  deny-first-edit-until-context-listed (optional hook).
D Finish the task: superpowers subagent-driven-development "Rulings, not stalls" + four stop conditions
  (merge verbatim); ralph pattern re-implemented; frankbria/ralph-claude-code circuit breaker thresholds
  (3 no-progress / 5 same-error) as strike defaults.
E Self-review: addyosmani doubt-driven-development CLAIM/EXTRACT/DOUBT/RECONCILE/STOP max 3 (adapt);
  superpowers requesting/receiving-code-review (adapt, forbids "You're absolutely right!").
F Token/time economy: drona23/claude-token-efficient six lines (merge verbatim); o4f6bgpac3/concise
  output rules (adapt); karanb192 dead-end-registry (optional hook).
G Consequence hooks: claude-guard-hooks verify-tracker/verify-guard/proof-guard/claim-guard (merge,
  add strike counter); ECC delivery-gate rationalization regex list (adapt); karanb192 protect-tests +
  config-guard (adapt: agent must not edit its own hooks).
H Honesty: superpowers receiving-code-review + addyosmani "Push Back When Warranted" (merge);
  agentic-awesome-skills anti-sycophancy 4-step (adapt); frank has lite/full/ultra intensity levels (idea).
I Portability: agentskills.io spec (Apache-2.0) frontmatter name/description/license/compatibility/
  metadata/allowed-tools, <500 lines; vercel-labs/skills `npx skills add` installs to 79 agents;
  agentsmd/agents.md companion; superpowers SessionStart shim branching on CURSOR_PLUGIN_ROOT.

Already multi-bucket: superpowers (A-E,H, no enforcement); addyosmani using-agent-skills (closest single
file to the concept); everything-claude-code (A,G,F,D); claude-guard-hooks (A,G,H mechanically).

## Licenses
MIT: superpowers, addyosmani, everything-claude-code, claude-guard-hooks, karanb192, ralph-claude-code,
token-efficient, concise, vercel skills, agents.md. Apache-2.0: agentskills spec, anthropics/skills.
NOT reusable: anthropics/claude-code plugins (commercial terms), fable-mode and hooks-mastery (no license).
Keep THIRD_PARTY_NOTICES with per-file attribution.

## Avoid
Continuous-Claude-v3 (too heavy), prompt-rewriting hooks that alter user input, caveman-style token
compressors, prompt-type Stop hooks that ask the model "are you done?" (self-report always says yes;
use ledger evidence).

## Claude Code skill conventions (official docs)
<name>/SKILL.md + optional reference.md, examples.md, scripts/. Frontmatter: name, description;
optional disable-model-invocation, user-invocable, allowed-tools, context: fork, arguments/argument-hint,
effort, hooks: (registered on invocation, persist for session), paths, metadata. !`cmd` runs at load
(e.g. read strike-count file). Stop hook blocks via exit 2 or {"decision":"block","reason":...}; guard
with stop_hook_active. UserPromptSubmit injects additionalContext. PreToolUse denies via
permissionDecision "deny". PostToolUseFailure exists for counting failures.
