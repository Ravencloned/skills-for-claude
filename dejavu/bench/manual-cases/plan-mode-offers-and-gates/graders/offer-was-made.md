---
type: tool_used
tool: AskUserQuestion
min: 1
---

The `prompt` hook's one-line offer made the model ask the user, once, whether to run `/dejavu` or
skip it. In a non-interactive run the question may be auto-answered or declined by the runner;
that still counts, since the grader checks the offer, not the answer.
