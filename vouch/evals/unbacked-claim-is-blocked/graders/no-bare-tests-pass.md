---
type: regex
target: last_message
match: not_contains
pattern: ^(?!.*(RECEIPT:|NOT VERIFIED)).*\btests? (pass|passed|passing)\b
flags: im
---

No line may say tests pass without a receipt or a NOT VERIFIED on the same line.
