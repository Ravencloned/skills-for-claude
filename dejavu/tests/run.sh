#!/usr/bin/env bash
# dejavu pipe-test battery: synthetic hook JSON in, decisions and log rows out; every source read from tests/fixtures/.
# Runs in an isolated HOME and project dir so it never touches a real project, and never the network
# (DEJAVU_FIXTURES points every fetcher at the captured payloads; test 14 proves DEJAVU_OFFLINE=1 on top).
# Cases follow the numbered list in docs/PLAN.md ("Tests tests/run.sh"); see TESTING.md for what each group proves.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$HERE/../scripts/dejavu.js"
FX="$HERE/fixtures"
TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP="$(cygpath -m "$TMP")"; FX="$(cygpath -m "$FX")"; ENGINE="$(cygpath -m "$ENGINE")"; fi
export DEJAVU_HOME="$TMP/home"
export CLAUDE_PROJECT_DIR="$TMP/proj"
export DEJAVU_FIXTURES="$FX"
# CLI calls run the way Bash runs them for the model: no session id; hooks carry theirs in the stdin JSON
unset CLAUDE_SESSION_ID DEJAVU_OFFLINE
mkdir -p "$CLAUDE_PROJECT_DIR" "$TMP/proj2" "$TMP/proj3"
printf '{ "name": "proj", "private": true, "license": "MIT" }\n' > "$CLAUDE_PROJECT_DIR/package.json"
D="$CLAUDE_PROJECT_DIR/.dejavu"
DOCS="$CLAUDE_PROJECT_DIR/docs/dejavu"
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL $1"; echo "       got: $2"; }
run()  { printf '%s' "$2" | node "$ENGINE" "$1" 2>"$TMP/err"; echo "exit=$?"; }
cli()  { node "$ENGINE" "$@" 2>&1; echo "exit=$?"; }
# ids are generated inside command substitutions (subshells), so a counter would not persist; use entropy
nid()  { printf 'u%s%s%s' "$RANDOM" "$RANDOM" "$RANDOM"; }
# hook JSON builders: session id first, tool_use_id per call
sess()     { printf '"session_id":"%s","cwd":"%s","transcript_path":"%s"' "$1" "$CLAUDE_PROJECT_DIR" "$TMP/none.jsonl"; }
promptj()  { printf '{%s,"hook_event_name":"UserPromptSubmit","permission_mode":"%s","prompt":"%s"}' "$(sess "$1")" "$2" "$3"; }
toolj()    { printf '{%s,"hook_event_name":"PreToolUse","permission_mode":"plan","tool_name":"%s","tool_use_id":"%s","tool_input":{}}' "$(sess "$1")" "$2" "$3"; }
receiptj() { printf '{%s,"hook_event_name":"PostToolUse","tool_name":"%s","tool_use_id":"%s","tool_input":%s,"tool_response":%s}' "$(sess "$1")" "$2" "$3" "$4" "$5"; }
startj()   { printf '{%s,"hook_event_name":"SessionStart","source":"startup"}' "$(sess "$1")"; }
# JSON helpers (node, zero deps): a dotted path out of a JSON file; rows of a check log by kind [and source]
jf()    { node -e 'const o=JSON.parse(process.argv[1]);const v=process.argv[2].split(".").reduce((a,k)=>a==null?a:a[k],o);console.log(v!==null&&typeof v==="object"?JSON.stringify(v):String(v))' "$1" "$2" 2>/dev/null; }
jget()  { node -e 'const o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const v=process.argv[2].split(".").reduce((a,k)=>a==null?a:a[k],o);console.log(v!==null&&typeof v==="object"?JSON.stringify(v):String(v))' "$1" "$2" 2>/dev/null; }
count() { node -e 'const fs=require("fs");const [p,k,s]=process.argv.slice(1);let n=0;try{n=fs.readFileSync(p,"utf8").split("\n").filter(Boolean).map(JSON.parse).filter(x=>x.kind===k&&(!s||x.source===s)).length}catch(e){}console.log(n)' "$1" "$2" "${3:-}"; }
last()  { node -e 'const fs=require("fs");const [p,k,s]=process.argv.slice(1);const r=fs.readFileSync(p,"utf8").split("\n").filter(Boolean).map(JSON.parse).filter(x=>x.kind===k&&(!s||x.source===s));console.log(r.length?JSON.stringify(r[r.length-1]):"null")' "$1" "$2" "${3:-}"; }
nlines() { printf '%s\n' "$1" | grep -c .; }
# table rows of one "## <name>" section of a report (header and separator rows excluded)
section_rows() { awk -v h="^## $2" '/^## /{on=($0 ~ h)} on && /^\|/ && !/^\|[ -:|]*\|?$/ {print}' "$1" | tail -n +2; }
# a query's stdout + its log row must agree: normalized rows, one summary line, hits/top/request/tier/ms on the row
cat > "$TMP/qcheck.js" <<'JS'
const fs = require('fs'); const [outF, logF, src, q] = process.argv.slice(2);
const lines = fs.readFileSync(outF, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch (e) { return { bad: l }; } });
const badLine = lines.find((l) => l.bad); if (badLine) { console.log('non-JSON stdout line: ' + badLine.bad); process.exit(1); }
const rows = lines.filter((l) => l.kind !== 'summary'); const sums = lines.filter((l) => l.kind === 'summary');
if (sums.length !== 1) { console.log('expected one summary line, got ' + sums.length); process.exit(1); }
const KEYS = 'desc,evidence,license,name,source,stars_or_downloads,updated,url';
for (const r of rows) {
  if (Object.keys(r).sort().join(',') !== KEYS) { console.log('row keys: ' + Object.keys(r).sort().join(',')); process.exit(1); }
  if (r.source !== src || r.evidence !== 'listed' || !/^https?:\/\//.test(r.url) || !r.name) { console.log('row shape: ' + JSON.stringify(r)); process.exit(1); }
}
const s = sums[0];
if (s.source !== src || s.hits !== rows.length || s.logged !== true || s.error) { console.log('summary: ' + JSON.stringify(s)); process.exit(1); }
if (!rows.length) { console.log('no rows printed'); process.exit(1); }
const log = fs.readFileSync(logF, 'utf8').split('\n').filter(Boolean).map(JSON.parse).filter((x) => x.kind === 'query' && x.source === src);
const row = log[log.length - 1]; if (!row) { console.log('no query row logged for ' + src); process.exit(1); }
const okReq = typeof row.request === 'string' && /^(GET https?:\/\/|gh )/.test(row.request);
if (row.hits !== rows.length || !Array.isArray(row.top) || row.top.length !== rows.length || !okReq || typeof row.tier !== 'number' || typeof row.ms !== 'number' || row.q !== q || row.error) { console.log('log row: ' + JSON.stringify(Object.assign({}, row, { top: row.top && row.top.length }))); process.exit(1); }
console.log(rows.length + ' rows, tier ' + row.tier + ', request ' + row.request.slice(0, 60));
JS
qcheck() { node "$TMP/qcheck.js" "$@"; }

echo "1. prompt outside plan mode -> silent, no session file"
r=$(run prompt "$(promptj t1 default 'add a rate limiter')")
[ "$r" = "exit=0" ] && ok "silent, exit 0" || bad "expected silence" "$r"
[ ! -e "$D/sessions/t1.json" ] && ok "no session file written" || bad "session file written outside plan mode" "$(ls "$D/sessions" 2>&1)"

echo "1b. non-object stdin (null, a string, an array) -> every hook exits 0 and logs no exception"
for body in 'null' '"x"' '[1,2]'; do for h in prompt gate enter receipt start; do r=$(run "$h" "$body"); echo "$r" | grep -q 'exit=0' || bad "$h with stdin $body" "$r"; done; done
[ ! -s "$DEJAVU_HOME/errors.log" ] && ok "null / string / array stdin: 5 hooks x 3 bodies exit 0, errors.log empty" || bad "non-object stdin logged an exception" "$(cat "$DEJAVU_HOME/errors.log")"

echo "2. prompt in plan mode -> one line naming AskUserQuestion and /dejavu; second call silent"
r=$(run prompt "$(promptj t1 plan 'add a rate limiter')")
echo "$r" | grep -q '"additionalContext"' && echo "$r" | grep -q 'AskUserQuestion' && echo "$r" | grep -q '/dejavu' && ok "offer names AskUserQuestion and /dejavu" || bad "expected the offer line" "$r"
echo "$r" | grep -q ' skip ' && ok "offer names the skip command" || bad "offer should name skip" "$r"
[ "$(nlines "$r")" -eq 2 ] && ok "exactly one line spoken" || bad "expected one JSON line plus the exit line" "$r"
[ "$(jget "$D/sessions/t1.json" offered)" = true ] && ok "session offered=true" || bad "offered not recorded" "$(cat "$D/sessions/t1.json" 2>&1)"
r=$(run prompt "$(promptj t1 plan 'now write the plan')")
[ "$r" = "exit=0" ] && ok "second prompt silent" || bad "second prompt must be silent" "$r"

echo "3. gate -> deny once with a reason naming /dejavu and skip; new tool_use_id -> allow; replayed id -> silent"
r=$(run gate "$(toolj t1 ExitPlanMode tu1)")
echo "$r" | grep -q '"permissionDecision":"deny"' && ok "denied" || bad "expected deny" "$r"
echo "$r" | grep -q '/dejavu' && echo "$r" | grep -q 'skip' && ok "reason names /dejavu and skip" || bad "reason incomplete" "$r"
[ "$(jget "$D/sessions/t1.json" gate_denied)" = true ] && ok "gate_denied recorded" || bad "gate_denied not recorded" "$(cat "$D/sessions/t1.json")"
r=$(run gate "$(toolj t1 ExitPlanMode tu2)")
[ "$r" = "exit=0" ] && ok "second ExitPlanMode allowed (silent): no loop" || bad "must deny only once per plan cycle" "$r"
r=$(run gate "$(toolj t1 ExitPlanMode tu1)")
[ "$r" = "exit=0" ] && ok "replayed tool_use_id silent" || bad "replay must be silent" "$r"
[ "$(jget "$D/sessions/t1.json" seen.g:tu1)" != "undefined" ] && ok "tool_use_id remembered in session.seen" || bad "seen{} lacks the id" "$(cat "$D/sessions/t1.json")"

echo "4. skip needs --user-said (else exit 1, gate stays closed); with it, a new session's plan-mode prompt and gate are silent"
# the offer and the gate reason show the exact skip form and say never to skip without the user's answer
r=$(run prompt "$(promptj t2x plan 'plan the limiter')")
echo "$r" | grep -q 'skip --user-said \\"<the user' && echo "$r" | grep -q "never skip without the user's answer" && ok "offer shows the --user-said skip form and forbids skipping without the user's answer" || bad "offer skip form" "$r"
r=$(run gate "$(toolj t2x ExitPlanMode tu2x0)")
echo "$r" | grep -q 'skip --user-said' && echo "$r" | grep -q "never skip without the user's answer" && ok "gate reason shows the --user-said skip form" || bad "gate skip form" "$r"
r=$(run enter "$(toolj t2x EnterPlanMode tu2x1)")   # re-arm t2x so the closed-gate check below sees a fresh deny
r=$(cli skip "the model decided on its own")
echo "$r" | grep -q 'exit=1' && echo "$r" | grep -q "a skip needs the user's answer; ask with AskUserQuestion, then pass --user-said" && ok "skip without --user-said exits 1 with the one-line reason" || bad "skip without --user-said" "$r"
[ ! -e "$D/pending-skip.json" ] && [ ! -e "$D/skips.jsonl" ] && ok "nothing recorded: no pending-skip.json, no skips.jsonl" || bad "a refused skip left files" "$(ls "$D" 2>&1)"
r=$(run gate "$(toolj t2x ExitPlanMode tu2x2)")
echo "$r" | grep -q '"permissionDecision":"deny"' && ok "gate stays closed after the refused skip" || bad "gate must still deny after a refused skip" "$r"
r=$(cli skip "user declined the check" --user-said "no, skip the check, I know this space")
echo "$r" | grep -q 'skip recorded (user said: "no, skip the check, I know this space"; reason: user declined the check)' && ok "skip with --user-said recorded, the user's words printed back" || bad "skip" "$r"
[ -f "$D/pending-skip.json" ] && [ "$(jget "$D/pending-skip.json" user_said)" = "no, skip the check, I know this space" ] && grep -q 'user declined' "$D/skips.jsonl" && grep -q '"user_said":"no, skip the check, I know this space"' "$D/skips.jsonl" && ok "pending-skip.json and skips.jsonl carry reason and user_said" || bad "skip files" "$(ls "$D" 2>&1; cat "$D/pending-skip.json" 2>&1)"
r=$(run prompt "$(promptj t2 plan 'plan the limiter')")
[ "$r" = "exit=0" ] && ok "new session: plan-mode prompt silent" || bad "prompt must be silent after a skip" "$r"
r=$(run gate "$(toolj t2 ExitPlanMode tu3)")
[ "$r" = "exit=0" ] && ok "new session: gate allows" || bad "gate must allow after a skip" "$r"
[ "$(jget "$D/sessions/t2.json" skip.reason)" = "user declined the check" ] && [ "$(jget "$D/sessions/t2.json" skip.user_said)" = "no, skip the check, I know this space" ] && ok "session file shows the skip with user_said" || bad "skip missing from session" "$(cat "$D/sessions/t2.json" 2>&1)"
[ ! -e "$D/pending-skip.json" ] && ok "pending-skip.json consumed" || bad "pending skip not consumed" "$(cat "$D/pending-skip.json")"

echo "5. enter on an unsatisfied session re-arms one offer and one deny"
r=$(run enter "$(toolj t1 EnterPlanMode tu4)")
[ "$r" = "exit=0" ] && ok "enter never prints" || bad "enter spoke" "$r"
[ "$(jget "$D/sessions/t1.json" offered)" = false ] && [ "$(jget "$D/sessions/t1.json" gate_denied)" = false ] && ok "offered and gate_denied reset" || bad "not reset" "$(cat "$D/sessions/t1.json")"
r=$(run prompt "$(promptj t1 plan 'second cycle')")
echo "$r" | grep -q 'AskUserQuestion' && ok "one more offer" || bad "expected a second offer" "$r"
r=$(run prompt "$(promptj t1 plan 'second cycle, again')")
[ "$r" = "exit=0" ] && ok "then silent" || bad "offer repeated" "$r"
r=$(run gate "$(toolj t1 ExitPlanMode tu5)")
echo "$r" | grep -q '"permissionDecision":"deny"' && ok "one more deny" || bad "expected a second deny" "$r"
r=$(run gate "$(toolj t1 ExitPlanMode tu6)")
[ "$r" = "exit=0" ] && ok "then allowed" || bad "denied twice in one cycle" "$r"
r=$(run enter "$(toolj t2 EnterPlanMode tu4b)"); r=$(run prompt "$(promptj t2 plan 'third cycle')")
[ "$r" = "exit=0" ] && ok "enter on a satisfied session (skip) does not re-arm" || bad "re-armed a satisfied session" "$r"

echo "6. invoke deep|frobnicate, open, frame write the expected files"
r=$(cli invoke frobnicate)
echo "$r" | grep -q 'depth default | budget 25 queries' && ok "non-depth word means default" || bad "invoke frobnicate" "$r"
r=$(cli invoke deep)
echo "$r" | grep -q 'depth deep | budget 40 queries | tiers required 0,1,2,3,4,5' && ok "invoke deep: depth, budget, tiers" || bad "invoke deep" "$r"
echo "$r" | grep -q 'languages javascript | project license MIT' && ok "languages and project license detected" || bad "detection" "$r"
echo "$r" | grep -q '^next: node "' && echo "$r" | grep -q 'open "<what you are about to build>" --depth deep' && ok "next command printed" || bad "next line" "$r"
[ "$(jget "$D/pending-invoke.json" depth)" = deep ] && ok "pending-invoke.json depth deep" || bad "pending-invoke" "$(cat "$D/pending-invoke.json" 2>&1)"
r=$(cli open "token bucket rate limiter")
echo "$r" | grep -q '^opened token-bucket-rate-limiter | depth deep | budget 40 queries' && ok "open derives the slug and takes the invoke depth" || bad "open" "$r"
SLUG=token-bucket-rate-limiter; LOG="$D/checks/$SLUG.jsonl"
[ "$(jget "$D/checks/$SLUG.json" status)" = open ] && [ "$(jget "$D/checks/$SLUG.json" depth)" = deep ] && [ "$(jget "$D/checks/$SLUG.json" topic)" = "token bucket rate limiter" ] && ok "check meta written" || bad "meta" "$(cat "$D/checks/$SLUG.json" 2>&1)"
[ "$(jget "$D/current.json" slug)" = "$SLUG" ] && [ "$(jget "$D/current.json" status)" = open ] && ok "current.json points at the open check" || bad "current.json" "$(cat "$D/current.json" 2>&1)"
[ ! -e "$D/pending-invoke.json" ] && ok "pending-invoke.json consumed" || bad "pending-invoke left behind" "$(cat "$D/pending-invoke.json")"
[ "$(count "$LOG" note)" -eq 1 ] && ok "opened note row in the log" || bad "log" "$(cat "$LOG" 2>&1)"
r=$(cli frame "$SLUG" "callers must not exceed N requests per second" "token bucket with refill" "rate limiter middleware" --syn "throttle,leaky bucket")
echo "$r" | grep -q '^framed token-bucket-rate-limiter' && ok "frame prints" || bad "frame" "$r"
[ "$(jget "$D/checks/$SLUG.json" framings.mechanism)" = "token bucket with refill" ] && [ "$(jget "$D/checks/$SLUG.json" framings.category)" = "rate limiter middleware" ] && ok "three framings recorded" || bad "framings" "$(cat "$D/checks/$SLUG.json")"
[ "$(jget "$D/checks/$SLUG.json" synonyms)" = '["throttle","leaky bucket"]' ] && ok "synonyms recorded" || bad "synonyms" "$(jget "$D/checks/$SLUG.json" synonyms)"
[ "$(count "$LOG" note)" -eq 2 ] && ok "framings note row" || bad "log" "$(cat "$LOG")"
r=$(cli frame "$SLUG" "only" "two"); echo "$r" | grep -q 'exit=1' && ok "frame with missing framings exits 1" || bad "frame should fail" "$r"
r=$(cli open); echo "$r" | grep -q 'exit=1' && ok "open without a topic exits 1" || bad "open should fail" "$r"
r=$(CLAUDE_PROJECT_DIR="$TMP/proj3" node "$ENGINE" open "a claude code skill that checks whether anyone has already built the thing" 2>&1)
echo "$r" | grep -q '^opened a-claude-code-skill-that-checks-whether-anyone-has-already |' && ok "a long topic's slug is cut at the last word boundary before 60 chars, not mid-word" || bad "slug cut" "$r"
r=$(cli frame "$SLUG" "callers must not exceed N requests per second" "token bucket with refill" "per key request rate limiting middleware for express")
echo "$r" | grep -q '^next: node "[^"]*" query gh-repos "per key request" --tier 1 --framing category' && ok "frame hint takes the first three words of the category, not the whole framing" || bad "frame hint" "$r"
cli frame "$SLUG" "callers must not exceed N requests per second" "token bucket with refill" "rate limiter middleware" --syn "throttle,leaky bucket" >/dev/null

echo "7. query for every source from fixtures -> normalized rows + log row with hits and request; query bogus -> exit 1"
Q="token bucket rate limiter"
for src in gh-repos gh-code gh-topics npm crates hn so openalex; do
  node "$ENGINE" query "$src" "$Q" --limit 20 --framing category --agent A > "$TMP/q.out" 2>"$TMP/err"; code=$?
  [ "$code" -eq 0 ] || { bad "query $src exit $code" "$(cat "$TMP/err")"; continue; }
  msg=$(qcheck "$TMP/q.out" "$LOG" "$src" "$Q") && ok "$src: $msg" || bad "$src rows/log disagree" "$msg"
done
req=$(jf "$(last "$LOG" query gh-repos)" request)
case "$req" in "gh search repos token bucket rate limiter --limit 20 --sort stars --order desc --json "*) ok "gh-repos: each word is a separate gh term (no exact-phrase quoting)";; *) bad "gh-repos request still quotes the query as one phrase" "$req";; esac
req=$(jf "$(last "$LOG" query gh-code)" request)
case "$req" in "gh search code token bucket rate limiter --limit 20 --json "*) ok "gh-code: each word is a separate gh term";; *) bad "gh-code request" "$req";; esac
[ "$(jf "$(last "$LOG" query npm)" framing)" = category ] && [ "$(jf "$(last "$LOG" query npm)" agent)" = A ] && ok "--framing and --agent land on the log row" || bad "framing/agent" "$(last "$LOG" query npm)"
[ "$(node -e 'const r=JSON.parse(process.argv[1]);console.log(r.top.some(t=>t.url==="https://github.com/express-rate-limit/express-rate-limit"))' "$(last "$LOG" query gh-repos)")" = true ] && ok "gh-repos top[] carries the express-rate-limit URL" || bad "express-rate-limit missing from top[]" "$(last "$LOG" query gh-repos | head -c 300)"
# gh-topics: fixtures/gh-topics.json is the `gh search repos --topic` camelCase array (parsed in the loop above); the REST
# shape {total_count, items[]} that `gh api search/repositories` and keyless api.github.com print must yield the same rows
camel=$(node -e 'console.log(JSON.parse(process.argv[1]).top.map(t=>t.name).join(","))' "$(last "$LOG" query gh-topics)")
mkdir -p "$TMP/fxrest"; cp "$FX/gh-topics-rest.json" "$TMP/fxrest/gh-topics.json"
DEJAVU_FIXTURES="$TMP/fxrest" node "$ENGINE" query gh-topics "$Q" --limit 20 --framing category --agent A > "$TMP/q.out" 2>"$TMP/err"; code=$?
msg=$(qcheck "$TMP/q.out" "$LOG" gh-topics "$Q") && ok "gh-topics REST shape (gh-topics-rest.json): $msg" || bad "gh-topics REST shape (exit $code)" "$msg $(cat "$TMP/err")"
rest=$(node -e 'console.log(JSON.parse(process.argv[1]).top.map(t=>t.name).join(","))' "$(last "$LOG" query gh-topics)")
[ -n "$camel" ] && [ "$camel" = "$rest" ] && ok "camelCase and REST gh-topics fixtures parse to the same repos ($camel)" || bad "gh-topics shapes disagree" "camel: $camel | rest: $rest"
r=$(cli query gh-repos '"token bucket" limiter' --limit 3 --since 2026-01-01 --sort updated)
req=$(jf "$(last "$LOG" query gh-repos)" request)
case "$req" in 'gh search repos "token bucket" limiter "pushed:>2026-01-01" --limit 3 --sort updated --order desc --json '*) ok "a caller-quoted phrase stays one term; pushed:> is its own term; --sort updated honoured";; *) bad "quoted phrase / --since / --sort" "$req";; esac
# pypi: the captured page is the JS client challenge pypi.org serves to non-browsers; the parser must yield an error row, not crash
r=$(cli query pypi "$Q" --limit 10)
echo "$r" | grep -q 'exit=0' && echo "$r" | grep -q '"kind":"summary","source":"pypi","hits":0,"logged":true,"error":"pypi search is behind a JS client challenge' && ok "pypi: challenge page -> error row, exit 0" || bad "pypi" "$r"
[ "$(jf "$(last "$LOG" query pypi)" hits)" = 0 ] && [ "$(jf "$(last "$LOG" query pypi)" error)" != "undefined" ] && ok "pypi error logged on the query row" || bad "pypi log row" "$(last "$LOG" query pypi)"
[ "$(jf "$(last "$LOG" query pypi)" request)" = "GET https://pypi.org/search/?q=token%20bucket%20rate%20limiter" ] && ok "errored pypi row carries the URL it attempted" || bad "pypi error request" "$(jf "$(last "$LOG" query pypi)" request)"
# arxiv: the real 429 body maps to a rate-limit error row; the happy path runs only once fixtures/arxiv.xml is captured
mkdir -p "$TMP/fx429"; cp "$FX/arxiv-ratelimited.txt" "$TMP/fx429/arxiv.xml"
r=$(DEJAVU_FIXTURES="$TMP/fx429" node "$ENGINE" query arxiv "$Q" --limit 5 2>&1; echo "exit=$?")
echo "$r" | grep -q 'exit=0' && echo "$r" | grep -q '"source":"arxiv","hits":0,"logged":true,"error":"arxiv rate-limited' && ok "arxiv: 429 body -> rate-limited error row, exit 0" || bad "arxiv 429" "$r"
case "$(jf "$(last "$LOG" query arxiv)" request)" in "GET https://export.arxiv.org/api/query?search_query=all%3Atoken%20AND%20all%3Abucket"*) ok "errored arxiv row carries the URL it attempted";; *) bad "arxiv error request" "$(last "$LOG" query arxiv)";; esac
if [ -f "$FX/arxiv.xml" ]; then
  node "$ENGINE" query arxiv "$Q" --limit 5 > "$TMP/q.out" 2>"$TMP/err"; code=$?
  msg=$(qcheck "$TMP/q.out" "$LOG" arxiv "$Q") && ok "arxiv: $msg" || bad "arxiv rows/log disagree (exit $code)" "$msg $(cat "$TMP/err")"
