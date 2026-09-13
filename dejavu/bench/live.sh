#!/usr/bin/env bash
# dejavu live bench: real endpoints and real `claude -p` runs (nothing here is mocked).
#   bash dejavu/bench/live.sh endpoints          # every engine source once + three `inspect` calls; source/hits/ms/error table
#   bash dejavu/bench/live.sh invoke [model]     # `/dejavu quick …` in a throwaway Node project; asserts the committed report
#   bash dejavu/bench/live.sh planmode [model]   # `--permission-mode plan`; asserts the offer and the ExitPlanMode gate
# Exit status: endpoints -> non-zero on any error that is not a rate limit; invoke/planmode -> non-zero on a failed assertion.
# Written against the CLI contract in docs/PLAN.md (open / query / inspect / report, .dejavu/ state files). Lines marked
# "ENGINE CONTRACT" name the engine behaviour (scripts/dejavu.js, section names from log/SCHEMA.md) an assertion depends on.
set -u
MODE="${1:-endpoints}"; MODEL="${2:-sonnet}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"; command -v cygpath >/dev/null 2>&1 && PLUGIN="$(cygpath -m "$PLUGIN")"
ENGINE="$PLUGIN/scripts/dejavu.js"
OUT="$HERE/results"; mkdir -p "$OUT"; STAMP="$(date +%Y%m%d-%H%M%S)-live-$MODE"
QUERY="token bucket rate limiter"
d="$(mktemp -d)"; command -v cygpath >/dev/null 2>&1 && d="$(cygpath -m "$d")"
# throwaway express-shaped Node project (never installed; the check only reads package.json for language detection)
mkdir -p "$d/src"
printf '{ "name": "live-fixture", "private": true, "license": "MIT", "type": "module", "dependencies": { "express": "^4.19.2" } }\n' > "$d/package.json"
printf '%s\n' "import express from 'express';" "const app = express();" "app.get('/health', (req, res) => res.json({ ok: true }));" "app.listen(3000);" > "$d/src/app.js"
( cd "$d" && git init -q . && git add -A && git -c user.email=live@example.invalid -c user.name=live commit -q -m init ) 2>/dev/null
pass=0; fail=0; ratelimited=0
ok()   { pass=$((pass+1)); echo "  ok   $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       got: $2"; }
now_ms() { local n; n="$(date +%s%N 2>/dev/null)"; case "$n" in *N|"") node -e 'console.log(Date.now())';; *) echo $((n/1000000));; esac; }
# documented throttles and challenges count as RATE-LIMITED, not ERROR: arXiv answers a throttled IP with 429, 503, or a held
# connection (the engine's 15 s timeout), and pypi.org/search serves a JS client challenge to non-browsers
is_ratelimit() {
  printf '%s' "$1" | grep -qiE 'rate.?limit|rate exceeded|429|503|quota|too many requests|secondary rate|client challenge' && return 0
  printf '%s' "$1" | grep -qi 'arxiv' && printf '%s' "$1" | grep -qi 'timeout'
}
# the user_said of a recorded skip (session file first, else the last skips.jsonl row); empty when none or when the record lacks it
skip_user_said() {
  node -e '
const fs=require("fs");const [sess,skips]=process.argv.slice(1);let s=null;
try{s=JSON.parse(fs.readFileSync(sess,"utf8")).skip}catch{}
if(!s){try{const ls=fs.readFileSync(skips,"utf8").split("\n").filter(Boolean);s=JSON.parse(ls[ls.length-1])}catch{}}
process.stdout.write(s&&s.user_said?String(s.user_said):"")' "${1:-/dev/null}" "${2:-/dev/null}"
}
# -p mode has nobody to answer, so any skip is the model's own decision (the offer line forbids it); the record must also
# carry user_said, which the engine now requires: an empty one means the engine regressed
assert_no_skip() { # $1 session file, $2 skips.jsonl
  if [ "$skipped" = true ] || [ -f "$2" ]; then
    us="$(skip_user_said "$1" "$2")"
    if [ -z "$us" ]; then bad "model recorded a skip without a user answer (user_said empty: the engine must refuse this)" "$(head -c 200 "$2" 2>/dev/null)"
    else bad "model recorded a skip in -p mode, quoting a user answer nobody gave: \"$us\"" "$(head -c 200 "$2" 2>/dev/null)"; fi
    return 1
  fi
  ok "no skip was recorded on the user's behalf"
}
# table rows of one markdown section: "|" lines between the heading and the next heading, minus header + separator rows
section_rows() { awk -v h="$2" 'BEGIN{IGNORECASE=1} /^#+ /{on=($0 ~ h)} on && /^\|/ && !/^\|[ -:|]*\|?$/ {print}' "$1" | tail -n +2; }

