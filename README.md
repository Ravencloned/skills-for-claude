# Skills for Claude

A marketplace of Claude Code plugins, one folder per skill, each with its own README, tests,
benchmark harness, and the research it was built on.

```
claude plugin marketplace add Ravencloned/skills-for-claude
claude plugin install <name>@skills-for-claude
```

| skill | what it does | status |
|---|---|---|
| [`vouch`](vouch/) | Receipts, not recall. Signed tool receipts, a claim guard, a grounding lock, and a per-model bankroll that sets the model's autonomy. Makes the model pay for unforced errors in the only currency it has. | v0.2.12, released, submitted to the community marketplace |

Each skill folder is a complete plugin: `SKILL.md`, `scripts/`, `hooks/`, `agents/`, `tests/`,
`bench/`, `docs/` (plan and research), `reference.md` (every rule with its citation),
`THIRD_PARTY_NOTICES.md`. The repo root holds only the marketplace manifest and this index.

MIT.
