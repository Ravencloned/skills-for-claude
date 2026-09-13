---
type: regex
target: last_message
match: contains
pattern: (docs/dejavu/|\.dejavu/checks/)[A-Za-z0-9._-]+\.md
flags: m
---

The final message names the report file (the committed copy under `docs/dejavu/`, or the canonical
copy under `.dejavu/checks/` when the check ran with `--no-docs`).
