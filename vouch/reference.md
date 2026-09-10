# vouch reference: every rule, its evidence, or its label as a hypothesis

Research sweep 2026-09-09 (nine passes: literature, harness docs, GitHub). Full notes in
`PLAN-vouch.md` at the repo root. Numbers are as reported by the cited papers.

## The frame: correction, interruption, attribution, gating

| claim | source |
|---|---|
| "Punishing" a stateless deployed model in-session is a category error; the enforceable surfaces are detect the error, correct or interrupt the output, attribute and log it, gate downstream actions | threat-model analysis of open-weight enforcement surfaces, 2026 (see PLAN-vouch.md, "Research connection") |
| Post-training persists hallucination because binary scoring rewards guessing over abstention; the fix is a scoreboard that penalizes confident errors more than "I don't know" | Kalai, Nachum, Vempala, Zhang, "Why Language Models Hallucinate", arXiv:2509.04664 (the NOT VERIFIED credit is that scoreboard at the harness level) |
| Agent identifiers, real-time monitoring, and tamper-evident activity logging are the accountability infrastructure that links an action to an agent | Chan et al., "Visibility into AI Agents", arXiv:2401.13138 (the hash-chained receipt ledger) |
| Every software-layer safeguard the operator controls is strippable; only what is below the software layer or outside it survives | same threat-model analysis; vouch works because the user, not the model, owns the hooks (config guard enforces it) |

## Why not just tell the model to be careful

| claim | source |
|---|---|
| Threats, tips, and stakes wording have no aggregate effect on current models; per-question swings are unpredictable | Meincke, Mollick et al., Prompting Science Report 3, arXiv:2508.00614 |
| EmotionPrompt's headline gains shrink to +2.6 percent on honest averaging | arXiv:2409.20303 |
| Unaided self-correction lowers accuracy | Huang et al., ICLR 2024, arXiv:2310.01798; Stechly/Kambhampati arXiv:2402.08115 |
| Penalizing narrated reasoning produces hidden misbehaviour; penalize the unverified claim, never the reasoning | OpenAI CoT monitoring arXiv:2503.11926; Anthropic arXiv:2511.18397 |
| Naive accumulation of failures in context does not help; keep the ledger short, attributed, and include wins | Monea et al., arXiv:2410.05362 |

## Rule 0: recall is not evidence (grounding lock)

| claim | source |
|---|---|
| 20-30 point accuracy loss when the needed content sits mid-context | Liu et al., Lost in the Middle, arXiv:2307.03172 |
| All 18 frontier models degrade monotonically with context length | Chroma, Context Rot, 2025 |
| Only 50-70 percent of code an agent viewed survives into the context it patches from (medium confidence) | ContextBench-style analyses, see plan notes |
| Read-before-edit with content fingerprint | SteelDynamite/pi-read-before-write, Pinperepette/grounded (MIT, pattern reused) |

## The claim line and receipts

| claim | source |
|---|---|
| False success is 35.6 percent of agent failures (75.8 percent on AppWorld); drops ~15x where an independent verifier can check state | arXiv:2606.09863 |
| Exposing per-constraint verification status cut premature exit 60 to 35 percent | LiveLedger, arXiv:2602.07549 |
| Unforgeable tool receipts detect 94 percent of fabricated tool references and 91 percent of false-absence claims at <15 ms | arXiv:2603.10060 (HMAC receipts reused as the ledger signature) |
| Framing "not verified" as a success outcome raised correct abstention 65 to 80.5 percent; "reproduce first" alone did nothing | arXiv:2605.07769 |
| Evidence-or-FAIL verifier one tier below the producer; verdict without evidence is FAIL; 3-dispatch cap; typed failure triage | midego1/claude-orchestrate (MIT, contract reused) |
| Verification-before-completion iron law | obra/superpowers (MIT) |

## The bankroll and wagers

