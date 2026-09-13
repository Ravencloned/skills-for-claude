#!/usr/bin/env bash
# Creates the "atelier" playground: one small Node API project with three roadmap features whose
# prior-art answer is known in advance, for an INTERACTIVE session with the dejavu plugin loaded.
# Run it, then follow the printed instructions (the full script is bench/PLAYGROUND.md).
#
#   bash dejavu/bench/playground.sh [target-dir]      (default: dejavu/playgrounds/atelier, gitignored)
#
# Seeds (the evaluator checks each one from the .dejavu logs, never from what the agent says):
#   A. per-client rate limiting          -> EXISTS. Tier 0 must find src/legacy/throttle.js (a teammate
#                                           started one; it is in git history), Tier 1/2 must fetch a
#                                           real library (express-rate-limit, rate-limiter-flexible, ...).
#   B. idempotency keys on POST /orders  -> PARTIAL or EXISTS; whichever it is, the top match must be
#                                           fetched or inspected, never recalled.
#   C. export in the in-house .tally     -> NOVEL only with every required tier searched; otherwise
#      format (docs/tally-format.md)        UNKNOWN naming the gaps. Any "match" here is a recalled or
#                                           mis-read result and the engine must have refused to count it.
#   Plan mode: the offer must be made once, a skip must carry the user's own words, and ExitPlanMode
#   must pass on the second call after a report or a skip.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
D="${1:-$HERE/../playgrounds/atelier}"
rm -rf "$D"; mkdir -p "$D/src/legacy" "$D/test" "$D/docs"
cd "$D"
cat > package.json <<'EOF'
{ "name": "atelier", "version": "0.3.0", "private": true, "type": "module", "license": "MIT",
  "description": "A small orders API for a print shop; the roadmap in README.md lists what comes next.",
  "scripts": { "test": "node --test", "start": "node src/server.js" } }
EOF
cat > README.md <<'EOF'
# atelier

A small orders API for a print shop. Plain Node, no framework, one JSON file as the store.

    npm test
    npm start          # http://localhost:8787

## Roadmap (next three features, in order)

A. **Per-client rate limiting.** One client's burst took the API down last month. Limit each client
   (by API key, falling back to IP) to N requests per minute with a clear 429 and a Retry-After header.
   Someone on the team started something for this a while back; check before you build.

B. **Idempotency keys on `POST /orders`.** Clients retry on timeouts and we get duplicate orders.
   Honour an `Idempotency-Key` header: same key + same body within 24 h returns the first response;
   same key + different body is a 422. Storage can be the JSON store for now.

C. **Export the order ledger in `.tally` format.** Our accountant's tool reads only our in-house
   `.tally` files (spec in `docs/tally-format.md`, schema version 2). Add `GET /export.tally` that
   streams the ledger in that format, with the schema version in the header block.

Before building any of these, find out whether it has been done already.
EOF
cat > docs/tally-format.md <<'EOF'
# .tally format, schema version 2 (in-house)

A `.tally` file is UTF-8 text. It starts with a header block, then one ledger line per order.

    %tally 2
    %shop atelier
    %exported 2026-09-13T10:00:00Z
    %%
    2026-09-01 | ORD-1041 | 3 x A2 poster matte | 87.00 | EUR | paid
    2026-09-02 | ORD-1042 | 1 x business cards 500 | 42.50 | EUR | open

Rules: header keys start with `%`, the header ends with `%%`, fields are separated by ` | ` (space,
pipe, space), amounts carry two decimals, currency is ISO 4217, status is `open`, `paid` or `void`.
Version 1 files had no currency column; a version 2 writer must never emit a version 1 line.
This format exists only inside this company.
EOF
cat > src/server.js <<'EOF'
import http from 'node:http';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const STORE = new URL('../orders.json', import.meta.url);
export function load() { return existsSync(STORE) ? JSON.parse(readFileSync(STORE, 'utf8')) : []; }
export function save(rows) { writeFileSync(STORE, JSON.stringify(rows, null, 2)); }
export function nextId(rows) { return 'ORD-' + String(1000 + rows.length + 1); }

export function handle(req, res, body) {
  const rows = load();
  if (req.method === 'GET' && req.url === '/orders') return json(res, 200, rows);
  if (req.method === 'POST' && req.url === '/orders') {
    const order = Object.assign({ id: nextId(rows), status: 'open', created: new Date().toISOString() }, JSON.parse(body || '{}'));
    rows.push(order); save(rows);
    return json(res, 201, order);
  }
  return json(res, 404, { error: 'not found' });
}
function json(res, code, obj) { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj)); }

if (process.argv[1] && process.argv[1].endsWith('server.js')) {
  http.createServer((req, res) => { let b = ''; req.on('data', (c) => (b += c)); req.on('end', () => handle(req, res, b)); }).listen(8787);
  console.log('atelier listening on 8787');
}
EOF
cat > src/legacy/throttle.js <<'EOF'
// Per-client throttle, started 2026-06 and never finished (see git log). Counts requests per key in a
// fixed one-minute window; the sliding-window version and the Retry-After header are still TODO.
const buckets = new Map();
export function throttle(key, limit = 60) {
  const minute = Math.floor(Date.now() / 60000);
  const k = key + ':' + minute;
  const n = (buckets.get(k) || 0) + 1;
  buckets.set(k, n);
  // TODO: sliding window, Retry-After, eviction of old minutes
  return n <= limit;
}
EOF
cat > test/server.test.js <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import { nextId } from '../src/server.js';
test('ids are sequential', () => { assert.equal(nextId([]), 'ORD-1001'); assert.equal(nextId([{}, {}]), 'ORD-1003'); });
EOF
printf 'node_modules/\norders.json\n.dejavu/\n' > .gitignore

# git history: tier 0 has to be able to find the unfinished throttle with `git log -S`
git init -q -b main
G="git -c user.name=teammate -c user.email=teammate@example.com"
$G add package.json README.md src/server.js test/server.test.js .gitignore
$G commit -q -m "atelier: orders API with a JSON store" --date="2026-05-20T10:00:00"
$G add src/legacy/throttle.js
$G commit -q -m "Start a per-client throttle for the API (fixed window; sliding window and Retry-After still TODO)" --date="2026-06-11T16:30:00"
$G add docs/tally-format.md
$G commit -q -m "Document the in-house .tally export format, schema version 2" --date="2026-08-02T09:15:00"

node --test >/dev/null 2>&1 && T="tests green" || T="TESTS FAILING (unexpected)"
ABS="$(pwd)"
command -v cygpath >/dev/null 2>&1 && ABS="$(cygpath -m "$ABS")" && PLUGIN="$(cygpath -m "$PLUGIN")"
cat <<EOF

playground ready: $ABS   ($T, 3 commits)

Open it with the plugin loaded (one session per feature is easiest):

    cd "$ABS"
    claude --plugin-dir "$PLUGIN"

Then follow dejavu/bench/PLAYGROUND.md: plan mode + feature A (expect the offer, say yes),
plan mode + feature C (say skip, in your own words), and /dejavu default on feature C.
Afterwards, from the repo root:

    bash dejavu/bench/evaluate.sh "$ABS"
EOF