if [ "$MODE" = "endpoints" ]; then
  [ -f "$ENGINE" ] || { echo "engine missing: $ENGINE"; rm -rf "$d"; exit 2; }
  export CLAUDE_PROJECT_DIR="$d"
  TABLE="$OUT/$STAMP.txt"
  # ENGINE CONTRACT: `open` writes .dejavu/checks/<slug>.json + current.json so every query below lands in the check log
  ( cd "$d" && node "$ENGINE" open "$QUERY" --depth deep ) > "$d/open.out" 2>&1 || { echo "open failed:"; cat "$d/open.out"; }
  LOG="$(ls "$d"/.dejavu/checks/*.jsonl 2>/dev/null | head -1)"
  SOURCES="gh-repos gh-code gh-topics npm pypi crates hn so openalex arxiv"
  printf '%-14s %-36s %5s %7s  %s\n' source request hits ms error | tee "$TABLE"
  row() { printf '%-14s %-36s %5s %7s  %s\n' "$1" "$2" "$3" "$4" "$5" | tee -a "$TABLE"; }
  # ENGINE CONTRACT: hits/ms/error come from the last `query` row for that source in the check log
  # ({source,tier,framing,q,request,hits,top[],ms,error?}); the stdout fallback counts printed rows that carry a url.
  logrow() { # source -> "hits<TAB>ms<TAB>error"
    node -e '
const fs=require("fs");const [f,src]=process.argv.slice(1);let last=null;
try{for(const l of fs.readFileSync(f,"utf8").split("\n")){if(!l.trim())continue;let o;try{o=JSON.parse(l)}catch{continue}
 const kind=o.kind||o.type||o.row||o.event;if(kind==="query"&&o.source===src)last=o;}}catch{}
if(!last){process.stdout.write("\t\t");process.exit(0)}
process.stdout.write([last.hits??"",last.ms??"",last.error??""].join("\t"));' "${LOG:-/dev/null}" "$1"
  }
  for src in $SOURCES; do
    [ "$src" = arxiv ] && sleep 3   # the engine spaces arXiv itself; this keeps the bench polite on quick re-runs
    t0=$(now_ms)
    ( cd "$d" && node "$ENGINE" query "$src" "$QUERY" --limit 10 ) > "$d/q.$src.out" 2> "$d/q.$src.err"; code=$?
    t1=$(now_ms); wall=$((t1-t0))
    [ -z "${LOG:-}" ] && LOG="$(ls "$d"/.dejavu/checks/*.jsonl 2>/dev/null | head -1)"
    IFS=$'\t' read -r hits ms err < <(logrow "$src"; printf '\n')
    [ -z "$hits" ] && hits="$(grep -c '"url"' "$d/q.$src.out")"
    [ -z "$ms" ] && ms="$wall"
    [ "$code" -ne 0 ] && err="${err:-exit $code: $(head -c 160 "$d/q.$src.err" | tr '\n' ' ')}"
    if [ -n "$err" ]; then
      if is_ratelimit "$err"; then ratelimited=$((ratelimited+1)); err="RATE-LIMITED: $err"; else fail=$((fail+1)); err="ERROR: $err"; fi
    elif [ "$hits" = 0 ]; then
      err="(zero hits)"
    fi
    row "$src" "query" "$hits" "$ms" "$err"
  done
  # ENGINE CONTRACT: `inspect` prints one row with evidence:"fetched" and logs fetch + meta rows
  for target in "express-rate-limit/express-rate-limit" "npm:express-rate-limit" "crate:governor"; do
    t0=$(now_ms)
    ( cd "$d" && node "$ENGINE" inspect "$target" ) > "$d/i.out" 2> "$d/i.err"; code=$?
    t1=$(now_ms); wall=$((t1-t0))
    hits="$(grep -c '"evidence"' "$d/i.out")"; err=""
    if [ "$code" -ne 0 ]; then err="exit $code: $(cat "$d/i.err" "$d/i.out" | head -c 160 | tr '\n' ' ')"
    elif ! grep -q '"fetched"' "$d/i.out"; then err="no evidence:fetched row in stdout"; fi
    if [ -n "$err" ]; then
      if is_ratelimit "$err"; then ratelimited=$((ratelimited+1)); err="RATE-LIMITED: $err"; else fail=$((fail+1)); err="ERROR: $err"; fi
    fi
    row "inspect" "$target" "$hits" "$wall" "$err"
  done
  [ -n "${LOG:-}" ] && cp "$LOG" "$OUT/$STAMP.log.jsonl"
  echo "errors=$fail rate-limited=$ratelimited  table: $TABLE"
  rm -rf "$d"
  [ "$fail" -eq 0 ] && exit 0 || exit 1
