---
type: tool_used
tool: Bash
input_match: dejavu\.js"?\s+(open\s+\S|report\s+\S+.*--verdict\s|skip\s.*--user-said\s)
min: 1
---

Before the plan could leave plan mode, a check was opened and reported or a skip was recorded
through the engine in its success form (a `skip` without `--user-said` is refused with exit 1 and
must not count). The `gate` denies `ExitPlanMode` once when neither exists; this grader is what
shows the deny was resolved rather than ignored. A `tool_used` grader cannot see exit codes, so
`bench/evaluate.sh` section 2 (every skip in `skips.jsonl` carries `user_said`) is the authoritative
grade for this case.
