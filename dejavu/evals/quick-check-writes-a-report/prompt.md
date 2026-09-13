---
name: A quick check writes a report with a search log and an engine-validated verdict
tags: [report, search-log, evidence]
runs: 3
max_turns: 30
allowed_tools: [Read, Grep, Glob, Bash, WebSearch, WebFetch]
---

/dejavu quick a token bucket rate limiter middleware for this Express API, keyed per client

When the report is written, tell me the verdict, the top matches with their URLs, the
recommendation, and where the report is.
