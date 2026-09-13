---
type: tool_used
tool: Bash
input_match: dejavu\.js"?\s+report\s+\S+.*--verdict\s+(EXISTS|PARTIAL|NOVEL|UNKNOWN)\b
min: 1
---

The engine's `report <slug> --verdict ...` subcommand ran at least once with a slug and a verdict,
so the verdict was validated against the log and the canonical copy under `.dejavu/checks/` was
written. A `tool_used` grader sees the command, not its exit code or the file; the written report
itself (at least five search-log rows, every Closest-matches row `listed` or `fetched`) is asserted
by `bench/live.sh invoke`, which reads the artifact.
