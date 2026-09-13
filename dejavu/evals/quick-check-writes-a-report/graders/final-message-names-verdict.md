---
type: regex
target: last_message
match: contains
pattern: \b(EXISTS|PARTIAL|NOVEL|UNKNOWN)\b
flags: m
---

The final message states the validated verdict in the engine's vocabulary.