else
  echo "  skip arxiv happy path: fixtures/arxiv.xml not captured (arXiv answered 429 or 503 to every capture on 2026-09-13, last try 16:30 with a 10 s retry)"
fi
r=$(cli query bogus "x"); echo "$r" | grep -q 'exit=1' && echo "$r" | grep -q 'unknown source' && ok "query bogus exits 1" || bad "query bogus" "$r"
r=$(cli query npm); echo "$r" | grep -q 'exit=1' && ok "query without a string exits 1" || bad "query npm (no q)" "$r"
r=$(cli query hn "$Q" --since 2026-01-01 --limit 3); echo "$r" | grep -q 'exit=0' && [ "$(jf "$(last "$LOG" query hn)" since)" = 2026-01-01 ] && echo "$(last "$LOG" query hn)" | grep -q 'created_at_i>' && ok "--since recorded and applied to the request" || bad "--since" "$r"
r=$(cli bogus); echo "$r" | grep -q 'exit=1' && echo "$r" | grep -q '^usage:' && ok "unknown subcommand prints usage, exits 1" || bad "unknown subcommand" "$(echo "$r" | head -3)"

echo "7b. inspect and fetch from fixtures -> one row with evidence fetched; fetch + meta rows logged"
n0=$(count "$LOG" fetch); m0=$(count "$LOG" meta)
r=$(cli inspect express-rate-limit/express-rate-limit)
echo "$r" | grep -q '"name":"express-rate-limit/express-rate-limit","url":"https://github.com/express-rate-limit/express-rate-limit"' && echo "$r" | grep -q '"license":"MIT","source":"gh-repos","evidence":"fetched","archived":false' && ok "inspect github: license, health, evidence fetched, source gh-repos" || bad "inspect github" "$r"
[ "$(count "$LOG" fetch)" -eq $((n0+1)) ] && [ "$(count "$LOG" meta)" -eq $((m0+1)) ] && ok "fetch + meta rows logged" || bad "inspect rows" "$(tail -2 "$LOG")"
[ "$(jf "$(last "$LOG" fetch)" target)" = "express-rate-limit/express-rate-limit" ] && [ "$(jf "$(last "$LOG" fetch)" via)" = inspect ] && ok "inspect's fetch row records the target as typed (the claim receipt)" || bad "inspect target" "$(last "$LOG" fetch)"
r=$(cli inspect npm:express-rate-limit)
echo "$r" | grep -q '"name":"express-rate-limit","url":"https://www.npmjs.com/package/express-rate-limit"' && echo "$r" | grep -q '"stars_or_downloads":225416514' && ok "inspect npm: packument + downloads" || bad "inspect npm" "$r"
r=$(cli inspect crate:governor)
echo "$r" | grep -q '"name":"governor","url":"https://crates.io/crates/governor"' && echo "$r" | grep -q '"evidence":"fetched"' && ok "inspect crates" || bad "inspect crates" "$r"
r=$(cli inspect pypi:token-bucket)
echo "$r" | grep -q '"name":"token-bucket","url":"https://pypi.org/project/token-bucket/"' && echo "$r" | grep -q '"updated":"2026-06-12","license":"Apache-2.0","source":"pypi","evidence":"fetched"' && ok "inspect pypi: JSON API row, license from license_expression, last upload date" || bad "inspect pypi" "$r"
r=$(cli fetch https://example.com/)
echo "$r" | grep -q '^fetched https://example.com/ | status 200 | 559 bytes | title: Example Domain | logged: token-bucket-rate-limiter$' && ok "fetch: title and size, logged" || bad "fetch" "$(echo "$r" | head -2)"
r=$(cli fetch https://github.com/express-rate-limit/express-rate-limit)
echo "$r" | grep -q '^fetched https://github.com/express-rate-limit/express-rate-limit | status 200 | 8744 bytes | title: express-rate-limit/express-rate-limit | logged: token-bucket-rate-limiter | read via gh api repos/express-rate-limit/express-rate-limit/readme$' && ok "fetch of a github.com repo URL reads the README through the contents API; the title falls back to the repo name" || bad "github fetch route" "$(echo "$r" | head -1)"
row=$(last "$LOG" fetch)
[ "$(jf "$row" url)" = "https://github.com/express-rate-limit/express-rate-limit" ] && [ "$(jf "$row" request)" = "gh api repos/express-rate-limit/express-rate-limit/readme" ] && [ "$(jf "$row" final_url)" = undefined ] && ok "fetch row keeps the URL as typed and records the README route in request" || bad "fetch row" "$row"
echo "$r" | sed -n '2,3p' | grep -q 'express-rate-limit' && ok "README text starts on line 2 of the output (no navigation chrome)" || bad "body" "$(echo "$r" | sed -n '2,5p')"
r=$(cli fetch "https://github.com/express-rate-limit/express-rate-limit/blob/main/readme.md")
echo "$r" | grep -q '| title: express-rate-limit/express-rate-limit/readme.md | logged: token-bucket-rate-limiter | read via GET https://raw.githubusercontent.com/express-rate-limit/express-rate-limit/main/readme.md$' && ok "a blob URL is read raw" || bad "blob route" "$(echo "$r" | head -1)"
r=$(cli fetch "https://github.com/topics/rate-limiter"); echo "$r" | grep -q '| title: Example Domain | logged: token-bucket-rate-limiter$' && ok "a github.com page that is not a repo is fetched as a page" || bad "non-repo github url" "$(echo "$r" | head -1)"
r=$(cli fetch notaurl); echo "$r" | grep -q 'exit=1' && ok "fetch without a url exits 1" || bad "fetch notaurl" "$r"

echo "8. log finding evidence tagging: fixture top[] URL -> listed; unknown URL -> recalled; missing URL -> exit 1"
r=$(cli log finding "limiter" "https://www.npmjs.com/package/limiter" --closeness 3 --reusable "token bucket class" --source npm)
echo "$r" | grep -q 'finding logged: limiter | closeness 3 | evidence listed' && ok "URL in a fixture top[] -> listed" || bad "listed" "$r"
[ "$(jf "$(last "$LOG" finding)" evidence)" = listed ] && [ "$(jf "$(last "$LOG" finding)" reusable)" = "token bucket class" ] && ok "finding row carries evidence and reusable" || bad "finding row" "$(last "$LOG" finding)"
r=$(cli log finding "ratelimiter" "https://github.com/RussellLuo/ratelimiter/blob/master/README.md" --closeness 2)
echo "$r" | grep -q 'evidence listed' && ok "a blob URL of a listed repo -> listed (URL normalized)" || bad "normalization" "$r"
r=$(cli log finding "express-rate-limit" "https://github.com/express-rate-limit/express-rate-limit/" --closeness 5 --reusable "whole middleware")
echo "$r" | grep -q 'closeness 5 | evidence fetched' && ok "inspected URL -> fetched" || bad "fetched" "$r"
r=$(cli log finding "remembered-lib" "https://github.com/nobody/remembered-lib" --closeness 5)
echo "$r" | grep -q 'evidence recalled' && echo "$r" | grep -q 'recalled is not evidence' && ok "unknown URL -> recalled, with the instruction to inspect it" || bad "recalled" "$r"
r=$(cli log finding "no-url" --closeness 2); echo "$r" | grep -q 'exit=1' && ok "missing URL -> exit 1" || bad "missing url" "$r"
r=$(cli log finding "bad-url" "not a url" --closeness 2); echo "$r" | grep -q 'exit=1' && ok "non-http URL -> exit 1" || bad "bad url" "$r"
r=$(cli log finding "x" "https://github.com/nobody/x" --closeness 9); echo "$r" | grep -q 'closeness 5' && ok "closeness clamped to 1-5" || bad "clamp" "$r"
r=$(cli log query grep 0 2 "x" --slug nope); echo "$r" | grep -q 'exit=1' && echo "$r" | grep -q 'no check nope' && [ ! -e "$D/checks/nope.jsonl" ] && ok "log --slug of a check that was never opened exits 1 and writes no stray log" || bad "log --slug nope" "$r $(ls "$D/checks")"
r=$(cli query npm "x" --slug nope); echo "$r" | grep -q 'exit=1' && [ ! -e "$D/checks/nope.jsonl" ] && ok "query --slug nope exits 1 before any network call" || bad "query --slug nope" "$r"
r=$(cli log query grep 0 2 "git log -S x" --slug "$SLUG"); echo "$r" | grep -q 'query logged: grep tier 0 hits 2' && ok "log --slug of an existing check works" || bad "log --slug existing" "$r"

echo "9. receipt with an open check logs WebFetch / WebSearch rows, dedupes by id, writes nothing with no open check"
n0=$(count "$LOG" fetch)
r=$(run receipt "$(receiptj t1 WebFetch wf1 '{"url":"https://github.com/animir/node-rate-limiter-flexible"}' '{"code":200,"url":"https://github.com/animir/node-rate-limiter-flexible"}')")
[ "$r" = "exit=0" ] && ok "receipt never prints" || bad "receipt spoke" "$r"
[ "$(count "$LOG" fetch)" -eq $((n0+1)) ] && [ "$(jf "$(last "$LOG" fetch)" via)" = WebFetch ] && [ "$(jf "$(last "$LOG" fetch)" url)" = "https://github.com/animir/node-rate-limiter-flexible" ] && ok "WebFetch -> fetch row" || bad "fetch row" "$(last "$LOG" fetch)"
r=$(run receipt "$(receiptj t1 WebFetch wf1 '{"url":"https://github.com/animir/node-rate-limiter-flexible"}' '{}')")
[ "$(count "$LOG" fetch)" -eq $((n0+1)) ] && ok "replayed tool_use_id not logged twice" || bad "duplicate fetch row" "$(count "$LOG" fetch)"
q0=$(count "$LOG" query websearch)
WSR='{"query":"token bucket rate limiter alternatives","results":[{"tool_use_id":"srv1","content":[{"title":"bottleneck - npm","url":"https://www.npmjs.com/package/bottleneck"},{"title":"node-rate-limiter","url":"https://github.com/jhurliman/node-rate-limiter"}]},"Links: [alternatives](https://alternativeto.net/software/express-rate-limit/) and again https://www.npmjs.com/package/bottleneck"],"durationSeconds":1.2}'
r=$(run receipt "$(receiptj t1 WebSearch ws1 '{"query":"token bucket rate limiter alternatives"}' "$WSR")")
[ "$r" = "exit=0" ] && [ "$(count "$LOG" query websearch)" -eq $((q0+1)) ] && ok "WebSearch -> query row" || bad "websearch row" "$r $(last "$LOG" query websearch)"
row=$(last "$LOG" query websearch)
[ "$(jf "$row" tier)" = 5 ] && [ "$(jf "$row" hits)" = 3 ] && [ "$(jf "$row" request)" = WebSearch ] && echo "$row" | grep -q 'alternativeto.net' && ok "row: source websearch, tier 5, 3 deduplicated urls in top[], request WebSearch" || bad "websearch row fields" "$row"
r=$(run receipt "$(receiptj t1 WebSearch ws1 '{"query":"token bucket rate limiter alternatives"}' "$WSR")")
[ "$(count "$LOG" query websearch)" -eq $((q0+1)) ] && ok "replayed WebSearch id not logged twice" || bad "duplicate websearch row" "$(count "$LOG" query websearch)"
r=$(cli log finding "bottleneck" "https://www.npmjs.com/package/bottleneck" --closeness 3)
echo "$r" | grep -q 'evidence listed' && ok "a URL the WebSearch receipt saw counts as listed" || bad "websearch listed" "$r"
r=$(run receipt "$(receiptj t1 WebSearch ws2 '{"query":"rate limiter site:github.com"}' '{"results":[]}')")
[ "$(jf "$(last "$LOG" query websearch)" tier)" = 1 ] && ok "site:github.com search guessed as tier 1" || bad "tier guess" "$(last "$LOG" query websearch)"
r=$(CLAUDE_PROJECT_DIR="$TMP/proj2" run receipt "$(receiptj t7 WebFetch wf9 '{"url":"https://example.com/"}' '{}')")
[ "$r" = "exit=0" ] && [ ! -e "$TMP/proj2/.dejavu" ] && ok "no open check: nothing written at all" || bad "wrote without an open check" "$r $(ls -a "$TMP/proj2")"

echo "10. report from fixtures/log.jsonl: sections, search-log count, verdict validation, --no-docs, publish"
cli open "fx" >/dev/null
cp "$FX/log.jsonl" "$D/checks/fx.jsonl"; cp "$FX/log.meta.json" "$D/checks/fx.json"
# derived logs: fx-recalled drops the fetched closeness-5 finding; fx-gap keeps tiers 0-2 and the recalled finding; fx-novel keeps no finding, depth quick
node -e '
const fs=require("fs");const [dir,fx]=process.argv.slice(1);
const rows=fs.readFileSync(dir+"/fx.jsonl","utf8").split("\n").filter(Boolean).map(JSON.parse);
const meta=JSON.parse(fs.readFileSync(fx+"/log.meta.json","utf8"));
const w=(slug,rs,depth)=>{fs.writeFileSync(dir+"/"+slug+".jsonl",rs.map(r=>JSON.stringify(r)).join("\n")+"\n");fs.writeFileSync(dir+"/"+slug+".json",JSON.stringify(Object.assign({},meta,{slug,depth:depth||meta.depth}),null,2));};
w("fx-recalled",rows.filter(r=>!(r.kind==="finding"&&/express-rate-limit/.test(r.url))));
w("fx-gap",rows.filter(r=>r.kind==="note"||(r.kind==="query"&&r.tier<=2)||(r.kind==="finding"&&r.evidence==="recalled")));
w("fx-novel",rows.filter(r=>r.kind!=="finding"),"quick");
// fx-fetchonly adds an engine fetch (no inspect) of the recalled URL, a WebFetch of another URL plus a finding on it; fx-gap0 drops only tier 0 (quick)
const efetch={kind:"fetch",ts:1789294450000,url:"https://github.com/animir/node-rate-limiter-flexible",request:"gh api repos/animir/node-rate-limiter-flexible/readme",status:200,title:"animir/node-rate-limiter-flexible",bytes:5000,ms:1,via:"engine"};
const wfetch={kind:"fetch",ts:1789294460000,url:"https://github.com/SGrondin/bottleneck",via:"WebFetch",session:"s1"};
const bfind={kind:"finding",ts:1789294700000,name:"bottleneck",url:"https://github.com/SGrondin/bottleneck",closeness:4,reusable:"the scheduler",license:null,updated:null,stars_or_downloads:null,source:null,framing:null,desc:null,evidence:"recalled"};
w("fx-fetchonly",rows.concat([efetch,wfetch,bfind]));
w("fx-gap0",rows.filter(r=>r.kind!=="finding"&&!(r.kind==="query"&&r.tier===0)),"quick");
' "$D/checks" "$FX"
NQ=$(count "$D/checks/fx.jsonl" query)
r=$(cli report fx --verdict EXISTS --recommend adopt --summary "express-rate-limit covers the need" --cost "a week of rework")
echo "$r" | grep -qx 'verdict: EXISTS' && ok "EXISTS with a fetched closeness-5 finding stands" || bad "report fx" "$r"
echo "$r" | grep -q '^report: .dejavu/checks/fx.md and docs/dejavu/fx.md' && ok "both paths printed" || bad "paths" "$r"
[ -f "$D/checks/fx.md" ] && [ -f "$DOCS/fx.md" ] && cmp -s "$D/checks/fx.md" "$DOCS/fx.md" && ok "canonical and docs copies identical" || bad "report files" "$(ls "$D/checks" "$DOCS" 2>&1)"
MD="$DOCS/fx.md"; missing=""
for h in "Verdict" "Framings" "Closest matches" "Recommendation" "Reusable parts" "License compatibility" "Search log" "Fetched" "Recalled, not fetched" "Coverage" "Decision" "Re-check"; do grep -q "^## $h" "$MD" || missing="$missing [$h]"; done
[ -z "$missing" ] && ok "all 12 sections present" || bad "sections missing" "$missing"
head -1 "$MD" | grep -q '^# dejavu: token bucket rate limiter for an Express API' && grep -q '^\- \*\*Depth:\*\* default (10 of 25 queries used)' "$MD" && ok "title, topic, depth and budget header" || bad "header" "$(head -8 "$MD")"
n=$(section_rows "$MD" "Search log" | grep -c .)
[ "$n" -eq "$NQ" ] && ok "search log has $n rows = $NQ query rows in the log" || bad "search log rows $n != $NQ" "$(section_rows "$MD" "Search log" | head -3)"
section_rows "$MD" "Search log" | grep -q '| self | git log -S' && section_rows "$MD" "Search log" | grep -q '| websearch |' && section_rows "$MD" "Search log" | grep -q '| error: arxiv rate-limited' && ok "search log carries self, websearch and the errored arxiv query" || bad "search log content" "$(section_rows "$MD" "Search log")"
section_rows "$MD" "Search log" | grep -q '| 2026-09-13 10:02 UTC | lead |' && ok "search log 'When' is stamped UTC" || bad "when column" "$(section_rows "$MD" "Search log" | head -2)"
m=$(section_rows "$MD" "Closest matches")
[ "$(nlines "$m")" -eq 2 ] && echo "$m" | grep -q '| express-rate-limit | https://github.com/express-rate-limit/express-rate-limit | MIT | 2026-09-07 | 3305 | 5 | fetched |' && echo "$m" | grep -q '| limiter | https://www.npmjs.com/package/limiter | .* | 3 | listed |' && ok "closest matches: the fetched and the listed finding only, with license and activity from the inspect" || bad "closest matches" "$m"
section_rows "$MD" "Recalled, not fetched" | grep -q '| rate-limiter-flexible | https://github.com/animir/node-rate-limiter-flexible | 5 |' && ok "recalled finding listed apart, not counted" || bad "recalled section" "$(section_rows "$MD" "Recalled, not fetched")"
grep -q '^Engine check: dejavu check: verdict EXISTS (as claimed) | findings 3 (fetched 1, listed 1, recalled 1) | queries 10 + 2 errored of 25 | tiers covered 0,1,2,3,4,5$' "$MD" && ok "engine check line" || bad "engine check line" "$(grep 'Engine check' "$MD")"
grep -q '^\- Tiers required: 0, 1, 2, 3, 4, 5; covered: 0, 1, 2, 3, 4, 5; missing: none$' "$MD" && grep -q '^\- Errors and rate limits: .*pypi.*arxiv rate-limited' "$MD" && ok "coverage: tiers and the two source errors" || bad "coverage" "$(sed -n '/^## Coverage/,/^## Decision/p' "$MD")"
section_rows "$MD" "License compatibility" | grep -q '| express-rate-limit | MIT | ok (permissive) |' && ok "license compatibility row" || bad "license table" "$(section_rows "$MD" "License compatibility")"
grep -q '^| https://github.com/express-rate-limit/express-rate-limit | express-rate-limit/express-rate-limit | .* | inspect |' "$MD" && ok "fetched table lists the inspect once" || bad "fetched table" "$(section_rows "$MD" "Fetched")"
echo "$r" | grep -q '^CLAIM: dejavu report fx written with verdict EXISTS | RECEIPT: file:docs/dejavu/fx.md | WAGER: 100$' && echo "$r" | grep -q '| RECEIPT: cmd:dejavu.js inspect https://github.com/express-rate-limit/express-rate-limit | WAGER: 100$' && echo "$r" | grep -q '^CLAIM: NOT VERIFIED - arxiv ' && ok "claim lines: file receipt, inspect receipt, NOT VERIFIED for the errored source" || bad "claims" "$r"
[ "$(jget "$D/checks/fx.json" status)" = reported ] && [ "$(jget "$D/checks/fx.json" verdict)" = EXISTS ] && [ "$(jget "$D/checks/fx.json" recommend)" = adopt ] && [ "$(jget "$D/current.json" status)" = reported ] && ok "meta reported, current.json closed" || bad "state after report" "$(cat "$D/checks/fx.json" "$D/current.json")"
r=$(cli report fx-recalled --verdict EXISTS --recommend adopt --summary "from memory" --no-docs)
echo "$r" | grep -q '^verdict: PARTIAL (downgraded from EXISTS) — EXISTS needs a finding with closeness >= 4 and evidence fetched' && ok "closeness-5 recalled + EXISTS -> PARTIAL with the reason" || bad "downgrade to PARTIAL" "$r"
[ -f "$D/checks/fx-recalled.md" ] && [ ! -e "$DOCS/fx-recalled.md" ] && ok "--no-docs writes only the canonical copy" || bad "--no-docs" "$(ls "$D/checks" "$DOCS")"
echo "$r" | grep -q 'canonical only; publish with: node "' && ok "report names the publish command" || bad "publish hint" "$r"
grep -q '^\- Downgrade: EXISTS needs' "$D/checks/fx-recalled.md" && ok "downgrade reason written into the report" || bad "downgrade in md" "$(grep -n Downgrade "$D/checks/fx-recalled.md")"
r=$(cli publish fx-recalled)
echo "$r" | grep -q '^published docs/dejavu/fx-recalled.md' && cmp -s "$D/checks/fx-recalled.md" "$DOCS/fx-recalled.md" && ok "publish copies the canonical report" || bad "publish" "$r"
r=$(cli report fx-gap --verdict NOVEL --recommend build --summary "nothing found")
echo "$r" | grep -q '^verdict: UNKNOWN (downgraded from NOVEL)' && echo "$r" | grep -q 'tiers not covered: 3, 4, 5' && ok "NOVEL with tier gaps -> UNKNOWN naming the tiers" || bad "NOVEL gap" "$r"
echo "$r" | grep -q '^CLAIM: NOT VERIFIED - tiers 3, 4, 5 were not searched$' && ok "NOT VERIFIED claim names the tiers" || bad "tiers claim" "$r"
r=$(cli report fx-novel --verdict NOVEL --recommend build --summary "no candidate at quick depth")
echo "$r" | grep -qx 'verdict: NOVEL' && ok "NOVEL stands when every required tier is covered and half the budget is spent" || bad "NOVEL quick" "$r"
r=$(cli report fx-fetchonly --verdict EXISTS --recommend adopt --summary "x" --no-docs)
echo "$r" | grep -q '^CLAIM: rate-limiter-flexible fetched (animir/node-rate-limiter-flexible) closeness 5 | RECEIPT: cmd:dejavu.js fetch https://github.com/animir/node-rate-limiter-flexible | WAGER: 100$' && ok "a finding the engine only fetched claims with the fetch receipt" || bad "fetch claim" "$r"
echo "$r" | grep -q 'rate-limiter-flexible inspected' && bad "fetch-only finding claimed an inspect that never ran" "$r" || ok "no inspect receipt for a command that never ran"
echo "$r" | grep -q '^CLAIM: bottleneck' && bad "WebFetch-only finding got an engine receipt" "$r" || ok "a WebFetch-only finding gets no engine claim line (the model holds that receipt)"
echo "$r" | grep -q '^CLAIM: express-rate-limit inspected: license MIT, last activity 2026-09-07, closeness 5 | RECEIPT: cmd:dejavu.js inspect https://github.com/express-rate-limit/express-rate-limit | WAGER: 100$' && ok "an inspected finding still claims with the inspect receipt" || bad "inspect claim" "$r"
section_rows "$D/checks/fx-fetchonly.md" "Closest matches" | grep -q '| bottleneck | https://github.com/SGrondin/bottleneck | .* | 4 | fetched |' && ok "the WebFetch row still makes that finding fetched in the table" || bad "bottleneck evidence" "$(section_rows "$D/checks/fx-fetchonly.md" "Closest matches")"
r=$(cli report fx-gap0 --verdict NOVEL --recommend build --summary "nothing found" --no-docs)
echo "$r" | grep -q 'tiers not covered: 0' && echo "$r" | grep -q '^CLAIM: NOT VERIFIED - tier 0 was not searched$' && ok "one missing tier reads 'tier 0 was not searched'" || bad "tier 0 wording" "$r"
r=$(cli report fx --verdict BOGUS --recommend build --summary "x"); echo "$r" | grep -q 'exit=1' && ok "bad --verdict exits 1" || bad "verdict validation" "$r"
r=$(cli report fx --verdict UNKNOWN --recommend nope --summary "x"); echo "$r" | grep -q 'exit=1' && ok "bad --recommend exits 1" || bad "recommend validation" "$r"
r=$(cli report fx --verdict UNKNOWN --recommend build); echo "$r" | grep -q 'exit=1' && ok "missing --summary exits 1" || bad "summary required" "$r"
r=$(cli publish nothing-here); echo "$r" | grep -q 'exit=1' && ok "publish of an unreported slug exits 1" || bad "publish nothing" "$r"

echo "11. after report, a new session's gate adopts current.json and allows"
[ "$(jget "$D/current.json" slug)" = fx ] && [ "$(jget "$D/current.json" adopted_by)" = null ] && ok "current.json: fx, reported, not yet adopted" || bad "current.json" "$(cat "$D/current.json")"
r=$(run gate "$(toolj t3 ExitPlanMode tu8)")
[ "$r" = "exit=0" ] && ok "gate allows (silent)" || bad "gate should allow after a report" "$r"
[ "$(jget "$D/sessions/t3.json" checks)" = '["fx"]' ] && [ "$(jget "$D/current.json" adopted_by)" = t3 ] && ok "session adopted the check; adopted_by stamped" || bad "adoption" "$(cat "$D/sessions/t3.json" "$D/current.json")"
r=$(run prompt "$(promptj t3 plan 'now the plan')")
[ "$r" = "exit=0" ] && ok "plan-mode prompt silent once satisfied" || bad "prompt spoke after a report" "$r"

echo "12. start prints the count with reports present, nothing at 0; status lists them"
r=$(CLAUDE_PROJECT_DIR="$TMP/proj2" run start "$(startj t9)")
[ "$r" = "exit=0" ] && ok "0 reports: silent" || bad "start should be silent at 0" "$r"
NR=$(ls "$DOCS"/*.md | wc -l | tr -d ' ')
r=$(run start "$(startj t3)")
echo "$r" | grep -q "\"additionalContext\":\"dejavu: $NR reports on file, latest fx-[a-z]* [A-Z]* 20[0-9-]* (docs/dejavu/; recheck: node " && ok "start: '$NR reports on file, latest <slug> <verdict> <date>'" || bad "start line" "$r"
r=$(cli status)
echo "$r" | grep -q "^reports on file: $NR$" && [ "$(echo "$r" | grep -c '^  fx')" -eq "$NR" ] && ok "status lists the $NR reports" || bad "status reports" "$r"
echo "$r" | grep -q '^open check: none | last check: fx (reported) | depth default' && echo "$r" | grep -q '^unreported checks: token-bucket-rate-limiter$' && ok "status: a closed current.json reads 'last check: fx (reported)'; the unreported one is listed" || bad "status checks" "$r"
echo "$r" | grep -q '^session: none (CLAUDE_SESSION_ID unset); [0-9]* session files' && ok "status: session line without an id" || bad "status session" "$r"

echo "13. recheck with a recheck fixture prints only the new hits and appends the section"
mkdir -p "$TMP/fxr"; cp "$FX"/*.json "$FX"/*.html "$TMP/fxr/"; cp "$FX"/recheck/*.json "$TMP/fxr/"; cp "$FX/arxiv-ratelimited.txt" "$TMP/fxr/arxiv.xml"
r=$(DEJAVU_FIXTURES="$TMP/fxr" node "$ENGINE" recheck fx 2>"$TMP/err"; echo "exit=$?")
echo "$r" | grep -q 'exit=0' || bad "recheck exit" "$r $(cat "$TMP/err")"
new=$(echo "$r" | grep '"new_since"')
[ "$(nlines "$new")" -eq 2 ] && echo "$new" | grep -q '"name":"zz-new-since-report","url":"https://www.npmjs.com/package/zz-new-since-report"' && echo "$new" | grep -q '"name":"zz-new/zz-new-since-report","url":"https://github.com/zz-new/zz-new-since-report"' && ok "exactly the two fabricated new hits printed (npm, gh-repos)" || bad "new hits" "$new"
[ "$(echo "$r" | grep -c '"evidence":"listed"')" -eq 2 ] && ok "no already-known row printed" || bad "known rows re-printed" "$(echo "$r" | grep '"evidence"' | head -3)"
echo "$r" | grep -q '"kind":"recheck","slug":"fx","since":"'"$(date -u +%Y-%m-%d)"'","new":2,"reran":10,"manual":2' && ok "summary: 10 engine queries re-run, 2 manual (self, websearch)" || bad "recheck summary" "$(echo "$r" | tail -1)"
[ "$(echo "$r" | grep -c '"kind":"manual"')" -eq 2 ] && echo "$r" | grep -q '"kind":"manual","source":"self"' && echo "$r" | grep -q '"kind":"manual","source":"websearch"' && ok "manual re-run lines for self and websearch" || bad "manual lines" "$(echo "$r" | grep manual)"
echo "$r" | grep -q '"source":"arxiv","hits":0,"logged":true,"error":"arxiv rate-limited' && ok "errored query re-run and still errored: reported, not hidden" || bad "arxiv recheck" "$(echo "$r" | grep arxiv)"
[ "$(count "$D/checks/fx.jsonl" recheck)" -eq 10 ] && ok "10 recheck rows appended to the log" || bad "recheck rows" "$(count "$D/checks/fx.jsonl" recheck)"
for p in "$D/checks/fx.md" "$DOCS/fx.md"; do
  grep -q "^## Re-check $(date -u +%Y-%m-%d)$" "$p" && grep -q '^Since .*: 2 new hits across 10 re-run queries\.$' "$p" && grep -q '| npm | token bucket rate limiter | zz-new-since-report |' "$p" && grep -q '^Re-run by hand: self "git log' "$p" && ok "section appended to ${p#$CLAUDE_PROJECT_DIR/}" || bad "recheck section" "$(tail -12 "$p")"
done
r=$(cli recheck token-bucket-rate-limiter); echo "$r" | grep -q 'exit=1' && ok "recheck of an unreported check exits 1" || bad "recheck open check" "$r"

echo "14. DEJAVU_OFFLINE=1: all five hook subcommands succeed; query logs an error row, exit 0"
cli open "offline probe" >/dev/null
export DEJAVU_OFFLINE=1; SAVED_FX="$DEJAVU_FIXTURES"; unset DEJAVU_FIXTURES
r=$(run start "$(startj t4)"); echo "$r" | grep -q 'exit=0' && ok "start ok offline" || bad "start" "$r"
r=$(run prompt "$(promptj t4 plan 'offline plan')"); echo "$r" | grep -q 'exit=0' && echo "$r" | grep -q 'AskUserQuestion' && ok "prompt ok offline (offers)" || bad "prompt" "$r"
r=$(run gate "$(toolj t4 ExitPlanMode tu10)"); echo "$r" | grep -q 'exit=0' && echo "$r" | grep -q '"permissionDecision":"deny"' && ok "gate ok offline (denies)" || bad "gate" "$r"
r=$(run enter "$(toolj t4 EnterPlanMode tu11)"); [ "$r" = "exit=0" ] && ok "enter ok offline" || bad "enter" "$r"
r=$(run receipt "$(receiptj t4 WebFetch wf20 '{"url":"https://example.com/"}' '{}')"); [ "$r" = "exit=0" ] && [ "$(jf "$(last "$D/checks/offline-probe.jsonl" fetch)" url)" = "https://example.com/" ] && ok "receipt ok offline (logged)" || bad "receipt" "$r"
r=$(cli query npm "token bucket")
echo "$r" | grep -q 'exit=0' && echo "$r" | grep -q '"kind":"summary","source":"npm","hits":0,"logged":true,"error":"DEJAVU_OFFLINE=1: network disabled"' && ok "query: error row, exit 0" || bad "offline query" "$r"
[ "$(jf "$(last "$D/checks/offline-probe.jsonl" query npm)" error)" = "DEJAVU_OFFLINE=1: network disabled" ] && ok "error recorded on the query row" || bad "offline log row" "$(last "$D/checks/offline-probe.jsonl" query npm)"
[ "$(jf "$(last "$D/checks/offline-probe.jsonl" query npm)" request)" = "GET https://registry.npmjs.org/-/v1/search?text=token%20bucket&size=10" ] && ok "errored row carries the request it attempted (not '<source> <q>')" || bad "offline request" "$(last "$D/checks/offline-probe.jsonl" query npm)"
r=$(cli query gh-repos "token bucket"); echo "$r" | grep -q 'exit=0' && echo "$r" | grep -q '"error":"DEJAVU_OFFLINE=1: network disabled"' && ok "gh is never spawned offline" || bad "offline gh" "$r"
case "$(jf "$(last "$D/checks/offline-probe.jsonl" query gh-repos)" request)" in "gh search repos token bucket --limit 10 --sort stars --order desc --json "*) ok "errored gh-repos row carries the gh command line";; *) bad "offline gh request" "$(last "$D/checks/offline-probe.jsonl" query gh-repos)";; esac
r=$(cli inspect npm:limiter); echo "$r" | grep -q 'exit=0' && echo "$r" | grep -q '"source":"inspect","hits":0,"logged":true,"error":"DEJAVU_OFFLINE=1' && ok "inspect: error summary, exit 0" || bad "offline inspect" "$r"
unset DEJAVU_OFFLINE; export DEJAVU_FIXTURES="$SAVED_FX"

echo "15. hook latency"
t0=$(date +%s%N); run gate "$(toolj t1 ExitPlanMode "$(nid)")" >/dev/null; t1=$(date +%s%N)
ms=$(( (t1 - t0) / 1000000 )); [ "$ms" -lt 400 ] && ok "gate hook ${ms}ms wall" || bad "gate hook slow" "${ms}ms"
t0=$(date +%s%N); run receipt "$(receiptj t1 WebFetch "$(nid)" '{"url":"https://example.com/"}' '{}')" >/dev/null; t1=$(date +%s%N)
ms=$(( (t1 - t0) / 1000000 )); [ "$ms" -lt 400 ] && ok "receipt hook ${ms}ms wall" || bad "receipt hook slow" "${ms}ms"
avg=$(node -e 'const s=require(process.argv[1]);console.log((s.hooks_ms/s.hooks_n).toFixed(1))' "$D/sessions/t1.json")
echo "  info t1 hooks in-process avg ${avg}ms over $(jget "$D/sessions/t1.json" hooks_n) calls"

echo "16. no engine exception was logged during the battery"
[ ! -s "$DEJAVU_HOME/errors.log" ] && ok "errors.log empty" || bad "errors.log has entries" "$(cat "$DEJAVU_HOME/errors.log")"

echo; echo "passed $pass failed $fail"; rm -rf "$TMP"; [ "$fail" -eq 0 ]
