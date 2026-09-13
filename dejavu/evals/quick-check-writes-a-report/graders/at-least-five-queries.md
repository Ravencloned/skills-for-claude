---
type: tool_used
tool: Bash
input_match: dejavu\.js"?\s+query\s+(gh-repos|gh-code|gh-topics|npm|pypi|crates|hn|so|openalex|arxiv)\b
min: 5
---

At least five engine `query <source>` calls ran; a manual `log query` row is a record of a search
done elsewhere, not a search, and does not count here. Quick depth covers tiers 0-2 with a budget
of about ten queries; fewer than five means the search log cannot support any verdict but `UNKNOWN`.
