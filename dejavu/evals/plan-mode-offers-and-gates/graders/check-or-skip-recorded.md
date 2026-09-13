---
type: tool_used
tool: Bash
input_match: dejavu\.js.* (open|report|skip)
min: 1
---

Before the plan could leave plan mode, a check was opened and reported or a skip was recorded
through the engine. The `gate` denies `ExitPlanMode` once when neither exists; this grader is what
shows the deny was resolved rather than ignored.
