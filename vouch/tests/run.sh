#!/usr/bin/env bash
# vouch pipe-test battery: synthetic hook JSON in, decisions and ledger rows out.
# Runs in an isolated HOME and project dir so it never touches a real bankroll.
# The skip pattern under test is assembled from parts so this file never contains it literally
# (otherwise vouch's own test-protect would refuse to let an agent edit this file).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$HERE/../scripts/vouch.js"
TMP="$(mktemp -d)"
command -v cygpath >/dev/null 2>&1 && TMP="$(cygpath -m "$TMP")"
export VOUCH_HOME="$TMP/home"
export CLAUDE_PROJECT_DIR="$TMP/proj"
export CLAUDE_SESSION_ID="t1"
SK="sk"; IP="ip"; TD="te"; TS="sts"
mkdir -p "$CLAUDE_PROJECT_DIR/src" "$CLAUDE_PROJECT_DIR/$TD$TS" "$TMP/outside"
printf 'export const a = 1;\n' > "$CLAUDE_PROJECT_DIR/src/a.js"
printf 'test("x", () => {});\n' > "$CLAUDE_PROJECT_DIR/$TD$TS/a.test.js"
printf 'outside\n' > "$TMP/outside/o.txt"
A="$CLAUDE_PROJECT_DIR/src/a.js"
T="$CLAUDE_PROJECT_DIR/$TD$TS/a.test.js"
O="$TMP/outside/o.txt"
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL $1"; echo "       got: $2"; }
run()  { printf '%s' "$2" | node "$ENGINE" "$1" 2>"$TMP/err"; echo "exit=$?"; }
S='"session_id":"t1","cwd":"'"$CLAUDE_PROJECT_DIR"'","transcript_path":"'"$TMP/none.jsonl"'"'
bal()  { node -e 'const b=require(process.argv[1]);const k=Object.keys(b)[0];console.log(b[k].balance)' "$VOUCH_HOME/bankroll.json" 2>/dev/null || echo 1000; }
setbal() { node -e 'const fs=require("fs");const p=process.argv[1];const b=JSON.parse(fs.readFileSync(p));const k=Object.keys(b)[0];b[k].balance=+process.argv[2];fs.writeFileSync(p,JSON.stringify(b));' "$VOUCH_HOME/bankroll.json" "$1"; }
# ids are generated inside command substitutions (subshells), so a counter would not persist; use entropy
nid() { printf 'u%s%s%s' "$RANDOM" "$RANDOM" "$RANDOM"; }
# hook JSON builders (tool_use_id must differ per call so the duplicate-delivery guard stays out of the way)
lockj()    { printf '{%s,"tool_use_id":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$S" "$(nid)" "$1" "$2"; }
receiptj() { printf '{%s,"tool_use_id":"%s","hook_event_name":"%s","tool_name":"%s","tool_input":%s,"tool_response":{}}' "$S" "$(nid)" "$1" "$2" "$3"; }
stopj()    { printf '{%s,"hook_event_name":"Stop","stop_hook_active":%s,"last_assistant_message":"%s"}' "$S" "$1" "$2"; }
subj()     { printf '{%s,"hook_event_name":"SubagentStop","agent_id":"ag1","agent_type":"general-purpose","stop_hook_active":false,"last_assistant_message":"%s"}' "$S" "$1"; }
tierj()    { printf '{%s,"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$S" "$1" "$2"; }

echo "1. edit without read -> deny + -50"
r=$(run lock "$(lockj Edit '{"file_path":"'"$A"'","old_string":"1","new_string":"2"}')")
echo "$r" | grep -q '"permissionDecision":"deny"' && ok "denied" || bad "expected deny" "$r"
[ "$(bal)" = "950" ] && ok "balance 950" || bad "balance" "$(bal)"

echo "2. read then edit -> allowed"
run receipt "$(receiptj PostToolUse Read '{"file_path":"'"$A"'"}')" >/dev/null
r=$(run lock "$(lockj Edit '{"file_path":"'"$A"'","old_string":"1","new_string":"2"}')")
[ "$r" = "exit=0" ] && ok "allowed after fresh Read" || bad "should allow, silently" "$r"

echo "2b. a shell read (cat) counts as a read of the current content"
printf 'export const b = 1;\n' > "$CLAUDE_PROJECT_DIR/src/b.js"
run receipt "$(receiptj PostToolUse Bash '{"command":"cat src/b.js"}')" >/dev/null
r=$(run lock "$(lockj Edit '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/src/b.js","old_string":"1","new_string":"2"}')")
[ "$r" = "exit=0" ] && ok "edit allowed after shell cat" || bad "cat should count as a read" "$r"

echo "2c. shell writes are edits: a heredoc onto an unread file is denied; after a read it is allowed and advances the edit clock"
printf 'export const c = 1;\n' > "$CLAUDE_PROJECT_DIR/src/c.js"
r=$(run lock "$(lockj Bash '{"command":"cat > src/c.js <<EOF\nexport const c = 2;\nEOF"}')")
echo "$r" | grep -q 'grounding lock' && ok "shell write to unread file denied" || bad "expected shell-write deny" "$r"
run receipt "$(receiptj PostToolUse Bash '{"command":"cat src/c.js"}')" >/dev/null
r=$(run lock "$(lockj Bash '{"command":"cat > src/c.js <<EOF\nexport const c = 2;\nEOF"}')")
[ "$r" = "exit=0" ] && ok "shell write allowed after read" || bad "shell write after read should be allowed" "$r"
printf 'export const c = 2;\n' > "$CLAUDE_PROJECT_DIR/src/c.js"
run receipt "$(receiptj PostToolUse Bash '{"command":"cat > src/c.js <<EOF\nexport const c = 2;\nEOF"}')" >/dev/null
grep -q 'shell-write' "$CLAUDE_PROJECT_DIR/.vouch/sessions/t1.jsonl" && ok "shell-write receipt recorded" || bad "no shell-write receipt" "none"
node -e 'const s=require(process.argv[1]);process.exit(s.last_edit_ts>0?0:1)' "$CLAUDE_PROJECT_DIR/.vouch/sessions/t1.state.json" && ok "edit clock advanced by the shell write" || bad "edit clock not advanced" "$(cat "$CLAUDE_PROJECT_DIR/.vouch/sessions/t1.state.json")"
r=$(run lock "$(lockj Bash '{"command":"echo x > '"$TD$TS"'/a.test.js"}')")
echo "$r" | grep -q 'test-protect' && ok "shell overwrite of a test file denied" || bad "expected test-protect deny" "$r"

echo "2d. write-then-check in ONE command: the check counts as after the edit"
run receipt "$(receiptj PostToolUse Bash '{"command":"cat src/c.js"}')" >/dev/null
printf 'export const c = 3;\n' > "$CLAUDE_PROJECT_DIR/src/c.js"
# a non-test check command, so later "tests pass" cases still have no test receipt to lean on
run receipt "$(receiptj PostToolUse Bash '{"command":"cat > src/c.js <<EOF\nexport const c = 3;\nEOF\nnode src/c.js"}')" >/dev/null
r=$(run guard "$(stopj false 'CLAIM: c.js loads after the rewrite | RECEIPT: cmd:node src/c.js | WAGER: 100')")
echo "$r" | grep -q 'BEFORE your latest edit' && bad "same-command check must not be stale" "$r" || ok "check in the same command as the write is fresh"

echo "2e. paths with spaces and Git Bash /c/ paths: a quoted shell read counts; quoted, escaped and /c/ shell writes are locked"
printf 'export const m = 1;\n' > "$CLAUDE_PROJECT_DIR/src/my file.js"
printf 'export const o = 1;\n' > "$CLAUDE_PROJECT_DIR/src/other file.js"
run receipt "$(receiptj PostToolUse Bash '{"command":"cat \"src/my file.js\""}')" >/dev/null
r=$(run lock "$(lockj Edit '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/src/my file.js","old_string":"1","new_string":"2"}')")
[ "$r" = "exit=0" ] && ok "edit allowed after a quoted cat of a path with a space" || bad "quoted cat should count as a read" "$r"
r=$(run lock "$(lockj Bash '{"command":"echo x > \"src/other file.js\""}')")
echo "$r" | grep -q 'grounding lock' && ok "quoted shell write onto an unread file denied" || bad "expected shell-write deny" "$r"
r=$(run lock "$(lockj Bash '{"command":"echo x > src/other\\ file.js"}')")
echo "$r" | grep -q 'grounding lock' && ok "backslash-escaped shell write onto an unread file denied" || bad "expected shell-write deny" "$r"
r=$(run lock "$(lockj Bash '{"command":"echo x > \"'"$CLAUDE_PROJECT_DIR"'/src/other file.js\""}')")
echo "$r" | grep -q 'grounding lock' && ok "quoted absolute shell write denied" || bad "expected shell-write deny" "$r"
if command -v cygpath >/dev/null 2>&1; then
  # the /c/Users/... spelling Git Bash uses (cygpath -u would map the temp dir to /tmp, which is not the case under test)
  U="/$(printf '%s' "${CLAUDE_PROJECT_DIR:0:1}" | tr 'A-Z' 'a-z')${CLAUDE_PROJECT_DIR:2}"
  printf 'export const u = 1;\n' > "$CLAUDE_PROJECT_DIR/src/u.js"; printf 'export const v = 1;\n' > "$CLAUDE_PROJECT_DIR/src/v.js"
  run receipt "$(receiptj PostToolUse Bash '{"command":"cat '"$U"'/src/u.js"}')" >/dev/null
  r=$(run lock "$(lockj Edit '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/src/u.js","old_string":"1","new_string":"2"}')")
  [ "$r" = "exit=0" ] && ok "a /c/ style cat counts as a read on Windows" || bad "/c/ read not honoured" "$r"
  r=$(run lock "$(lockj Bash '{"command":"echo x > '"$U"'/src/v.js"}')")
  echo "$r" | grep -q 'grounding lock' && ok "a /c/ style shell write onto an unread file denied" || bad "expected shell-write deny" "$r"
fi

echo "2f. the lock takes content reads only: Grep, wc, and a file that is merely a token of a read command are not reads"
for f in g w x p; do printf 'export const %s = 1;\n' "$f" > "$CLAUDE_PROJECT_DIR/src/$f.js"; done
run receipt "$(receiptj PostToolUse Grep '{"pattern":"zzz","path":"'"$CLAUDE_PROJECT_DIR"'/src/g.js","output_mode":"files_with_matches"}')" >/dev/null
r=$(run lock "$(lockj Edit '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/src/g.js","old_string":"1","new_string":"2"}')")
echo "$r" | grep -q 'no Read receipt' && ok "a Grep on the file is not a read" || bad "Grep must not unlock an edit" "$r"
run receipt "$(receiptj PostToolUse Bash '{"command":"wc -l src/w.js"}')" >/dev/null
r=$(run lock "$(lockj Edit '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/src/w.js","old_string":"1","new_string":"2"}')")
echo "$r" | grep -q 'no Read receipt' && ok "wc is not a read" || bad "wc must not unlock an edit" "$r"
run receipt "$(receiptj PostToolUse Bash '{"command":"cat src/w.js && ls -la src/x.js"}')" >/dev/null
r=$(run lock "$(lockj Edit '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/src/x.js","old_string":"1","new_string":"2"}')")
echo "$r" | grep -q 'no Read receipt' && ok "a file named by ls in the same command is not read" || bad "an ls token must not unlock an edit" "$r"
r=$(run lock "$(lockj Edit '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/src/w.js","old_string":"1","new_string":"2"}')")
[ "$r" = "exit=0" ] && ok "the cat in that same command did read w.js" || bad "cat && ls: the cat's file must count" "$r"
# a Grep pattern shaped like a redirection is not a shell write and does not advance the edit clock
run receipt "$(receiptj PostToolUse Bash '{"command":"node src/p.js"}')" >/dev/null
run receipt "$(receiptj PostToolUse Grep '{"pattern":"foo > src/p.js"}')" >/dev/null
r=$(run guard "$(stopj false 'CLAIM: p.js loads | RECEIPT: cmd:node src/p.js | WAGER: 50')")
echo "$r" | grep -q 'BEFORE your latest edit' && bad "a Grep pattern advanced the edit clock" "$r" || ok "a Grep pattern with > is not a shell write"
# the denials above have drained the test bankroll; the tier must stay full for the claim-guard cases
setbal 1000

echo "3. file changed after read -> deny"
printf 'export const a = 2;\n' > "$A"
r=$(run lock "$(lockj Edit '{"file_path":"'"$A"'","old_string":"2","new_string":"3"}')")
echo "$r" | grep -q 'changed since' && ok "stale read denied" || bad "expected stale deny" "$r"
run receipt "$(receiptj PostToolUse Read '{"file_path":"'"$A"'"}')" >/dev/null

echo "4. 'tests pass' with no command -> Stop blocked, wager lost"
b0=$(bal)
r=$(run guard "$(stopj false 'Done. All tests pass and the feature is working.')")
echo "$r" | grep -q '"decision":"block"' && ok "blocked implicit claim" || bad "expected block" "$r"
[ "$(bal)" -lt "$b0" ] && ok "balance dropped $b0 -> $(bal)" || bad "balance should drop" "$(bal)"
grep -q '"kind":"incident"' "$CLAUDE_PROJECT_DIR/.vouch/sessions/t1.jsonl" && ok "incident row written" || bad "incident row" "none"

echo "5. duplicate delivery of the same stop -> ignored; stop_hook_active -> released"
b0=$(bal)
r=$(run guard "$(stopj false 'Done. All tests pass and the feature is working.')")
[ "$(bal)" -eq "$b0" ] && ok "duplicate event not charged again" || bad "duplicate charged" "$(bal) vs $b0"
r=$(run guard "$(stopj true 'Done. All tests pass and the feature is working.')")
[ "$r" = "exit=0" ] && ok "released" || bad "must not re-block, silently" "$r"

echo "6. CLAIM with cmd receipt but command never ran -> block with exact missing receipt"
r=$(run guard "$(stopj false 'CLAIM: unit tests pass | RECEIPT: cmd:npm test | WAGER: 200')")
echo "$r" | grep -q 'no command containing .*npm test' && ok "names the missing receipt" || bad "expected missing-receipt reason" "$r"

echo "7. run the command, then claim -> win"
run receipt "$(receiptj PostToolUse Bash '{"command":"npm test -- --run"}')" >/dev/null
b0=$(bal)
r=$(run guard "$(stopj false 'CLAIM: unit tests pass (12) | RECEIPT: cmd:npm test | WAGER: 200')")
[ "$r" = "exit=0" ] && ok "backed claim passes (a settled win is silent)" || bad "should not block or speak" "$r"
[ "$(bal)" -gt "$b0" ] && ok "balance rose $b0 -> $(bal)" || bad "balance should rise" "$(bal)"

echo "8. edit AFTER the test run -> the same claim is stale"
run receipt "$(receiptj PostToolUse Edit '{"file_path":"'"$A"'"}')" >/dev/null
r=$(run guard "$(stopj false 'CLAIM: unit tests still pass | RECEIPT: cmd:npm test | WAGER: 100')")
echo "$r" | grep -q 'BEFORE your latest edit' && ok "stale receipt rejected" || bad "expected stale rejection" "$r"

echo "9. NOT VERIFIED claim -> small credit, no block"
b0=$(bal)
r=$(run guard "$(stopj false 'CLAIM: NOT VERIFIED - could not run the e2e suite (no browser).')")
[ "$r" = "exit=0" ] && ok "not blocked" || bad "must not block or speak" "$r"
[ "$(bal)" -eq $((b0+10)) ] && ok "credit +10" || bad "expected +10" "$(bal) vs $b0"

echo "10. forged receipt is ignored; chain tamper is detected"
L="$CLAUDE_PROJECT_DIR/.vouch/sessions/t1.jsonl"
printf '{"kind":"receipt","ts":9999999999999,"tool":"Bash","ok":true,"cmd":"pytest -q","exit":0,"hash":"deadbeefdeadbeef","prev":"genesis","sig":"0000000000000000"}\n' >> "$L"
r=$(run guard "$(stopj false 'CLAIM: pytest green | RECEIPT: cmd:pytest | WAGER: 300')")
echo "$r" | grep -q 'no command containing .*pytest' && ok "forged receipt rejected" || bad "expected rejection of forged receipt" "$r"
node "$ENGINE" verify t1 | grep -q 'TAMPERED' && ok "verify reports tamper" || bad "verify should report tamper" "$(node "$ENGINE" verify t1)"
cp "$L" "$TMP/ledger.bak"; grep -v deadbeef "$TMP/ledger.bak" > "$L"
node "$ENGINE" verify t1 | grep -q 'chain intact' && ok "chain intact after removing the forgery" || bad "chain should be intact" "$(node "$ENGINE" verify t1)"
# drop the SECOND receipt row (other row kinds are interleaved, so line numbers do not map to receipts)
cp "$L" "$TMP/ledger.bak"; node -e 'const fs=require("fs");let n=0;const out=fs.readFileSync(process.argv[1],"utf8").split("\n").filter(l=>{if(l.includes("\"kind\":\"receipt\"")){n++;return n!==2}return true});fs.writeFileSync(process.argv[1],out.join("\n"))' "$L"
node "$ENGINE" verify t1 | grep -q 'TAMPERED' && ok "deleting a middle receipt breaks the chain" || bad "expected chain break" "$(node "$ENGINE" verify t1)"
cp "$TMP/ledger.bak" "$L"

echo "11. test-protect: skipping a test -> deny -100; removing the tests dir -> deny; multi-line scripts ok"
b0=$(bal)
r=$(run lock "$(lockj Edit '{"file_path":"'"$T"'","old_string":"test(","new_string":"test.'"$SK$IP"'("}')")
echo "$r" | grep -q 'test-protect' && ok "skip denied" || bad "expected test-protect deny" "$r"
[ "$(bal)" -eq $((b0-100)) ] && ok "-100" || bad "expected -100" "$(bal) vs $b0"
r=$(run lock "$(lockj Bash '{"command":"rm -rf '"$TD$TS"'/"}')")
echo "$r" | grep -q 'test-protect' && ok "removing tests dir denied" || bad "expected deny" "$r"
r=$(run lock "$(lockj Bash '{"command":"rm -rf build/\nnpm run '"$TD$TS"'"}')")
[ "$r" = "exit=0" ] && ok "multi-line script mentioning tests allowed" || bad "must not match across newlines" "$r"

echo "11b. test-protect judges real test paths: artifacts named test-* or *.log are not tests, globs under a tests dir are"
mkdir -p "$CLAUDE_PROJECT_DIR/test-results" "$CLAUDE_PROJECT_DIR/coverage"; printf 'x\n' > "$CLAUDE_PROJECT_DIR/coverage/spec-report.html"; printf 'x\n' > "$CLAUDE_PROJECT_DIR/test.log"
for cmd in 'rm -f /tmp/test.log' 'rm -rf test-results' 'rm -rf coverage/spec-report.html' 'rm test.log' 'rm -rf build'; do
  r=$(run lock "$(lockj Bash '{"command":"'"$cmd"'"}')")
  [ "$r" = "exit=0" ] && ok "allowed: $cmd" || bad "over-match: $cmd" "$r"
done
r=$(run lock "$(lockj Bash '{"command":"rm '"$TD$TS"'/*.js"}')")
echo "$r" | grep -q 'test-protect' && ok "rm of a glob under the tests dir denied" || bad "expected test-protect deny" "$r"
printf 'x\n' > "$CLAUDE_PROJECT_DIR/src/a.${TD}st.js"
r=$(run lock "$(lockj Bash '{"command":"rm src/a.'"${TD}st"'.js"}')")
echo "$r" | grep -q 'test-protect' && ok "rm of a *.${TD}st.js file outside the tests dir denied" || bad "expected test-protect deny" "$r"
r=$(run lock "$(lockj Bash '{"command":"npm rm '"$TD$TS"'-helper"}')")
[ "$r" = "exit=0" ] && ok "npm rm of a package is not a deletion of tests" || bad "npm rm over-matched" "$r"

echo "11c. a test-like word in the PROJECT path (my-test-app) is not a test path"
MT="$TMP/my-$TD-app"; mkdir -p "$MT/src" "$MT/build"; printf 'export const d = 1;\n' > "$MT/src/d.js"
MS='"session_id":"mt","cwd":"'"$MT"'","transcript_path":"'"$TMP/none.jsonl"'"'
printf '{%s,"tool_use_id":"mt1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"cat src/d.js"},"tool_response":{}}' "$MS" | CLAUDE_PROJECT_DIR="$MT" node "$ENGINE" receipt >/dev/null
r=$(printf '{%s,"tool_use_id":"mt2","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo x > src/d.js"}}' "$MS" | CLAUDE_PROJECT_DIR="$MT" node "$ENGINE" lock; echo "exit=$?")
[ "$r" = "exit=0" ] && ok "shell write in my-$TD-app allowed after a read" || bad "the project folder name was judged a test path" "$r"
r=$(printf '{%s,"tool_use_id":"mt3","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf %s/build"}}' "$MS" "$MT" | CLAUDE_PROJECT_DIR="$MT" node "$ENGINE" lock; echo "exit=$?")
[ "$r" = "exit=0" ] && ok "rm of an absolute path under my-$TD-app allowed" || bad "the absolute project path was judged a test path" "$r"

echo "12. loop monitor: same failing command 3x with no edit -> -50 + warning"
b0=$(bal)
for i in 1 2 3; do run receipt "$(receiptj PostToolUseFailure Bash '{"command":"npm run build"}')" > "$TMP/loop$i"; done
grep -q 'loop rule' "$TMP/loop3" && ok "loop warning on 3rd" || bad "expected loop warning" "$(cat "$TMP/loop3")"
grep -q 'loop rule' "$TMP/loop2" && bad "warned too early" "$(cat "$TMP/loop2")" || ok "silent on 2nd"
[ "$(bal)" -eq $((b0-50)) ] && ok "-50" || bad "expected -50" "$(bal) vs $b0"

echo "12b. edit loop: edit/run/edit/run is the honest path and never charged; N straight edits of one file with no command are"
b0=$(bal)
for i in 1 2 3 4 5 6 7; do
  run receipt "$(receiptj PostToolUse Edit '{"file_path":"'"$A"'","old_string":"a","new_string":"b"}')" > "$TMP/e$i"
  run receipt "$(receiptj PostToolUse Bash '{"command":"node src/a.js"}')" >/dev/null
done
grep -q 'loop rule' "$TMP/e6" "$TMP/e7" && bad "honest edit/run alternation charged" "$(cat "$TMP/e6" "$TMP/e7")" || ok "edit/run x7: no loop charge"
[ "$(bal)" -eq "$b0" ] && ok "balance unchanged" || bad "balance changed" "$(bal) vs $b0"
for i in 1 2 3 4 5 6; do run receipt "$(receiptj PostToolUse Edit '{"file_path":"'"$A"'","old_string":"a","new_string":"b"}')" > "$TMP/e$i"; done
grep -q 'loop rule' "$TMP/e5" && bad "warned too early" "$(cat "$TMP/e5")" || ok "silent on the 5th straight edit"
grep -q 'edited 6x with no command' "$TMP/e6" && ok "warned on the 6th straight edit" || bad "expected the edit-loop warning" "$(cat "$TMP/e6")"
[ "$(bal)" -eq $((b0-50)) ] && ok "-50 once" || bad "expected -50" "$(bal) vs $b0"

# the battery's own losses have drained the test bankroll by now; restore it so tier effects only appear in test 17
setbal 1000

echo "13. lock scope: a file outside the project is not locked by default"
r=$(run lock "$(lockj Edit '{"file_path":"'"$O"'","old_string":"a","new_string":"b"}')")
[ "$r" = "exit=0" ] && ok "outside-project edit allowed" || bad "outside file should be allowed, silently" "$r"

echo "14. code spans and fenced blocks are not claims"
r=$(run guard "$(stopj false 'Use `CLAIM: <what> | RECEIPT: cmd:<y> | WAGER: <n>` when done.\n```\nCLAIM: <one thing> | RECEIPT: cmd:<b> | WAGER: <300>\n```')")
[ "$r" = "exit=0" ] && ok "examples with placeholders ignored" || bad "examples (with placeholders) must not be claims" "$r"
r=$(run guard "$(stopj false 'Claim lines:\n```\nCLAIM: the migration applied | RECEIPT: cmd:alembic upgrade head | WAGER: 200\n```')")
echo "$r" | grep -q '"decision":"block"' && ok "fenced REAL claim lines are parsed (and this one is unbacked)" || bad "fenced real claims must be parsed" "$r"

echo "15. subagent: implicit phrase not charged; explicit unbacked claim still blocked"
b0=$(bal)
r=$(run guard "$(subj 'Summary: all tests pass and it is working.')")
[ "$r" = "exit=0" ] && ok "subagent implicit ignored" || bad "subagent implicit must not block or speak" "$r"
[ "$(bal)" -eq "$b0" ] && ok "lead bankroll untouched" || bad "lead bankroll changed" "$(bal) vs $b0"
r=$(run guard "$(subj 'CLAIM: refactor green | RECEIPT: cmd:cargo test | WAGER: 200')")
echo "$r" | grep -q '"decision":"block"' && ok "subagent explicit unbacked blocked" || bad "expected block" "$r"
node -e 'const b=require(process.argv[1]);const ks=Object.keys(b);process.exit(ks.some(k=>/subagent/.test(k))?0:1)' "$VOUCH_HOME/bankroll.json" && ok "charged to a subagent key, not the lead" || bad "subagent key missing" "$(cat "$VOUCH_HOME/bankroll.json")"

echo "16. corpus: false-completion taxonomy vs benign prose"
node "$HERE/corpus.js" "$HERE/corpus.json" "$ENGINE" "$CLAUDE_PROJECT_DIR" && ok "corpus all correct" || bad "corpus has misclassifications" "see above"

echo "17. tiers: silent in normal mode, enforced when invoked"
setbal 300
r=$(run tier "$(tierj Write '{"file_path":"'"$A"'","content":"x"}')")
[ "$r" = "exit=0" ] && ok "normal mode: tier hook silent" || bad "should be silent when not invoked" "$r"
node "$ENGINE" invoke strict >/dev/null
r=$(run tier "$(tierj Write '{"file_path":"'"$A"'","content":"x"}')")
echo "$r" | grep -q 'restricted' && ok "restricted: Write denied" || bad "expected restricted deny" "$r"
r=$(run tier "$(tierj Agent '{"prompt":"x","model":"sonnet"}')")
[ "$r" = "exit=0" ] && ok "restricted: cheaper rework subagent allowed" || bad "sonnet subagent should pass silently" "$r"
r=$(run tier "$(tierj Agent '{"prompt":"x"}')")
echo "$r" | grep -q 'fan-out is off' && ok "restricted: fan-out denied" || bad "expected fan-out deny" "$r"
setbal 50
r=$(run tier "$(tierj Edit '{"file_path":"'"$A"'","old_string":"a","new_string":"b"}')")
echo "$r" | grep -q 'broke' && ok "broke: Edit denied" || bad "expected broke deny" "$r"
r=$(run guard "$(stopj false 'CLAIM: NOT VERIFIED - handing off.')")
echo "$r" | grep -q 'handoff' && ok "broke: Stop blocked once with handoff instruction" || bad "expected handoff block" "$r"

echo "17b. skill hooks arm the session by themselves (--armed) when the invoke line never ran"
export CLAUDE_SESSION_ID="t2"
r=$(printf '%s' "$(tierj Write '{"file_path":"'"$A"'","content":"x"}' | sed 's/"session_id":"t1"/"session_id":"t2"/')" | node "$ENGINE" tier --armed strict; echo "exit=$?")
node -e 'const s=require(process.argv[1]);process.exit(s.invoked&&s.strictness==="strict"?0:1)' "$CLAUDE_PROJECT_DIR/.vouch/sessions/t2.state.json" && ok "hook armed a fresh session as strict" || bad "self-arming failed" "$(cat "$CLAUDE_PROJECT_DIR/.vouch/sessions/t2.state.json" 2>/dev/null)"
grep -q '"kind":"invoke"' "$CLAUDE_PROJECT_DIR/.vouch/sessions/t2.jsonl" && ok "invoke row written via hook" || bad "no invoke row" "none"
export CLAUDE_SESSION_ID="t1"

echo "17c. a session id with path separators cannot escape .vouch/sessions/"
r=$(printf '{"session_id":"../../escape","cwd":"%s","hook_event_name":"PostToolUse","tool_use_id":"esc1","tool_name":"Read","tool_input":{"file_path":"%s"},"tool_response":{}}' "$CLAUDE_PROJECT_DIR" "$A" | node "$ENGINE" receipt; echo "exit=$?")
[ ! -e "$TMP/escape.jsonl" ] && [ ! -e "$CLAUDE_PROJECT_DIR/escape.jsonl" ] && ls -a "$CLAUDE_PROJECT_DIR/.vouch/sessions/" | grep -q 'escape' && ok "session id sanitized into .vouch/sessions/ ($(ls -a "$CLAUDE_PROJECT_DIR/.vouch/sessions/" | grep escape | head -1))" || bad "session id escaped the sessions dir" "$(ls -a "$TMP" "$CLAUDE_PROJECT_DIR" | tr '\n' ' ')"

echo "18. config guard while armed: the engine and Claude Code's hook settings, not the app's own settings.json"
r=$(run lock "$(lockj Edit '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/.claude/skills/vouch/scripts/vouch.js","old_string":"a","new_string":"b"}')")
echo "$r" | grep -q 'config-guard' && ok "engine edit denied" || bad "expected config-guard deny" "$r"
r=$(run lock "$(lockj Edit '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/.claude/settings.json","old_string":"a","new_string":"b"}')")
echo "$r" | grep -q 'config-guard' && ok ".claude/settings.json denied" || bad "expected config-guard deny" "$r"
mkdir -p "$CLAUDE_PROJECT_DIR/src/config"; printf '{"a":1}\n' > "$CLAUDE_PROJECT_DIR/src/config/settings.json"
run receipt "$(receiptj PostToolUse Read '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/src/config/settings.json"}')" >/dev/null
r=$(run lock "$(lockj Edit '{"file_path":"'"$CLAUDE_PROJECT_DIR"'/src/config/settings.json","old_string":"1","new_string":"2"}')")
[ "$r" = "exit=0" ] && ok "the app's own src/config/settings.json is editable after a read" || bad "config-guard over-reached" "$r"

echo "18b. record guard: the signing secret is never readable, the bankroll and the ledger are never written or deleted by the model"
r=$(run lock "$(lockj Bash '{"command":"cat '"$VOUCH_HOME"'/secret"}')")
echo "$r" | grep -q '"permissionDecision":"deny"' && ok "shell read of the secret denied" || bad "expected deny" "$r"
r=$(run lock "$(lockj Read '{"file_path":"'"$VOUCH_HOME"'/secret"}')")
echo "$r" | grep -q '"permissionDecision":"deny"' && ok "Read of the secret denied" || bad "expected deny" "$r"
r=$(run lock "$(lockj Bash '{"command":"echo {} > '"$VOUCH_HOME"'/bankroll.json"}')")
echo "$r" | grep -q 'record guard' && ok "shell write to the bankroll denied while armed" || bad "expected record-guard deny" "$r"
r=$(run lock "$(lockj Write '{"file_path":"'"$VOUCH_HOME"'/bankroll.json","content":"{}"}')")
echo "$r" | grep -q 'record guard' && ok "Write to the bankroll denied while armed" || bad "expected record-guard deny" "$r"
r=$(run lock "$(lockj Bash '{"command":"rm -rf .vouch/sessions"}')")
echo "$r" | grep -q 'record guard' && ok "rm of the ledger denied while armed" || bad "expected record-guard deny" "$r"
r=$(run lock "$(lockj Read '{"file_path":"'"$A"'"}')")
[ "$r" = "exit=0" ] && ok "an ordinary Read is silent" || bad "Read hook spoke" "$r"
r=$(printf '{%s,"tool_use_id":"rg-t9","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf .vouch/sessions"}}' '"session_id":"t9x","cwd":"'"$CLAUDE_PROJECT_DIR"'"' | node "$ENGINE" lock; echo "exit=$?")
echo "$r" | grep -q '"permissionDecision":"ask"' && ok "in normal mode the same command asks the user instead" || bad "expected ask in normal mode" "$r"

echo "19. injections: full line when state changes, stub otherwise"
r1=$(run prompt '{'"$S"',"hook_event_name":"UserPromptSubmit","prompt":"hi"}')
echo "$r1" | grep -q 'vouch armed' && ok "first turn: full line" || bad "expected full injection" "$r1"
r2=$(run prompt '{'"$S"',"hook_event_name":"UserPromptSubmit","prompt":"again"}')
n=$(echo "$r2" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s.split("\n")[0]);console.log(o.hookSpecificOutput.additionalContext.length)})')
[ "$n" -lt 40 ] && ok "unchanged turn: stub of $n chars" || bad "expected a short stub" "$r2"
r=$(run start '{'"$S"',"hook_event_name":"SessionStart","source":"startup","model":"claude-test"}')
echo "$r" | grep -q 'balance' && ok "session start line" || bad "expected start line" "$r"

echo "20. handoff, impossible, status, report"
p=$(node "$ENGINE" handoff | tail -1)
[ -f "$p" ] && grep -q 'Commands tried' "$p" && ok "handoff written" || bad "handoff" "$p"
node "$ENGINE" impossible "sandbox has no chromium" "apt fails offline" >/dev/null
grep -q chromium "$CLAUDE_PROJECT_DIR/.vouch/impossible.jsonl" && ok "impossible recorded" || bad "impossible" "missing"
node "$ENGINE" status | grep -q balance && ok "status prints" || bad "status" "none"
node "$ENGINE" report t1 | grep -q 'claims backed/unbacked' && ok "report prints" || bad "report" "$(node "$ENGINE" report t1)"
node "$ENGINE" help | grep -q 'VOUCH_HOME' && node "$ENGINE" | grep -q '^usage:' && ok "help lists the subcommands and VOUCH_HOME" || bad "help" "$(node "$ENGINE" help | head -3)"

echo "20b. vouch.config.json merges one level deep: a partial tiers or max_turns override keeps the other keys"
setbal 500
printf '{"tiers":{"full":900}}\n' > "$CLAUDE_PROJECT_DIR/vouch.config.json"
node "$ENGINE" status | grep -q 'tier default' && ok "partial tiers override: balance 500 is still tier default" || bad "partial tiers override lost the other thresholds" "$(node "$ENGINE" status)"
printf '{"max_turns":{"strict":10}}\n' > "$CLAUDE_PROJECT_DIR/vouch.config.json"
node "$ENGINE" invoke default | grep -q 'budget 40 turns' && ok "partial max_turns override keeps default at 40" || bad "default budget lost" "$(node "$ENGINE" invoke default)"
node "$ENGINE" invoke strict | grep -q 'budget 10 turns' && ok "overridden strict budget is 10" || bad "strict override not applied" "$(node "$ENGINE" invoke strict)"
rm -f "$CLAUDE_PROJECT_DIR/vouch.config.json"

echo "21. hook latency"
t0=$(date +%s%N); run receipt "$(receiptj PostToolUse Read '{"file_path":"'"$A"'"}')" >/dev/null; t1=$(date +%s%N)
ms=$(( (t1 - t0) / 1000000 )); echo "  info receipt hook ${ms}ms wall (node start-up included; machine dependent)"
avg=$(node -e 'const s=require(process.argv[1]);console.log(s.hooks_n?(s.hooks_ms/s.hooks_n).toFixed(1):"0")' "$CLAUDE_PROJECT_DIR/.vouch/sessions/t1.state.json")
[ "${avg%.*}" -lt 400 ] && ok "hooks in-process avg ${avg}ms over $(node -e 'console.log(require(process.argv[1]).hooks_n)' "$CLAUDE_PROJECT_DIR/.vouch/sessions/t1.state.json") calls" || bad "hooks slow in-process" "${avg}ms"

echo "22. parallel subagents append receipts at once: the ledger forks, nothing is voided, the lock honours every read"
export CLAUDE_SESSION_ID="t9"
S9='"session_id":"t9","cwd":"'"$CLAUDE_PROJECT_DIR"'","transcript_path":"'"$TMP/none.jsonl"'"'
for i in $(seq 1 12); do
  printf '{%s,"tool_use_id":"par%s","hook_event_name":"PostToolUse","tool_name":"Read","agent_id":"ag%s","tool_input":{"file_path":"%s"},"tool_response":{}}' "$S9" "$i" "$i" "$A" | node "$ENGINE" receipt >/dev/null 2>&1 &
done
wait
v=$(node "$ENGINE" verify t9)
echo "$v" | grep -q '^ok: 12/12' && ok "12 concurrent receipts all valid: $v" || bad "expected ok: 12/12" "$v"
forks=$(node -e 'const fs=require("fs");const rows=fs.readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean).map(JSON.parse).filter(r=>r.kind==="receipt");console.log(new Set(rows.map(r=>r.prev)).size<rows.length?"forked":"linear")' "$CLAUDE_PROJECT_DIR/.vouch/sessions/t9.jsonl")
echo "  info $forks ledger (a fork is expected under real concurrency, a linear one is fine too)"
r=$(printf '{%s,"tool_use_id":"e9","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"1","new_string":"2"}}' "$S9" "$A" | node "$ENGINE" lock; echo "exit=$?")
[ "$r" = "exit=0" ] && ok "edit allowed after a concurrently recorded read" || bad "lock denied or spoke after a concurrent read" "$r"
# a forged row (right shape, wrong signature) is void and does not void the rows chained after it
node -e 'const fs=require("fs");const p=process.argv[1];const rows=fs.readFileSync(p,"utf8").split("\n").filter(Boolean);const last=JSON.parse(rows[rows.length-1]);const forged=Object.assign({},last,{ts:last.ts+1,path:"C:/forged.js",sig:"0000000000000000"});fs.appendFileSync(p,JSON.stringify(forged)+"\n")' "$CLAUDE_PROJECT_DIR/.vouch/sessions/t9.jsonl"
printf '{%s,"tool_use_id":"after-forge","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"%s"},"tool_response":{}}' "$S9" "$A" | node "$ENGINE" receipt >/dev/null
v=$(node "$ENGINE" verify t9; echo " exit=$?")
echo "$v" | tr '\n' ' ' | grep -q 'TAMPERED.*13/14.*exit=1' && ok "forged row void, later receipt still valid: $v" || bad "expected TAMPERED 13/14 exit=1" "$v"
export CLAUDE_SESSION_ID="t1"

echo "23. non-object stdin (null, a string, an array) -> every hook exits 0; no engine exception was logged during the battery"
for body in 'null' '"x"' '[1,2]'; do for h in receipt lock guard start prompt tier; do r=$(run "$h" "$body"); echo "$r" | grep -q 'exit=0' || bad "$h with stdin $body" "$r"; done; done
[ ! -s "$VOUCH_HOME/errors.log" ] && ok "null / string / array stdin: 6 hooks x 3 bodies exit 0; errors.log (under VOUCH_HOME) empty" || bad "errors.log has entries" "$(cat "$VOUCH_HOME/errors.log")"

echo; echo "passed $pass failed $fail"; rm -rf "$TMP"; [ "$fail" -eq 0 ]
