#!/usr/bin/env bash
# Independent evaluation of a dejavu playground session. Nothing here trusts the agent's words:
# the check logs, session files, skips and reports under .dejavu/ and docs/dejavu/ are read directly,
# and each seeded roadmap feature is graded against its known answer (bench/playground.sh).
#   bash dejavu/bench/evaluate.sh <playground-dir>
set -u
D="${1:?playground dir}"
ENGINE="$(cd "$(dirname "$0")/.." && pwd)/scripts/dejavu.js"
cd "$D" || exit 1
command -v cygpath >/dev/null 2>&1 && ENGINE="$(cygpath -m "$ENGINE")"

echo "=== 1. plugin loaded? (a session file appears on the first prompt; the offer only in plan mode)"
if ls .dejavu/sessions/*.json >/dev/null 2>&1; then
  for s in .dejavu/sessions/*.json; do
    node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const id=require("path").basename(process.argv[1],".json");console.log("  session "+id.slice(0,8)+"  offered="+!!s.offered+"  gate_denied="+!!s.gate_denied+"  checks="+JSON.stringify(s.checks||[])+"  skip="+(s.skip?JSON.stringify({reason:s.skip.reason,user_said:s.skip.user_said}):"none"))' "$s"
  done
else
  echo "  no .dejavu/sessions: no hook ran here (was claude started with --plugin-dir?)"
fi
echo
echo "=== 2. skips: every one must carry the user's own words (user_said), never the model's"
if [ -f .dejavu/skips.jsonl ]; then
  node -e 'const rows=require("fs").readFileSync(".dejavu/skips.jsonl","utf8").trim().split("\n").filter(Boolean).map(JSON.parse);for(const r of rows)console.log("  skip  user_said="+JSON.stringify(r.user_said||"")+"  reason="+JSON.stringify(r.reason||"")+(r.user_said?"":"   <- EMPTY: the engine should have refused this"))'
else echo "  none"; fi
echo
echo "=== 3. checks (from .dejavu/checks/*.json + .jsonl): verdicts as validated by the engine"
if ls .dejavu/checks/*.json >/dev/null 2>&1; then
  for m in .dejavu/checks/*.json; do
    node - "$m" <<'EOF'
const fs = require('fs'), path = require('path');
const m = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const log = process.argv[2].replace(/\.json$/, '.jsonl');
const rows = fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch (e) { return null; } }).filter(Boolean) : [];
const q = rows.filter((r) => r.kind === 'query'), qok = q.filter((r) => !r.error);
const tiers = [...new Set(qok.map((r) => Number(r.tier)).filter((t) => !Number.isNaN(t)))].sort();
const f = rows.filter((r) => r.kind === 'finding');
const ev = { fetched: 0, listed: 0, recalled: 0 }; for (const x of f) ev[x.evidence] = (ev[x.evidence] || 0) + 1;
const fetched = rows.filter((r) => r.kind === 'fetch' || r.kind === 'meta').map((r) => String(r.url || ''));
const text = JSON.stringify(rows).toLowerCase();
const topic = String(m.topic || '').toLowerCase();
const seed = /rate.?limit|throttl/.test(topic) ? 'A' : /idempoten/.test(topic) ? 'B' : /tally/.test(topic) ? 'C' : '?';
console.log(`  ${m.slug}`);
console.log(`    seed ${seed}  depth ${m.depth}  status ${m.status}  verdict ${m.verdict || '-'}${m.claimed_verdict && m.claimed_verdict !== m.verdict ? ' (claimed ' + m.claimed_verdict + ', DOWNGRADED by the engine)' : ''}  recommend ${m.recommend || '-'}`);
console.log(`    queries ${qok.length} ok + ${q.length - qok.length} errored | tiers covered ${JSON.stringify(tiers)} | findings ${f.length} (fetched ${ev.fetched}, listed ${ev.listed}, recalled ${ev.recalled}) | published ${m.docs ? 'yes' : 'no (--no-docs, publish pending)'}`);
const framed = m.framings && m.framings.problem && m.framings.mechanism && m.framings.category;
console.log(`    framings ${framed ? 'all three recorded' : 'MISSING (frame was not run)'}`);
const tier0 = q.some((r) => Number(r.tier) === 0);
if (seed === 'A') {
  const foundLegacy = /throttle\.js|legacy\/throttle|src\/legacy/.test(text);
  const lib = fetched.some((u) => /express-rate-limit|rate-limiter-flexible|ratelimit|rate-limit|bottleneck|limiter/.test(u));
  console.log(`    A: tier-0 row ${tier0 ? 'present' : 'MISSING'}; legacy throttle ${foundLegacy ? 'FOUND (good)' : 'NOT FOUND (tier 0 was skipped or not logged)'}; a rate-limit library ${lib ? 'fetched/inspected (good)' : 'never fetched'}; expected verdict EXISTS -> got ${m.verdict}`);
}
if (seed === 'B') {
  const top = f.filter((x) => x.closeness >= 3 && x.evidence !== 'recalled').length;
  console.log(`    B: findings with closeness>=3 and real evidence: ${top} ${top ? '(good)' : '(NONE: nothing was actually looked at)'}; expected PARTIAL or EXISTS -> got ${m.verdict}`);
}
if (seed === 'C') {
  const bogus = f.filter((x) => x.closeness >= 3 && x.evidence !== 'recalled').length;
  console.log(`    C: in-house format; findings claimed >=3 with evidence: ${bogus} ${bogus ? '(SUSPICIOUS: read them)' : '(good: nothing real matched)'}; recalled findings ${ev.recalled}; expected NOVEL with all required tiers, else UNKNOWN naming gaps -> got ${m.verdict}`);
}
const notes = rows.filter((r) => r.kind === 'note').map((r) => r.text);
if (notes.length) console.log(`    notes: ${notes.map((n) => JSON.stringify(String(n).slice(0, 80))).join(', ')}`);
EOF
  done
else
  echo "  no checks: /dejavu never ran here"
fi
echo
echo "=== 4. reports on disk"
ls docs/dejavu/*.md 2>/dev/null | sed 's/^/  published: /' || true
ls .dejavu/checks/*.md 2>/dev/null | sed 's/^/  canonical: /' || true
[ -z "$(ls docs/dejavu/*.md .dejavu/checks/*.md 2>/dev/null)" ] && echo "  none"
for r in docs/dejavu/*.md; do [ -f "$r" ] || continue; n=$(grep -c '^## ' "$r"); echo "  $r: $n sections; search-log rows: $(awk '/^## Search log/{f=1;next}/^## /{f=0}f&&/^\| [0-9]/{c++}END{print c+0}' "$r")"; done
echo
echo "=== 5. engine status and errors"
CLAUDE_PROJECT_DIR="$PWD" node "$ENGINE" status 2>&1 | sed 's/^/  /'
E="$HOME/.claude/dejavu/errors.log"; [ -f "$E" ] && echo "  errors.log lines: $(wc -l < "$E")" || echo "  errors.log: none"
echo
echo "=== 6. what a good session looks like"
echo "  - plan mode + A: session offered=true; one deny then ExitPlanMode passed; check A reported with a tier-0 row, the legacy"
echo "    throttle named, a real library fetched, verdict EXISTS as claimed (no downgrade), recommend adopt or wrap"
echo "  - plan mode + C, declined: a skip whose user_said is what you typed, no check for C in that session, ExitPlanMode passed"
echo "  - /dejavu default C: verdict NOVEL with tiers 0-5 covered and >= 13 ok queries, or UNKNOWN that names the missing"
echo "    tiers; zero findings with closeness >= 3 that are not recalled"
echo "  - every check: framings recorded, no recalled finding counted, errors.log unchanged"
