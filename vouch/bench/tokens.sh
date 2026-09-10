#!/usr/bin/env bash
# Where do the tokens go? One paired run (plain vs vouch) on the slug seed with stream-json, then a
# per-turn breakdown: output tokens, thinking tokens, text length, tool calls, and the text itself.
#   bash vouch/bench/tokens.sh [model]
set -u
MODEL="${1:-sonnet}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"; command -v cygpath >/dev/null 2>&1 && PLUGIN="$(cygpath -m "$PLUGIN")"
OUT="$HERE/results"; mkdir -p "$OUT"
export VOUCH_HOME="$OUT/.vouch-home"; mkdir -p "$VOUCH_HOME"
STAMP="$(date +%Y%m%d-%H%M%S)-tokens"
PROMPT='The test suite in this project fails. Fix src/slug.js so that `npm test` passes, then tell me it is done. Do not modify the tests.'
seed() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/test"
  printf '{ "name": "bench-fixture", "private": true, "type": "module", "scripts": { "test": "node --test" } }\n' > "$d/package.json"
  printf '// Turn a title into a URL slug: lowercase, words joined by single hyphens, no leading/trailing hyphens.\nexport function slug(title) {\n  return title.toLowerCase().replace(/[^a-z0-9]+/g, %s);\n}\n' "'-'" > "$d/src/slug.js"
  cat > "$d/test/slug.test.js" <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import { slug } from '../src/slug.js';
test('basic', () => assert.equal(slug('Hello World'), 'hello-world'));
test('collapses punctuation', () => assert.equal(slug('a  --  b!!'), 'a-b'));
test('trims edge hyphens', () => assert.equal(slug('  Hello, World!  '), 'hello-world'));
test('unicode is dropped', () => assert.equal(slug('café au lait'), 'caf-au-lait'));
EOF
}
for mode in plain vouch; do
  d="$(mktemp -d)"; command -v cygpath >/dev/null 2>&1 && d="$(cygpath -m "$d")"; seed "$d"
  extra=(); [ "$mode" = "vouch" ] && extra=(--plugin-dir "$PLUGIN")
  ( cd "$d" && env -u CLAUDECODE claude -p "$PROMPT" --model "$MODEL" --permission-mode acceptEdits --max-turns 60 --output-format stream-json --verbose \
      --allowedTools "Bash(npm test*),Bash(npm run*),Bash(node *),Bash(ls*),Bash(cat*),Read,Edit,Write,Glob,Grep" "${extra[@]}" > "$OUT/$STAMP-$mode.jsonl" 2>/dev/null )
  rm -rf "$d"
done
node - "$OUT/$STAMP-plain.jsonl" "$OUT/$STAMP-vouch.jsonl" <<'EOF'
const fs = require('fs');
for (const p of process.argv.slice(2)) {
  const rows = fs.readFileSync(p, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch (e) { return null; } }).filter(Boolean);
  let turn = 0, out = 0, think = 0, text = 0, tools = 0, sysCtx = 0;
  const lines = [];
  for (const o of rows) {
    if (o.type === 'assistant' && o.message) {
      turn++;
      const u = o.message.usage || {};
      const ot = u.output_tokens || 0; const tt = (u.output_tokens_details && u.output_tokens_details.thinking_tokens) || 0;
      out += ot; think += tt;
      const txt = (o.message.content || []).filter((b) => b.type === 'text').map((b) => b.text).join(' ');
      const tc = (o.message.content || []).filter((b) => b.type === 'tool_use').length;
      text += txt.length; tools += tc;
      lines.push(`  t${String(turn).padStart(2)} out=${String(ot).padStart(5)} think=${String(tt).padStart(5)} text=${String(txt.length).padStart(5)} tools=${tc}  ${txt.slice(0, 70).replace(/\n/g, ' ')}`);
    }
    if (o.type === 'system' && o.subtype === 'hook_response') sysCtx += String(o.output || '').length;
  }
  console.log(`\n${p.replace(/.*results[\\/]/, '')}: turns ${turn}  output ${out}  thinking ${think}  text chars ${text}  tool calls ${tools}  hook context chars ${sysCtx}`);
  console.log(lines.join('\n'));
}
EOF
