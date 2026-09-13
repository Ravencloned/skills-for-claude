# Third-party notices

dejavu's engine (`scripts/dejavu.js`) is original code; its io helpers (`readStdin`, `readJson`,
`writeJson`, `appendLine`, `out`, `ctx`, `seenBefore`, `main`) are copied from the sibling plugin
`vouch/scripts/vouch.js` in this repository (same author, MIT). No third-party code is included.
The prior-art skills examined for `docs/RESEARCH.md` were read, not reused:
`ShanedevPro/dont-reinvent-the-wheel-skill` (MIT) and the patent `prior-art-search` skill in
`majiayu000/claude-skill-registry`. Patterns inherited through vouch (verifier one tier below the
producer, the 3-dispatch cap, the inline floor, the circuit breaker) keep their attributions in
`vouch/THIRD_PARTY_NOTICES.md`.

## Data sources and their terms

The engine calls the public endpoints below without keys, with the User-Agent `dejavu/<version>`,
one request at a time per source, and never from a hook. Limits quoted are from the providers'
documentation at the URLs given; the ones marked *probed* were confirmed on this machine on
2026-09-13, the rest are as documented and are re-checked by `bench/live.sh endpoints` before
each release. Results are shown to the user and written into `docs/dejavu/<slug>.md`; each row
keeps its source URL, which is the attribution those terms ask for.

| source | endpoint | terms | limits and etiquette |
|---|---|---|---|
| GitHub (`gh-repos`, `gh-code`, `gh-topics`, `inspect`, `fetch` of a repo URL) | `gh search repos\|code --json`, `gh api repos/{owner}/{repo}`, `gh api repos/{owner}/{repo}/readme`; without `gh` (missing or unauthenticated) the same routes keyless on `https://api.github.com/` | GitHub Terms of Service; the user's own `gh` authentication, or the unauthenticated REST limit | search 30 requests/min (repos) and 10/min (code), *probed*; keyless REST 60 requests/hour per IP; https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api |
| GitHub raw content (`fetch` of a blob URL) | `https://raw.githubusercontent.com/{owner}/{repo}/{ref}/{path}` | GitHub Terms of Service | keyless; one file per fetch, 200 KB cap |
| npm (`npm`, `inspect npm:`) | `https://registry.npmjs.org/-/v1/search`, `https://registry.npmjs.org/<name>`, `https://api.npmjs.org/downloads/point/last-month/<name>` (download count for `inspect`) | npm Open-Source Terms and the registry's public API; https://github.com/npm/registry/blob/main/docs/download-counts.md | keyless, *probed*; keep the request rate modest, no bulk mirroring |
| PyPI (`pypi`, `inspect pypi:`) | `https://pypi.org/search/?q=` (HTML, best-effort), `https://pypi.org/pypi/<name>/json` | PyPI Terms of Use, https://pypi.org/policy/terms-of-use/ | no JSON search API; PyPI asks clients not to hammer the search page; the engine sends one request per query, and when the page is the JS client challenge (*probed*: it always was on 2026-09-13) it tries the exact-name JSON endpoint once and otherwise logs an error row that names the WebSearch `site:pypi.org` fallback |
| crates.io (`crates`, `inspect crate:`) | `https://crates.io/api/v1/crates?q=` | crates.io data-access policy, https://crates.io/data-access | a User-Agent naming the tool is required, *probed*; one request per second |
| Hacker News (`hn`) | `https://hn.algolia.com/api/v1/search` | Algolia HN Search API terms, https://hn.algolia.com/api | keyless, *probed*; the documented per-IP hourly limit applies; attribution to Algolia HN Search and Hacker News on the results page |
| StackExchange (`so`) | `https://api.stackexchange.com/2.3/search/advanced?site=stackoverflow` (gzip) | content is CC BY-SA 4.0 with attribution to the author and the question URL; API terms at https://api.stackexchange.com/docs | keyless daily quota per IP; the engine appends `(quota N)` from `quota_remaining` to the logged request and honours a `backoff` field through `so_backoff_until`; it does not warn on a low quota |
| OpenAlex (`openalex`) | `https://api.openalex.org/works?search=` | OpenAlex data is CC0; https://docs.openalex.org/ | keyless, *probed*; the engine sends no `mailto` parameter in v0.1, so requests go through the common pool rather than the polite pool (no config key for it yet) |
| arXiv (`arxiv`) | `https://export.arxiv.org/api/query?search_query=` | arXiv API Terms of Use, https://info.arxiv.org/help/api/tou.html; metadata is CC0, papers keep their own licenses | at least 3 s between requests, one connection, *probed*; the engine enforces the spacing through `.dejavu/ratelimit.json` and retries once after 3 s on a 429, 503 or timeout, then logs the error |
| grep.app | not used in v0.1 | the raw API is bot-blocked; an MCP endpoint at `https://mcp.grep.app` exists | optional, later |

WebSearch and WebFetch results are subject to the Claude Code terms; the engine only logs the
query, the URL and the title.

Research citations are listed in `reference.md`.