| claim | source |
|---|---|
| Persistent virtual bankroll with wagers: stake tracks correctness (big bets ~99 percent right, small ~74 percent); learning across rounds 12.0 vs 2.9 pp (p=0.011) | arXiv:2512.05998 (pilot, forecasting domain) |
| Scalar reward per attempt drives improvement without verbal critique | "Reward Is Enough", arXiv:2506.06303 |
| Raw self-reported confidence is noise; recalibrate against historical hit rate | Agora, arXiv:2607.09600 (ECE 0.222 to 0.023); AgentLance arXiv:2608.23867 |
| Never gate on the confidence you asked for; proper scoring breaks when the report buys anything else | arXiv:2605.07671 |
| Injected budget-used/remaining cut wasted tool calls 40 percent at equal accuracy | Budget-Aware Tool Use, arXiv:2511.17006 |
| Models are optimistically biased about remaining budget; the clock must be harness-side | BAGEN, arXiv:2606.00198 |
| Persistent per-model scoreboard that routes work away from losers | phuetz/code-buddy (MIT, pattern) |
| Brier-scored self-reports with a pre-committed rollback | Seth090502/osanwe-public (MIT, pattern) |
| **Hypothesis**: a persistent penalty ledger changes behaviour across coding sessions | no published controlled study; vouch measures it (see Measurement) |

## Tiers, demotion, delegation

| claim | source |
|---|---|
| A failed attempt left in context raises per-step error ~7.1x; clean restart dominates | arXiv:2605.08563 (single-author preprint) |
| Replacing the worst agents with weaker models: pass@1 62 to 79 percent with 38 percent fewer tokens; demote, don't delete | "Agents that Matter", arXiv:2605.27621 |
| Autonomy as an earned trust score that shrinks after errors | CSA Agentic Trust Framework 2026 (concept) |
| Evidence-anchored failure memory: +34 percent relative success, 16 percent fewer steps | ReasoningBank, arXiv:2509.25140 |
| Attribution must name the specific failing step | AgentDebug, arXiv:2509.25370 |

## Loops, budgets, abort

| claim | source |
|---|---|
| A failed agent run burns ~5x the tokens of a success (8.8M vs 1.8M) | SWE-Effi, arXiv:2509.09853 |
| Non-LLM step monitor: <1 ms per step, 96 percent catch with coverage check, 0 false positives on healthy runs; weak on content corruption (hence receipts) | arXiv:2608.02464 |
| Early abort of doomed runs saves 55-60 percent of generated tokens at 90 percent recall | arXiv:2607.06503 |
| Circuit breaker after 3 identical failures | frankbria/ralph-claude-code, VoDaiLocz/kilo-kit-mcp (patterns) |
| Rulings not stalls; four stop conditions | obra/superpowers subagent-driven-development (MIT) |
| ASSUMPTIONS block pre-flight | addyosmani/agent-skills using-agent-skills (MIT) |

## Fan-out policy

| claim | source |
|---|---|
| Multi-agent token multipliers 1.58x to 6.15x; error amplification up to 17.2x; negative returns once the solo agent exceeds ~45 percent accuracy; orchestrator cross-check cuts factual errors 22.7 percent | arXiv:2512.08296 |
| At matched thinking tokens a single agent matches or beats all five multi-agent topologies | arXiv:2604.02460 |
| Multi-agent on sequential tasks: -39 to -70 percent | PlanCraft results in arXiv:2512.08296 |
| Inter-agent misalignment is ~37 percent of multi-agent failures; topology changes bought +0 pp | MAST, arXiv:2503.13657 |
| Calling an LLM judge every round: +129 percent tokens, no gain; deterministic signals first | arXiv:2606.27009 |
| A cheap critic gate cut attempts 8.0 to 1.35 | OpenHands critic, March 2026 |
| Verifier cost is linear in trajectory length; tool-based verification costs a 1.14x verifier | arXiv:2502.20379, arXiv:2505.11730 |
| Inline floor (<=2 files / <=40 lines never fans out); cost gate before dispatch | ekamphuis82/claude-code-swarm (MIT, pattern) |
| Single-writer ledger keys and a blocking join | kenn-io/kata (MIT, pattern) |
| Cross-agent IMPOSSIBLE broadcast | **our addition**; no prior implementation found |

## Measurement

Per session and per model version the ledger records: claims backed vs unbacked, wagers lost,
loops tripped, aborts, bankroll trajectory, hook latency. Compare total tokens and turns for the
same task with and without vouch. The skill passes only if both go down and at least one
unbacked claim is blocked on a seeded-fault run. No published token delta exists for any of the
patterns above; this measurement is the contribution.