fi

# ---- claude -p modes -------------------------------------------------------------------------------
# one line: a slash command followed by further paragraphs returns an empty result in -p mode
if [ "$MODE" = "invoke" ]; then
  PROMPT='/dejavu quick token bucket rate limiter middleware for express'
  PERM="acceptEdits"; FMT="json"; EXTRA=""
elif [ "$MODE" = "planmode" ]; then
  PROMPT='Plan a token bucket rate limiter for this express app'
  PERM="plan"; FMT="stream-json"; EXTRA="--verbose"   # stream-json lists every tool_use, so we can see whether ExitPlanMode was attempted
else
  echo "unknown mode: $MODE (endpoints | invoke [model] | planmode [model])"; rm -rf "$d"; exit 2
fi
# MSYS_NO_PATHCONV: Git Bash would otherwise rewrite a leading "/dejavu" into a Windows path
( cd "$d" && env -u CLAUDECODE MSYS_NO_PATHCONV=1 claude -p "$PROMPT" --model "$MODEL" --permission-mode "$PERM" --max-turns 60 --output-format "$FMT" $EXTRA \
    --allowedTools "Bash(node *),Bash(gh *),Bash(curl *),Bash(git *),Bash(cat*),Bash(ls*),Read,Edit,Write,Glob,Grep,Agent,WebSearch,WebFetch" \
    --plugin-dir "$PLUGIN" > "$OUT/$STAMP.json" 2> "$OUT/$STAMP.err" )
echo "exit=$? result: $OUT/$STAMP.json"
node -e '
const fs=require("fs");const raw=fs.readFileSync(process.argv[1],"utf8").trim();let o=null;
try{o=JSON.parse(raw)}catch{ for(const l of raw.split("\n").reverse()){try{const x=JSON.parse(l);if(x.type==="result"){o=x;break}}catch{}} }
if(!o){console.log("no result object");process.exit(0)}
console.log("turns",o.num_turns,"cost",o.total_cost_usd,"stop",o.stop_reason||o.subtype);console.log("--- final:");console.log(String(o.result).slice(0,900))' "$OUT/$STAMP.json"
# state copies next to the result
[ -d "$d/.dejavu" ] && ( cd "$d/.dejavu" && tar cf "$OUT/$STAMP.dejavu.tar" . ) 2>/dev/null
REPORT="$(ls "$d"/docs/dejavu/*.md 2>/dev/null | head -1)"
[ -n "$REPORT" ] && cp "$REPORT" "$OUT/$STAMP.report.md"

if [ "$MODE" = "invoke" ]; then
  echo "--- assertions (invoke):"
  # ENGINE CONTRACT: `report` writes docs/dejavu/<slug>.md with "Search log" and "Closest matches" sections (names from log/SCHEMA.md)
  if [ -n "$REPORT" ]; then ok "report written: ${REPORT#$d/}"; else bad "docs/dejavu/*.md missing" "$(ls "$d" | tr '\n' ' ')"; fi
  if [ -n "$REPORT" ]; then
    nq="$(section_rows "$REPORT" "search log" | wc -l | tr -d ' ')"
    nlog="$(cat "$d"/.dejavu/checks/*.jsonl 2>/dev/null | grep -c '"query"')"
    [ "$nq" -ge 5 ] && ok "search log has $nq rows (>=5; log file has $nlog query rows)" || bad "search log rows $nq < 5 (log file: $nlog query rows)" "$(section_rows "$REPORT" "search log" | head -3)"
    matches="$(section_rows "$REPORT" "closest matches")"
    nm="$(printf '%s\n' "$matches" | grep -c .)"
    unevidenced="$(printf '%s\n' "$matches" | grep . | grep -vE '\|[[:space:]]*(listed|fetched)[[:space:]]*\|')"
    nbad="$(printf '%s\n' "$unevidenced" | grep -c .)"
    if [ "$nm" -gt 0 ] && [ "$nbad" -eq 0 ]; then ok "all $nm Closest-matches rows carry evidence listed|fetched"
    elif [ "$nm" -eq 0 ]; then bad "Closest matches table has no rows" "$(grep -n -i 'closest' "$REPORT" | head -3)"
    else bad "$nbad of $nm Closest-matches rows lack evidence listed|fetched" "$(printf '%s\n' "$unevidenced" | head -3)"; fi
    grep -qiE 'verdict' "$REPORT" && ok "verdict present" || bad "no verdict in report"
  fi
