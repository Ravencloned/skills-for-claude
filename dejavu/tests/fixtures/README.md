# dejavu test fixtures

Raw response bodies, saved verbatim (no reformatting), so `tests/run.sh` can run every `query` / `inspect` parser offline
via `DEJAVU_FIXTURES=<this dir>`. Fixed query for every search source: **token bucket rate limiter**.
Captured 2026-09-13 from this machine with curl 8.15.0 and gh 2.83.0 (authenticated). Line endings: LF only (no CR bytes).

| file | bytes | capture command |
|---|---:|---|
| npm.json | 10062 | `curl -s "https://registry.npmjs.org/-/v1/search?text=token%20bucket%20rate%20limiter&size=10"` |
| crates.json | 9940 | `curl -s -A "dejavu-fixture-capture" "https://crates.io/api/v1/crates?q=token%20bucket%20rate%20limiter&per_page=10"` |
| hn.json | 29898 | `curl -s "https://hn.algolia.com/api/v1/search?query=token%20bucket%20rate%20limiter&tags=story&hitsPerPage=10"` |
| so.json | 7403 | `curl -s --compressed "https://api.stackexchange.com/2.3/search/advanced?q=token%20bucket%20rate%20limiter&site=stackoverflow&pagesize=10"` (`--compressed`: the API always gzips; the file is plain JSON) |
| openalex.json | 217395 | `curl -s "https://api.openalex.org/works?search=token%20bucket%20rate%20limiter&per-page=10"` |
| arxiv-ratelimited.txt | 14 | `curl -s -L "https://export.arxiv.org/api/query?search_query=all:%22token%20bucket%22&max_results=5"` -> HTTP 429, body `Rate exceeded.` (see arXiv note) |
| arxiv-503.html | 126 | same command, retried after 10 s / 30 s / 45 s -> HTTP 503 (see arXiv note); a last attempt at 16:30 the same day (`curl --retry 1 --retry-delay 10`) got the same 126-byte 503 and then a 446-byte Varnish "503 Request timedout" page |
| pypi.html | 3038 | `curl -s "https://pypi.org/search/?q=token+bucket+rate+limiter"` -> HTTP 200 but a JavaScript "Client Challenge" page, not results (see PyPI note) |
| gh-repos.json | 3820 | `gh search repos "token bucket rate limiter" --limit 10 --json fullName,description,url,stargazersCount,updatedAt,license,isArchived` + one appended row (see below) |
| gh-code.json | 1482 | `gh search code "token bucket" --limit 5 --json repository,path,url` |
| gh-topics.json | 1635 | `gh search repos --topic rate-limiter --limit 5 --json fullName,description,url,stargazersCount,updatedAt,license,isArchived` (captured 16:20; the camelCase array the engine's `gh-topics` source runs) |
| gh-topics-rest.json | 28219 | `gh api "search/repositories?q=topic:rate-limiter&per_page=5"` (the REST shape; same five repos, see below) |
| inspect-github.json | 7515 | `gh api repos/express-rate-limit/express-rate-limit` |
| inspect-npm.json | 461272 | `curl -s "https://registry.npmjs.org/express-rate-limit"` (full packument, every version) |
| inspect-crates.json | 44972 | `curl -s -A "dejavu-fixture-capture" "https://crates.io/api/v1/crates/governor"` |
| recheck/npm.json | 10662 | copy of npm.json with one **fabricated** package object `zz-new-since-report` prepended to `objects[]` (`total` +1) |
| recheck/gh-repos.json | 4171 | copy of gh-repos.json with one **fabricated** repo `zz-new/zz-new-since-report` (updatedAt 2026-09-13T00:00:00Z) prepended |
| fetch.html | 559 | `curl -s "https://example.com/"` (what `fetch <url>` and `inspect <url>` read: any real HTML page with a `<title>`) |
| inspect-npm-downloads.json | 94 | `curl -s "https://api.npmjs.org/downloads/point/last-month/express-rate-limit"` (read by `inspect npm:<name>` next to inspect-npm.json) |
| inspect-pypi.json | 17847 | `curl -s "https://pypi.org/pypi/token-bucket/json"` (read by `inspect pypi:<name>`; `license_expression` Apache-2.0, last upload 2026-06-12) |
| fetch-readme.md | 8744 | `gh api repos/express-rate-limit/express-rate-limit/readme -H "Accept: application/vnd.github.raw+json"` (what `fetch <github.com repo URL>` reads instead of the page: the README through the contents API; the keyless `curl -H "Accept: application/vnd.github.raw+json" https://api.github.com/repos/express-rate-limit/express-rate-limit/readme` returns the identical body) |
| log.jsonl | 24228 | **generated** by running the engine against this directory (see "log.jsonl and log.meta.json" below); not a capture |
| log.meta.json | 555 | the `.dejavu/checks/<slug>.json` that belongs to log.jsonl (slug `fx`); generated the same way |

## Notes

**gh-repos.json is 10 real search rows plus one appended real row.** The live search did not return
`express-rate-limit/express-rate-limit`, which the `evidence: listed` test and `bench/live.sh` inspect against, so its row was
fetched with `gh api repos/express-rate-limit/express-rate-limit` and reshaped to the `gh search repos --json` field names
(`fullName, description, url, stargazersCount, updatedAt, license{key,name,url}, isArchived`) and appended as the 11th element.
Every value in that row is the real API value at capture time (3305 stars, MIT, updated 2026-09-10T01:30:05Z). The fixture
therefore contains `https://github.com/express-rate-limit/express-rate-limit`.

**gh-topics comes in both shapes.** `gh-topics.json` is the camelCase array that `gh search repos --topic <slug> --json ...`
prints, which is what the engine's `gh-topics` source runs (`fullName, url, stargazersCount, updatedAt, license{key,name,url},
isArchived`). `gh-topics-rest.json` is the same search through `gh api search/repositories?q=topic:...`: `{total_count,
incomplete_results, items[]}` with snake_case fields (`full_name, html_url, stargazers_count, pushed_at, license{key,spdx_id},
archived`), which is also what keyless api.github.com returns when `gh` is absent. Both captures list the same five repositories
(bull, resilience4j, unkey, failsafe, express-rate-limit). `ghRepoRows` in scripts/dejavu.js accepts both; `tests/run.sh` test 7
parses the camelCase file in its source loop and the REST file through a temporary fixture dir, and asserts the same five names.
`log.jsonl` row 6 (`gh-topics`, 5 hits) was generated from the REST capture; its `top[]` matches either file.

**arXiv: no successful capture.** Six calls over about four minutes (3 s spacing, then 10 s, 30 s and 45 s waits) all
returned 429 `Rate exceeded.` or a 503 HTML page; the host was throttling this IP (the plan already notes arXiv throttles).
The two real error bodies are kept so the `arxiv` parser can be tested on the failure path (error row, exit 0). A real
Atom feed `arxiv.xml` must be captured later with the same command once the throttle lifts; `tests/run.sh` should skip the
arxiv happy-path case while that file is absent. Note the http:// form of the URL answers 301 with an empty body, so use
https:// (or `-L`). `tests/run.sh` serves arxiv-ratelimited.txt as `arxiv.xml` from a temporary fixture dir to prove the
error path (test 7, test 13) and runs the happy-path case automatically once a real `arxiv.xml` exists here. Live finding
(2026-09-13, `bench/live.sh endpoints` and a curl/Node A/B): while throttling, arXiv either answers 429 `Rate exceeded.` within
0.5 s or holds the connection open for 30 s or more, at random per request and regardless of `Accept-Encoding` (plain curl hung
twice, compressed curl answered once in 0.35 s, the engine got the 429 twice, bare Node fetch hung once). The engine therefore logs
either `HTTP 429 (rate-limited) from arxiv`, `HTTP 503 from arxiv` or `timeout after 15 s` on the query row, after one retry 3 s
later (the `request` then ends in `(retried once after 3 s)`); `bench/live.sh endpoints` classifies all three forms as
RATE-LIMITED (its `is_ratelimit` treats arxiv + timeout as a throttle), so a run whose only failures are the arXiv throttle and
the PyPI challenge exits 0.

**PyPI: bot challenge, not results.** Both the plain `curl -s` call and a browser-like User-Agent get HTTP 200 with a 3 KB
"Client Challenge" page (`/_fs-ch-*/`) that requires JavaScript; it contains no `package-snippet` elements. This is what the
engine's Node fetch will see too, so the fixture is the real-world worst case: the `pypi` parser must return zero rows with a
note, not crash. `pypi` stays best-effort, as the plan says.

**recheck/** feeds the `recheck <slug>` test: the engine diffs registry results by name against the logged `top[]` of the
original query, so the only new hit it may print is `zz-new-since-report` (npm) / `zz-new/zz-new-since-report` (gh-repos).
Both objects are fabricated and marked as such in their `description`.

## log.jsonl and log.meta.json (tests 10, 11, 13)

A complete check log for slug `fx` (topic "token bucket rate limiter for an Express API", depth default, project MIT/javascript),
produced by running the engine with `DEJAVU_FIXTURES` pointing at this directory and then rewriting every `ts` to
2026-09-13T10:00Z + one minute per row (the `ms` values are the real fixture parse times). `tests/run.sh` copies the pair to
`.dejavu/checks/fx.jsonl` / `fx.json` after `open fx` and derives three variants from it in the test itself: `fx-recalled`
(the fetched finding removed: EXISTS must fall to PARTIAL), `fx-gap` (tiers 0-2 and the recalled finding only: NOVEL must fall
to UNKNOWN naming tiers 3, 4, 5) and `fx-novel` (no finding, depth quick: NOVEL must stand). Rows, in order:

| # | kind | what |
|---|---|---|
| 1-2 | note | `opened: ... (depth default)`, `framings recorded` (problem / mechanism / category + 3 synonyms; also in log.meta.json) |
| 3 | query | tier 0 `self`, via `log query self 0 0 "git log -S RateLimiter; grep -ri 'token bucket' src"`, request `manual` |
| 4-6 | query | tier 1: `gh-repos` limit 20 (11 hits, `top[]` carries https://github.com/express-rate-limit/express-rate-limit), `gh-code` (5), `gh-topics` (5) |
| 7-9 | query | tier 2: `npm` (10, `top[]` carries https://www.npmjs.com/package/limiter), `crates` (10), `pypi` (0 hits, `error`: JS client challenge) |
| 10-11 | query | tier 3: `hn` (8), `so` (10) |
| 12-13 | query | tier 4: `openalex` (10), `arxiv` (0 hits, `error`: rate-limited, from arxiv-ratelimited.txt served as arxiv.xml) |
| 14 | query | tier 5: `websearch`, written by the `receipt` hook from a WebSearch tool_response (3 URLs, request `WebSearch`) |
| 15-16 | fetch, meta | `inspect express-rate-limit/express-rate-limit` from inspect-github.json (`via: inspect`; license MIT, 3305 stars, pushed 2026-09-07) |
| 17-19 | finding | express-rate-limit closeness 5 **fetched**; limiter closeness 3 **listed**; rate-limiter-flexible closeness 5 **recalled** (URL in no `top[]`, no fetch) |
| 20 | note | `arxiv answered 429 Rate exceeded; one tier-4 query dropped` |

So the log has 12 query rows (10 without `error`) covering tiers 0-5, which is what `report fx --verdict EXISTS` must render as a
12-row Search log table, a 2-row Closest matches table and a 1-row "Recalled, not fetched" table. Every `top[]` holds the full
fixture result at the limit used, so `recheck` against `recheck/` (overlaid on this directory) finds exactly the two fabricated
rows and nothing else. Regenerate by replaying the commands above in a scratch project (`open`, `frame`, `log query`, ten
`query` calls, one `receipt` with a WebSearch payload, `inspect`, three `log finding`, `log note`), then rewrite `ts` and set
`slug` to `fx` in the meta; a parser change that alters `top[]` means regenerating, and test 10's literal assertions say which.
On 2026-09-13 four `request` strings and one `source` were rewritten in place to the engine's current format rather than
regenerating: rows 4 and 5 (gh-repos, gh-code) now show each word as a separate gh term, rows 9 and 13 (pypi, arxiv: errored)
carry the URL that was attempted, and the `meta` row 16 says `source: "gh-repos"` (an inspect of a GitHub repo).

**Re-capture** by running the commands in the table from this directory; keep `-A "dejavu-fixture-capture"` for crates.io
(its policy requires a User-Agent) and `--compressed` for StackExchange.
