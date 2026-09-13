# Installing dejavu

Requirements: Claude Code 2.1.265 or newer, Node 18 or newer on PATH. Optional: the `gh` CLI,
authenticated (`gh auth status`), for Tier 1 (`gh-repos`, `gh-code`, `gh-topics`: 30 and 10
queries per minute). Without it, Tier 1 runs through WebSearch `site:github.com`, and `inspect` or
`fetch` of a GitHub repository goes through keyless `api.github.com` (60 requests per hour per IP);
`inspect` of npm, crates.io and PyPI packages, and of any URL, never needs `gh`. No other
dependencies. dejavu is a Claude Code plugin: one folder with a manifest, a skill, an agent, hooks,
and the engine.

## A. Install from the marketplace (recommended)

```bash
claude plugin marketplace add Ravencloned/skills-for-claude
claude plugin install dejavu@skills-for-claude
```

Normal mode is on immediately: the SessionStart line (only when `docs/dejavu/` has reports), the
plan-mode offer and gate, and the WebSearch/WebFetch receipt hook. Run a check with
`/dejavu quick <what you are about to build>` (or `default`, `deep`). Updates arrive when `version`
in `plugin.json` is bumped. The marketplace path was verified end to end for the sibling plugin
vouch on 2026-09-10; dejavu has the same layout and manifest shape.

## B. Try it for one session from a clone

```bash
claude --plugin-dir ./dejavu
```

Same as A, for that session only. This is how `bench/live.sh invoke` and `planmode` run it.

## C. Copy into a project (experimental)

```bash
mkdir -p .claude/skills && cp -r dejavu .claude/skills/dejavu
printf '.dejavu/\n' >> .gitignore
```

The folder carries `.claude-plugin/plugin.json`, so Claude Code can load it as the plugin
`dejavu@skills-dir` in an interactive session in that project, after the workspace-trust prompt.
Known limits (measured on vouch, 2026-09-10; same layout): the skills-dir path did not load in
non-interactive (`claude -p`) runs, which never see the trust prompt, and a directory junction is
not followed. The receipt hook declared in `SKILL.md` and `${CLAUDE_PLUGIN_ROOT}` in
`hooks/hooks.json` exist only when the plugin loader runs the folder, so a copy that did not load as
a plugin runs nothing at all. If a session in a project with reports shows no
`dejavu: N reports on file` line, use A or B, or the standalone hooks below.
`cp -r dejavu ~/.claude/skills/dejavu` is the same copy for every project, with the same limits.

### Standalone fallback (no plugin loading)

Merge the `hooks` object from `dejavu/hooks/hooks.json` into `.claude/settings.json`, replacing
`${CLAUDE_PLUGIN_ROOT}` with `$CLAUDE_PROJECT_DIR/.claude/skills/dejavu`, and copy
`dejavu/agents/dejavu-scout.md` to `.claude/agents/`. That gives the hooks only; `/dejavu` needs the
plugin loader. The engine de-duplicates hook deliveries by `tool_use_id`, so running both the plugin
and the standalone copy logs nothing twice and denies `ExitPlanMode` at most once per plan cycle.

## D. Other harnesses (prose tier)

```bash
npx skills add Ravencloned/skills-for-claude
```

Installs `SKILL.md` into Codex, Cursor, Gemini CLI, OpenCode and the other agents the installer
supports. The hooks (offer, gate, receipt) are Claude Code only in v0.1; the procedure, the
framings, the tiers, the evidence rule and the report format still apply as instructions, and the
engine's CLI subcommands run anywhere Node 18 does.

## The `Bash(node *)` allow rule (recommended)

`SKILL.md` grants `allowed-tools: Bash(node *)` so the invoke line runs without a prompt, but that
grant covers only the invoking turn. Every later `node dejavu.js query|inspect|report ...` call
would prompt. Add the rule once to the project or user settings:

```json
{ "permissions": { "allow": ["Bash(node *)"] } }
```

in `.claude/settings.json` (project) or `~/.claude/settings.json` (user). The engine only ever
writes under `.dejavu/` and `docs/dejavu/` (a `report_dir` in `dejavu.config.json` that resolves
outside the project is ignored with a note); the plan-mode deny is the only thing it blocks.

## Plan-mode behaviour

Once per plan cycle, three things can happen, in this order:

1. **Offer once.** The first prompt submitted in plan mode adds one line of context asking the
   model to ask you, once, whether to run `/dejavu [quick|default|deep] <what is being built>` or
   skip it: through `AskUserQuestion` where that tool exists, otherwise as a one-line question in
   its reply, after which it ends the turn and waits. Only your answer authorizes the skip command;
   the model must never skip on your behalf. It does not ask again in that cycle.
2. **Gate once.** If the model calls `ExitPlanMode` with no reported check and no skip for the
   session, the call is denied once with the same instruction. The second call is allowed
   whatever happened, so a plan can never be trapped.
3. **Skip command.** To decline: `node dejavu.js skip --user-said "<your own words>" "<reason>"`
   records the skip (your words and the reason, in `.dejavu/skips.jsonl` and the session file) and
   opens the gate. The engine refuses a skip without `--user-said` (exit 1), so the model cannot
   record one on your behalf; the offer and the gate reason both say so.

A check run inside plan mode uses `report --no-docs` (the repo is read-only there); the plan's
first step is `node dejavu.js publish <slug>`, which lands the report in `docs/dejavu/`. Entering
plan mode a second time in the same session re-arms one offer and one deny if the session is still
unsatisfied. Turn either part off with `dejavu.config.json`: `{ "offer": false }` or
`{ "gate": false }`.

## Inspect, measure, reset

```bash
node dejavu/scripts/dejavu.js status              # session state, open check, reports on file
node dejavu/scripts/dejavu.js recheck <slug>      # new hits since the report date, appended to the report
node dejavu/scripts/dejavu.js publish <slug>      # copy the canonical report into docs/dejavu/
node dejavu/scripts/dejavu.js skip --user-said "<your words>" "<reason>"   # open the plan-mode gate without a check (needs your answer)
node dejavu/scripts/dejavu.js help                # every subcommand, environment variable and state file
```

State: `.dejavu/` in the project (sessions, checks, current check, pending skip, pending invoke,
rate-limit stamps) and `~/.claude/dejavu/errors.log`. Delete `.dejavu/` to reset; committed reports in
`docs/dejavu/` are unaffected. Override defaults with `dejavu.config.json` in the project root;
keys are listed in `log/SCHEMA.md` (`report_dir`, which must stay inside the project, `budgets`,
`tiers_required`, `offer`, `gate`, `sources_off`).

Page text that `fetch` prints, and the titles, descriptions and error bodies the sources return,
are data about the candidates; the engine frames fetched text between `--- untrusted page text ---`
markers and `SKILL.md` tells the model to read it as evidence, never as instructions.

## Tests and bench

```bash
bash dejavu/tests/run.sh               # pipe-tests, offline (DEJAVU_FIXTURES), isolated HOME and project
bash dejavu/bench/live.sh endpoints    # every real source once, plus three inspect calls
bash dejavu/bench/live.sh invoke       # real claude -p run of /dejavu quick
bash dejavu/bench/live.sh planmode     # real claude -p --permission-mode plan run
```

The live bench writes under `dejavu/bench/results/`; run `endpoints` before every release, since
fixtures cannot catch a source changing its response shape.