elif [ "$MODE" = "planmode" ]; then
  echo "--- assertions (planmode):"
  # ENGINE CONTRACT: `prompt` writes .dejavu/sessions/<session_id>.json {offered, gate_denied, checks[], skip}; `gate` sets gate_denied
  SESS="$(ls "$d"/.dejavu/sessions/*.json 2>/dev/null | head -1)"
  if [ -n "$SESS" ]; then
    cp "$SESS" "$OUT/$STAMP.session.json"
    read -r offered denied skipped < <(node -e 'const o=require(process.argv[1]);console.log(o.offered===true,o.gate_denied===true,!!o.skip)' "$SESS")
    [ "$offered" = true ] && ok "session offered: true" || bad "session offered != true" "$(cat "$SESS")"
    if grep -q '"name":"ExitPlanMode"' "$OUT/$STAMP.json"; then
      echo "  ExitPlanMode calls: $(grep -o '"name":"ExitPlanMode"' "$OUT/$STAMP.json" | wc -l | tr -d ' ')"
      [ "$denied" = true ] && ok "ExitPlanMode attempted and gate_denied: true" || bad "ExitPlanMode attempted but gate_denied != true" "$(cat "$SESS")"
      ndeny="$(grep -o 'dejavu gate: no prior-art check' "$OUT/$STAMP.json" | wc -l | tr -d ' ')"
      [ "$ndeny" -le 1 ] && ok "the deny reason appears at most once in the stream ($ndeny)" || bad "gate denied $ndeny times in one plan cycle"
      # after the deny the model must ask; a skip here is the model's own decision (see assert_no_skip)
      grep -q '"name":"AskUserQuestion"' "$OUT/$STAMP.json" && echo "  info AskUserQuestion was called after the deny"
      assert_no_skip "$SESS" "$d/.dejavu/skips.jsonl"
    elif [ "$(node -e 'const fs=require("fs");let has="unknown";for(const l of fs.readFileSync(process.argv[1],"utf8").split("\n")){try{const o=JSON.parse(l);if(o.type==="system"&&o.subtype==="init"){has=(o.tools||[]).includes("ExitPlanMode");break}}catch{}}console.log(has)' "$OUT/$STAMP.json")" = false ]; then
      # claude -p (2.1.270) lists neither ExitPlanMode nor AskUserQuestion in plan mode, so the model cannot reach the gate.
      # Drive it directly against the session state the live hooks left, with the real session id: deny once, then allow.
      SID="$(basename "$SESS" .json)"
      echo "  info ExitPlanMode is not in the -p tool list; driving the gate directly for session $SID"
      gatej() { printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s","hook_event_name":"PreToolUse","permission_mode":"plan","tool_name":"ExitPlanMode","tool_use_id":"%s","tool_input":{}}' "$SID" "$d" "$d/none.jsonl" "$1"; }
      g1="$(cd "$d" && gatej live-gate-1 | CLAUDE_PROJECT_DIR="$d" node "$ENGINE" gate 2>&1)"
      if ! assert_no_skip "$SESS" "$d/.dejavu/skips.jsonl"; then
        # the gate still opens on a recorded skip, as designed; the skip itself already failed the run above
        [ -z "$g1" ] && ok "gate allows silently after the skip" || bad "gate spoke although a skip is recorded" "$g1"
      else
        printf '%s' "$g1" | grep -q '"permissionDecision":"deny"' && printf '%s' "$g1" | grep -q '/dejavu' && printf '%s' "$g1" | grep -q 'skip' \
          && ok "gate denies once with a reason naming /dejavu and skip" || bad "gate did not deny with the expected reason" "$g1"
        [ "$(node -e 'console.log(require(process.argv[1]).gate_denied===true)' "$SESS")" = true ] && ok "session gate_denied: true after the deny" || bad "gate_denied not recorded" "$(cat "$SESS")"
        g2="$(cd "$d" && gatej live-gate-2 | CLAUDE_PROJECT_DIR="$d" node "$ENGINE" gate 2>&1)"
        [ -z "$g2" ] && ok "second ExitPlanMode in the same plan cycle is allowed (silent)" || bad "gate spoke twice in one plan cycle" "$g2"
      fi
      cp "$SESS" "$OUT/$STAMP.session.json"
    else
      echo "  info ExitPlanMode never attempted (gate not exercised); gate_denied=$denied"
    fi
  else
    bad "no .dejavu/sessions/*.json: the prompt hook did not fire" "$(ls -a "$d" | tr '\n' ' ')"
  fi
fi
echo "passed $pass failed $fail"
rm -rf "$d"
[ "$fail" -eq 0 ] && exit 0 || exit 1
