#!/usr/bin/env node
'use strict';
/*
 * vouch engine v0.2: receipts, grounding lock, claim guard, loop monitor, bankroll, tiers, report.
 * Zero dependencies. Runs as a Claude Code hook (stdin JSON) or as a CLI.
 *
 *   node vouch.js receipt        PostToolUse | PostToolUseFailure  (all tools)
 *   node vouch.js lock           PreToolUse   Edit|Write|MultiEdit|NotebookEdit|Bash
 *   node vouch.js guard          Stop | SubagentStop | TaskCompleted
 *   node vouch.js tier           PreToolUse   Agent|Edit|Write|MultiEdit (invoked mode)
 *   node vouch.js prompt         UserPromptSubmit (invoked mode)
 *   node vouch.js start          SessionStart
 *   node vouch.js invoke <tier>  called from SKILL.md dynamic context
 *   node vouch.js impossible <what> [evidence]
 *   node vouch.js handoff | report [session] | status | reset [model] | verify [session]
 *
 * Exit codes follow the Claude Code hook contract: 0 = ok (JSON on stdout is honoured),
 * 2 = block (stderr is the reason). Nothing here ever costs a model call.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const T0 = process.hrtime.bigint();

// ---------------------------------------------------------------- defaults
const DEFAULTS = {
  start_balance: 1000,
  wager_floor: 50,
  wager_cap: 500,
  win_multiplier: 0.1,
  not_verified_credit: 10,
  loop_loss: 50,
  lock_loss: 50,
  test_protect_loss: 100,
  tiers: { full: 800, default: 400, restricted: 100 },
  max_turns: { lenient: 80, default: 40, strict: 20 },
  loop_window: 3,             // same failing command N times with no edit in between
  edit_window: 6,             // same file edited N times with no command run in between (multi-hunk edits are normal)
  lock_scope: 'project',      // 'project' = only files under the project dir; 'all' = every file
  inject_every: 10,           // full budget line at least every N turns; otherwise a 10-token stub
  implicit_on_subagents: false, // completion-language rule applies to the main agent only
};

// ---------------------------------------------------------------- io helpers
function readStdin() {
  try { const buf = fs.readFileSync(0, 'utf8'); return buf.trim() ? JSON.parse(buf) : {}; } catch (e) { return {}; }
}
function readJson(p, fallback) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return fallback; } }
function writeJson(p, obj) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  const tmp = p + '.' + process.pid + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2));
  fs.renameSync(tmp, p);
}
function appendLine(p, obj) { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.appendFileSync(p, JSON.stringify(obj) + '\n'); }
function readLines(p) {
  try {
    return fs.readFileSync(p, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch (e) { return null; } }).filter(Boolean);
  } catch (e) { return []; }
}
function sha16(s) { return crypto.createHash('sha256').update(s).digest('hex').slice(0, 16); }
function fileSha(p) { try { return sha16(fs.readFileSync(p)); } catch (e) { return null; } }
function now() { return Date.now(); }
function out(obj) { process.stdout.write(JSON.stringify(obj) + '\n'); }
function trunc(s, n) { s = String(s || ''); return s.length > n ? s.slice(0, n - 1) + '…' : s; }
function clamp(n, lo, hi) { return Math.max(lo, Math.min(hi, n)); }
function elapsedMs() { return Number(process.hrtime.bigint() - T0) / 1e6; }

// ---------------------------------------------------------------- locations
function ctx(input) {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const vouchDir = path.join(projectDir, '.vouch');
  const globalDir = process.env.VOUCH_HOME || path.join(os.homedir(), '.claude', 'vouch');
  const sessionId = input.session_id || process.env.CLAUDE_SESSION_ID || 'cli';
  const cfg = Object.assign({}, DEFAULTS, readJson(path.join(projectDir, 'vouch.config.json'), {}));
  return {
    projectDir, vouchDir, globalDir, sessionId, cfg,
    ledger: path.join(vouchDir, 'sessions', sessionId + '.jsonl'),
    statePath: path.join(vouchDir, 'sessions', sessionId + '.state.json'),
    bankrollPath: path.join(globalDir, 'bankroll.json'),
    localBankrollPath: path.join(vouchDir, 'bankroll.json'),
    impossiblePath: path.join(vouchDir, 'impossible.jsonl'),
    secretPath: path.join(globalDir, 'secret'),
  };
}
function secret(c) {
  try { return fs.readFileSync(c.secretPath, 'utf8').trim(); } catch (e) {
    fs.mkdirSync(c.globalDir, { recursive: true });
    const s = crypto.randomBytes(32).toString('hex');
    fs.writeFileSync(c.secretPath, s, { mode: 0o600 });
    return s;
  }
}
// hash-chained HMAC: each receipt signs its own content AND the previous receipt's signature,
// so a receipt cannot be forged, deleted, or reordered without breaking every later signature
function sign(c, r) { return crypto.createHmac('sha256', secret(c)).update(`${r.ts}|${r.tool}|${r.hash}|${r.prev || 'genesis'}`).digest('hex').slice(0, 16); }
// v0.1 rows carry no prev field; they are verified with the unchained signature so an upgrade
// mid-session does not void a live ledger. Chained rows must reference the previous signature.
function legacySign(c, r) { return crypto.createHmac('sha256', secret(c)).update(r.ts + '|' + r.tool + '|' + r.hash).digest('hex').slice(0, 16); }
function verifiedReceipts(c) {
  const rows = readLines(c.ledger).filter((r) => r.kind === 'receipt');
  const good = [];
  let prev = 'genesis';
  let broken = null;
  for (const r of rows) {
    const legacy = r.prev === undefined;
    const valid = legacy ? r.sig === legacySign(c, r) : (r.prev === prev && r.sig === sign(c, r));
    if (!valid) { broken = broken || r.ts; break; }
    good.push(r); prev = r.sig;
  }
  return { receipts: good, broken };
}
function loadState(c) {
  return Object.assign({
    invoked: false, strictness: 'default', turns: 0, last_edit_ts: 0, stuck: 0,
    recent_cmds: [], recent_edits: [], blocked_once: {}, model: null, transcript_path: null,
    hooks_n: 0, hooks_ms: 0, last_inject: null, seen: {},
  }, readJson(c.statePath, {}));
}
// the same event can reach the engine twice when both the plugin's hooks and a settings copy are
// registered; process each tool call or stop message once, so nothing is charged twice
function seenBefore(state, key) {
  const t = now();
  for (const k of Object.keys(state.seen)) if (t - state.seen[k] > 30000) delete state.seen[k];
  if (state.seen[key]) return true;
  state.seen[key] = t;
  return false;
}
function saveState(c, s) { s.hooks_n++; s.hooks_ms += elapsedMs(); writeJson(c.statePath, s); }

// ---------------------------------------------------------------- model detection
function modelFromTranscript(tp) {
  if (!tp || !fs.existsSync(tp)) return null;
  try {
    const st = fs.statSync(tp);
    const fd = fs.openSync(tp, 'r');
    const len = Math.min(st.size, 256 * 1024);
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, st.size - len);
    fs.closeSync(fd);
    for (const l of buf.toString('utf8').split('\n').reverse()) {
      const m = /"model"\s*:\s*"([^"]+)"/.exec(l);
      if (m && !/<synthetic>/.test(m[1])) return m[1];
    }
  } catch (e) { /* fall through */ }
  return null;
}
function detectModel(input, state) {
  if (input.model) return input.model;
  // a subagent's claims settle against a separate key: its losses must never drain the lead's
  // bankroll (the transcript_path handed to subagent hooks is often the lead's, so the model name
  // is the best available label, and the /subagent suffix keeps the accounts apart)
  if (input.agent_id) return (modelFromTranscript(input.transcript_path) || state.model || 'unknown-model') + '/subagent';
  if (state.model) return state.model;
  return modelFromTranscript(input.transcript_path) || process.env.ANTHROPIC_MODEL || 'unknown-model';
}
function remember(input, state) {
  if (input.transcript_path && !input.agent_id) state.transcript_path = input.transcript_path;
  // keep probing until the transcript names the model; never cache the unknown placeholder
  if ((!state.model || /^unknown-model/.test(state.model)) && !input.agent_id) {
    const m = detectModel(input, { });
    state.model = m;
  }
  return input.agent_id ? detectModel(input, state) : state.model;
}

// ---------------------------------------------------------------- bankroll
function loadBankroll(c) { return readJson(c.bankrollPath, {}); }
function entry(bk, model, cfg) {
  if (!bk[model]) bk[model] = { balance: cfg.start_balance, wins: 0, losses: 0, backed: 0, unbacked: 0, last_loss: null, last_win: null };
  return bk[model];
}
function hitRate(e) { return (e.backed + 1) / (e.backed + e.unbacked + 2); }
function tierOf(balance, cfg) {
  if (balance >= cfg.tiers.full) return 'full';
  if (balance >= cfg.tiers.default) return 'default';
  if (balance >= cfg.tiers.restricted) return 'restricted';
  return 'broke';
}
function settle(c, model, kind, amount, note) {
  const bk = loadBankroll(c);
  const e = entry(bk, model, c.cfg);
  const ts = now();
  if (kind === 'win') { e.balance += amount; e.wins++; e.backed++; e.last_win = { ts, claim: note }; }
  else if (kind === 'loss') { e.balance -= amount; e.losses++; e.unbacked++; e.last_loss = { ts, claim: note.claim, missing: note.missing }; }
  else if (kind === 'credit') { e.balance += amount; }
  else if (kind === 'penalty') { e.balance -= amount; e.last_loss = { ts, claim: note.claim, missing: note.missing }; }
  writeJson(c.bankrollPath, bk);
  try { writeJson(c.localBankrollPath, bk); } catch (err) { /* read-only project */ }
  return e;
}
function summary(c, model) {
  const e = entry(loadBankroll(c), model, c.cfg);
  let s = `vouch: ${model} balance ${e.balance} tier ${tierOf(e.balance, c.cfg)} hit-rate ${(hitRate(e) * 100).toFixed(0)}%`;
  if (e.last_loss) s += ` | last loss: "${trunc(e.last_loss.claim, 50)}" (${trunc(e.last_loss.missing, 40)})`;
  if (e.last_win) s += ` | last win: "${trunc(e.last_win.claim, 40)}"`;
  return s;
}

// ---------------------------------------------------------------- receipts
const FILE_TOOLS = new Set(['Read', 'Edit', 'Write', 'MultiEdit', 'NotebookEdit']);
const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);
const TEST_PATH = /(^|[\\/._-])(test|tests|spec|specs|__tests__)([\\/._-]|$)/i;
const TEST_SKIP = /\b(it|test|describe)\.(skip|only)\s*\(|\bx(it|test|describe)\s*\(|@pytest\.mark\.(skip|xfail)|\bpytest\.skip\(|\bunittest\.skip|@Ignore\b|@Disabled\b|#\[ignore\]|\bt\.Skip\(/;
// one shell statement only: never let the match run across a newline or a separator
const TEST_RM = /\brm\b[^|;&\n]*\b(test|tests|spec|specs|__tests__)\b|\bgit\s+rm\b[^|;&\n]*\b(test|tests|spec)\b/i;

const READ_CMD = /(^|[;&|]\s*)(cat|head|tail|less|more|bat|type|Get-Content|gc|sed\s+-n|awk|nl|wc)\b/;
function shellReadPaths(c, cmd) {
  const found = new Set();
  for (const tok of cmd.split(/\s+/)) {
    const t = tok.replace(/^["']|["']$/g, '');
    if (!t || t.startsWith('-') || /[*?]/.test(t)) continue;
    const p = path.isAbsolute(t) ? t : path.join(c.projectDir, t);
    try { if (fs.statSync(p).isFile()) found.add(p); } catch (e) { /* not a file */ }
  }
  return [...found].slice(0, 20);
}

function makeReceipt(input, ok) {
  const tool = input.tool_name;
  const ti = input.tool_input || {};
  const r = { kind: 'receipt', ts: now(), tool, ok };
  if (input.agent_id) r.agent = input.agent_id;
  if (tool === 'Bash' || tool === 'PowerShell') {
    // keep enough of long chained commands that a receipt named from their tail still matches
    r.cmd = String(ti.command || '').slice(0, 4000);
    r.exit = ok ? 0 : 1;
    r.hash = sha16(tool + '\n' + r.cmd);
  } else if (FILE_TOOLS.has(tool) || tool === 'Grep' || tool === 'Glob') {
    r.path = ti.file_path || ti.notebook_path || ti.path || null;
    if (r.path) r.sha = fileSha(r.path);
    if (tool === 'Grep') r.cmd = 'grep:' + String(ti.pattern || '').slice(0, 120);
    if (tool === 'Glob') r.cmd = 'glob:' + String(ti.pattern || '').slice(0, 120);
    r.hash = sha16(tool + '\n' + (r.path || '') + '\n' + (r.cmd || '') + '\n' + (r.sha || ''));
  } else {
    r.hash = sha16(tool + '\n' + JSON.stringify(ti).slice(0, 400));
  }
  return r;
}

function cmdReceiptHook(input, event) {
  const c = ctx(input);
  const state = loadState(c);
  if (seenBefore(state, 'r:' + (input.tool_use_id || sha16(JSON.stringify(input.tool_input || {}) + event)))) { saveState(c, state); return; }
  const ok = event !== 'PostToolUseFailure' && !(input.tool_response && input.tool_response.is_error);
  const r = makeReceipt(input, ok);
  const rows = readLines(c.ledger).filter((x) => x.kind === 'receipt');
  r.prev = rows.length ? rows[rows.length - 1].sig : 'genesis';
  r.sig = sign(c, r);
  appendLine(c.ledger, r);
  // a shell read (cat, head, sed -n, ...) of an existing file is a read of its current content:
  // give each such file its own receipt so the grounding lock honours it
  let prevSig = r.sig;
  if (ok && r.cmd && READ_CMD.test(r.cmd)) {
    for (const p of shellReadPaths(c, r.cmd)) {
      const fr = { kind: 'receipt', ts: now(), tool: 'Bash', ok: true, path: p, sha: fileSha(p), via: 'shell-read' };
      fr.hash = sha16('Bash\n' + p + '\n' + fr.sha);
      fr.prev = prevSig; fr.sig = sign(c, fr); prevSig = fr.sig;
      appendLine(c.ledger, fr);
    }
  }
  const model = remember(input, state);
  const warnings = [];

  if (r.cmd && (r.tool === 'Bash' || r.tool === 'PowerShell')) {
    state.recent_cmds.push({ cmd: r.cmd, ok, edit_ts: state.last_edit_ts });
    state.recent_cmds = state.recent_cmds.slice(-c.cfg.loop_window);
    const w = state.recent_cmds;
    if (w.length === c.cfg.loop_window && w.every((x) => x.cmd === r.cmd && !x.ok && x.edit_ts === state.last_edit_ts)) {
      state.stuck++;
      appendLine(c.ledger, { kind: 'loop', ts: now(), rule: 'same-failing-command', detail: r.cmd, wager_lost: c.cfg.loop_loss });
      settle(c, model, 'penalty', c.cfg.loop_loss, { claim: 'loop: ' + r.cmd, missing: 'a change between attempts' });
      warnings.push(`vouch loop rule: "${trunc(r.cmd, 60)}" failed ${c.cfg.loop_window}x with no edit in between (-${c.cfg.loop_loss}, stuck=${state.stuck}). Change something or declare CLAIM: NOT VERIFIED and hand off.`);
      state.recent_cmds = [];
    }
    state._editWarned = false;
  }
  if (EDIT_TOOLS.has(r.tool)) {
    state.last_edit_ts = r.ts;
    state.recent_edits.push(r.path || '');
    state.recent_edits = state.recent_edits.slice(-c.cfg.edit_window);
    const cmdsSinceEdit = state.recent_cmds.filter((x) => x.edit_ts === state.last_edit_ts).length;
    if (state.recent_edits.length === c.cfg.edit_window && state.recent_edits.every((p) => p === r.path) && cmdsSinceEdit === 0 && !state._editWarned) {
      state._editWarned = true;
      state.stuck++;
      appendLine(c.ledger, { kind: 'loop', ts: now(), rule: 'same-file-no-test', detail: r.path, wager_lost: c.cfg.loop_loss });
      settle(c, model, 'penalty', c.cfg.loop_loss, { claim: 'loop: edits to ' + r.path, missing: 'a command run between edits' });
      warnings.push(`vouch loop rule: ${path.basename(r.path || '')} edited ${c.cfg.edit_window}x with no command run in between (-${c.cfg.loop_loss}). Run the check before the next edit.`);
    }
  }
  if (state.stuck >= 2 && !state._handoffWarned) {
    state._handoffWarned = true;
    warnings.push('vouch: stuck twice. Stop, run `node vouch.js handoff`, write what is unverifiable, and reduce the task to its verifiable subset or delegate one tier down.');
  }
  saveState(c, state);
  if (warnings.length) out({ hookSpecificOutput: { hookEventName: event, additionalContext: warnings.join('\n') } });
}

// ---------------------------------------------------------------- grounding lock + test protect + config guard
function deny(event, reason) { out({ hookSpecificOutput: { hookEventName: event, permissionDecision: 'deny', permissionDecisionReason: reason } }); }
function ask(event, reason) { out({ hookSpecificOutput: { hookEventName: event, permissionDecision: 'ask', permissionDecisionReason: reason } }); }
function underProject(c, p) {
  const n = (x) => path.resolve(String(x)).replace(/\\/g, '/').toLowerCase();
  return n(p).startsWith(n(c.projectDir) + '/');
}
function samePath(a, b) { const n = (x) => path.resolve(String(x)).replace(/\\/g, '/').toLowerCase(); return n(a) === n(b); }

function cmdLock(input) {
  const c = ctx(input);
  const state = loadState(c);
  const tool = input.tool_name;
  const ti = input.tool_input || {};
  if (seenBefore(state, 'l:' + (input.tool_use_id || sha16(tool + JSON.stringify(ti))))) { saveState(c, state); return; }
  const model = remember(input, state);
  const dev = process.env.VOUCH_DEV === '1';

  if (tool === 'Bash' || tool === 'PowerShell') {
    const cmd = String(ti.command || '');
    if (TEST_RM.test(cmd)) {
      settle(c, model, 'penalty', c.cfg.test_protect_loss, { claim: 'delete tests: ' + trunc(cmd, 80), missing: 'user authorization' });
      appendLine(c.ledger, { kind: 'incident', ts: now(), claim: 'test-protect: ' + trunc(cmd, 120), missing: 'user authorization', wager_lost: c.cfg.test_protect_loss, model });
      saveState(c, state);
      return deny('PreToolUse', `vouch test-protect: deleting tests is not a fix (-${c.cfg.test_protect_loss}). Make the test pass or declare CLAIM: NOT VERIFIED.`);
    }
    saveState(c, state);
    return;
  }
  const p = ti.file_path || ti.notebook_path;
  if (!p) return;

  if (state.invoked && !dev) {
    const norm = p.replace(/\\/g, '/');
    if (/\/\.vouch\/|\/skills\/vouch\/|\/plugins\/[^/]*vouch|\/agents\/vouch-|\/settings(\.local)?\.json$|\/hooks\/hooks\.json$/.test(norm)) {
      appendLine(c.ledger, { kind: 'incident', ts: now(), claim: 'config-guard: ' + norm, missing: 'VOUCH_DEV=1', wager_lost: 0, model });
      saveState(c, state);
      return deny('PreToolUse', 'vouch config-guard: the engine, ledger, and hook settings are read-only while vouch is armed. Ask the user to change them.');
    }
  }

  const content = String(ti.new_string || ti.content || (Array.isArray(ti.edits) ? ti.edits.map((e) => e.new_string).join('\n') : ''));
  if (TEST_PATH.test(p) && TEST_SKIP.test(content)) {
    settle(c, model, 'penalty', c.cfg.test_protect_loss, { claim: 'skip test in ' + path.basename(p), missing: 'user authorization' });
    appendLine(c.ledger, { kind: 'incident', ts: now(), claim: 'test-protect: skip/only in ' + p, missing: 'user authorization', wager_lost: c.cfg.test_protect_loss, model });
    saveState(c, state);
    return deny('PreToolUse', `vouch test-protect: skipping or focusing tests is not a fix (-${c.cfg.test_protect_loss}). Make the test pass or declare CLAIM: NOT VERIFIED.`);
  }

  if (c.cfg.lock_scope !== 'all' && !underProject(c, p)) { saveState(c, state); return; }
  const cur = fileSha(p);
  if (cur === null) { saveState(c, state); return; }
  const { receipts } = verifiedReceipts(c);
  const mine = receipts.filter((r) => r.path && samePath(r.path, p));
  const fresh = mine.some((r) => r.sha === cur);
  if (!fresh) {
    const seen = mine.length > 0;
    settle(c, model, 'penalty', c.cfg.lock_loss, { claim: 'edit ' + path.basename(p) + ' from recall', missing: 'fresh Read of ' + p });
    appendLine(c.ledger, { kind: 'incident', ts: now(), claim: 'grounding-lock: ' + p, missing: seen ? 'file changed since last read' : 'no Read this session', wager_lost: c.cfg.lock_loss, model });
    saveState(c, state);
    return deny('PreToolUse', `vouch grounding lock: Read ${p} before editing it (${seen ? 'it changed since your last read' : 'no Read receipt this session'}). Recall is not evidence (-${c.cfg.lock_loss}).`);
  }
  saveState(c, state);
}

// ---------------------------------------------------------------- tier enforcement (invoked mode)
// hooks registered from SKILL.md frontmatter exist only after /vouch was invoked, so their presence
// is proof of arming: they arm the session themselves if the dynamic invoke line never ran
function armIfNeeded(c, state, args) {
  const i = args.indexOf('--armed');
  if (i === -1 || state.invoked) return;
  let level = args[i + 1];
  // the skill's dynamic invoke line runs in a shell that may not carry the session id, so it
  // leaves the chosen strictness in a short-lived note that the first armed hook picks up
  const pendingPath = path.join(c.vouchDir, 'pending-invoke.json');
  const pending = readJson(pendingPath, null);
  if (pending && now() - pending.ts < 10 * 60 * 1000) { level = pending.strictness; try { fs.unlinkSync(pendingPath); } catch (e) { /* ignore */ } }
  state.invoked = true;
  state.strictness = ['lenient', 'default', 'strict'].includes(level) ? level : 'default';
  state.turns = 0; state.last_inject = null;
  appendLine(c.ledger, { kind: 'invoke', ts: now(), tier_arg: level || '(hook)', strictness: state.strictness, via: 'hook' });
}
function cmdTier(input, args) {
  const c = ctx(input);
  const state = loadState(c);
  armIfNeeded(c, state, args || []);
  if (!state.invoked) return;
  const model = remember(input, state);
  const e = entry(loadBankroll(c), model, c.cfg);
  const tier = tierOf(e.balance, c.cfg);
  const tool = input.tool_name;
  const ti = input.tool_input || {};
  saveState(c, state);
  if (tier === 'full') return;
  if (tool === 'Agent') {
    if (/haiku|sonnet/.test(String(ti.model || ''))) return; // the one allowed spawn: cheaper rework
    return deny('PreToolUse', `vouch tier ${tier} (balance ${e.balance}): fan-out is off. The only allowed spawn is a fresh-context rework subagent with model: haiku or sonnet carrying the handoff.`);
  }
  if (EDIT_TOOLS.has(tool)) {
    if (tier === 'default') return ask('PreToolUse', `vouch tier default (balance ${e.balance}): edits need your approval until the balance recovers through backed claims.`);
    if (tier === 'restricted' && tool === 'Write') return deny('PreToolUse', `vouch tier restricted (balance ${e.balance}): Write is denied. Edit existing files with a fresh Read, or delegate to a haiku/sonnet subagent.`);
    if (tier === 'restricted') return ask('PreToolUse', `vouch tier restricted (balance ${e.balance}): edit needs your approval.`);
    if (tier === 'broke') return deny('PreToolUse', `vouch tier broke (balance ${e.balance}): relay only. Write the handoff (node vouch.js handoff) and delegate the rework to a haiku/sonnet subagent.`);
  }
}

// ---------------------------------------------------------------- claim guard
const CLAIM_RE = /CLAIM:\s*(.+?)\s*\|\s*RECEIPT:\s*(.+?)\s*\|\s*WAGER:\s*(\d+)/gi;
const NOT_VERIFIED_RE = /CLAIM:\s*NOT VERIFIED\b[^\n]*/gi;
const IMPLICIT_RE = /\b(all (\d+ )?(tests?|assertions?|checks?|specs?|cases?) ?(now )?(pass|passed|passing|green)|(tests?|assertions?|checks?|specs?|suite)\b(?:[^.\n]|\.(?!\s)){0,60}\b(pass|passes|passed|passing|green)\b|(is|are) (now )?(fixed|working|verified|green)|works as expected|verified (that|the|it|via)|confirmed working|now works|should work|should be fine|should pass|pre-existing (bug|failure|issue)|i('m| am) confident (it|this) works|implemented and (working|tested)|fix is done and verified)\b/i;

// commands that count as a test run for auto-backing completion language
const TEST_CMD = /\b(npm|pnpm|yarn|bun)\s+(run\s+)?(test|check|lint|typecheck|build)\b|\bnode\s+--test\b|\b(pytest|jest|vitest|mocha|tox|phpunit|rspec|ctest)\b|\bcargo\s+(test|check|clippy)\b|\bgo\s+(test|vet|build)\b|\bmake\s+(test|check)\b|\bdotnet\s+test\b|\bgradle\w*\s+test\b|\bmvn\w*\s+(test|verify)\b|\bbash\s+\S*tests?\/\S*\.sh\b|\btsc\b|\beslint\b|\bruff\b|\bmypy\b/i;

// fenced blocks are examples, never claims; an inline code span is an example only if it holds a
// CLAIM line itself. Backticks around a receipt inside a real claim line are just formatting.
function stripCode(s) {
  return String(s || '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, (m) => (/CLAIM:/i.test(m) ? ' ' : m.slice(1, -1)))
    // a claim written as three lines (CLAIM: / RECEIPT: / WAGER:) is the same claim
    .replace(/\n\s*(?:[-*]\s*)?(RECEIPT|WAGER):/gi, ' | $1:');
}

function lastAssistantFromTranscript(tp) {
  if (!tp || !fs.existsSync(tp)) return '';
  try {
    for (const l of fs.readFileSync(tp, 'utf8').split('\n').filter(Boolean).reverse()) {
      if (!l.includes('"assistant"')) continue;
      const o = JSON.parse(l);
      if (o.type === 'assistant' && o.message && Array.isArray(o.message.content)) return o.message.content.filter((b) => b.type === 'text').map((b) => b.text).join('\n');
    }
  } catch (e) { /* ignore */ }
  return '';
}

const FAILURE_WORDS = /\b(fail|fails|failed|failing|error|errors|broken|does not pass|do not pass|0 passed|not passing|red|unfixable|cannot be fixed|can't be fixed|still (fails|failing|broken))\b/i;
// "4/5 passing", "3 of 4 pass": a partial ratio is a failure report by arithmetic
function reportsFailure(text) {
  if (FAILURE_WORDS.test(text)) return true;
  const m = /\b(\d+)\s*(?:\/|of|out of)\s*(\d+)\s*(?:tests?\s*|assertions?\s*|checks?\s*)?(?:pass|passing|passed)\b/i.exec(text);
  return !!(m && Number(m[1]) < Number(m[2]));
}
const FAILURE_CLAIM = { test: (t) => reportsFailure(String(t || '')) };

// a file receipt whose basename is mentioned in the text and whose recorded sha is still current
function freshFileMention(c, receipts, text) {
  const t = text.toLowerCase();
  let hit = null;
  for (const r of receipts) {
    if (!r.path || !r.sha) continue;
    const base = path.basename(r.path).toLowerCase();
    if (base.length < 4 || !t.includes(base)) continue;
    if (fileSha(r.path) === r.sha) hit = r;
  }
  return hit;
}
// the honest happy path for completion language without a claim line: any fresh successful test
// run, or any successful command / current file the message itself names
const TEST_LANGUAGE = /\b(tests?|assertions?|suite|specs?|checks?)\b[^\n]{0,60}\b(pass|passes|passed|passing|green)\b|\ball (\d+ )?(tests?|assertions?|checks?|specs?|cases?)\b/i;
function autoBacking(c, state, msg) {
  const { receipts } = verifiedReceipts(c);
  const fresh = receipts.filter((r) => r.ts > state.last_edit_ts);
  const testRuns = fresh.filter((r) => r.cmd && !r.via && TEST_CMD.test(r.cmd));
  const greenRun = testRuns.filter((r) => r.ok).pop();
  const anyRun = testRuns[testRuns.length - 1];
  // language about tests is backed only by a test run: green for a pass claim, any run if the
  // message itself reports the failure ("4/5 passing, the fifth is unfixable")
  if (TEST_LANGUAGE.test(msg)) {
    if (greenRun) return greenRun;
    if (anyRun && FAILURE_CLAIM.test(msg)) return anyRun;
    return null;
  }
  if (greenRun) return greenRun;
  const t = msg.toLowerCase();
  for (const r of fresh.filter((x) => x.ok && x.cmd && !x.via).reverse()) {
    const words = r.cmd.toLowerCase().replace(/^cd\s+\S+\s*(&&|;)\s*/, '').split(/\s+/).filter((w) => w.length > 1 && !w.startsWith('-')).slice(0, 2);
    if (words.length === 2 && t.includes(words.join(' '))) return r;
  }
  // "verified via reading x.js" style language about files
  return freshFileMention(c, receipts, msg);
}

function resolveReceipt(c, spec, state, claimText) {
  const { receipts, broken } = verifiedReceipts(c);
  const tail = broken ? ` (ledger chain broken at ${new Date(broken).toISOString()}; later receipts are void)` : '';
  spec = spec.trim().replace(/^`|`$/g, '');
  if (/^none$/i.test(spec)) return { ok: false, why: 'no receipt given' };
  // compound receipts ("file:src/a.js + cmd:npm test", "cmd:x and cmd:y"): every part must resolve
  const parts = spec.split(/\s+\+\s+|\s*;\s*|\s+and\s+(?=(?:cmd|file|read):)/i).map((s) => s.trim()).filter(Boolean);
  if (parts.length > 1) {
    let last = null;
    for (const p of parts) { const r = resolveReceipt(c, p, state, claimText); if (!r.ok) return r; last = r; }
    return last;
  }
  let m;
  if ((m = /^(?:cmd|command|ran|run):\s*(.+)$/i.exec(spec))) {
    // models append narrative after the command ("npm test -> output # pass 4"); match on the
    // longest leading word-prefix of the receipt that some command actually contains
    const full = m[1].trim().toLowerCase().replace(/^`|`$/g, '');
    const words = full.split(/\s+/);
    let needle = full, hits = [];
    // never shorten to a single word unless the receipt itself is one word ("npm" must not match "npm test")
    for (let n = words.length; n >= Math.min(2, words.length); n--) {
      const cand = words.slice(0, n).join(' ').replace(/[→"'`(),:]+$/g, '');
      if (cand.length < 3) break;
      hits = receipts.filter((r) => r.cmd && r.cmd.toLowerCase().includes(cand));
      if (hits.length) { needle = cand; break; }
    }
    if (!hits.length) return { ok: false, why: `no command containing "${trunc(words.slice(0, 3).join(' '), 40)}" ran this session${tail}` };
    const okHits = hits.filter((r) => r.ok);
    if (!okHits.length) {
      // a claim that REPORTS a failure is backed by the failed run itself ("0 passed, 1 failed")
      const failedFresh = hits.filter((r) => r.ts > state.last_edit_ts);
      if (claimText && FAILURE_CLAIM.test(claimText) && failedFresh.length) return { ok: true, hash: failedFresh[failedFresh.length - 1].hash };
      return { ok: false, why: `"${trunc(needle, 40)}" ran but failed` };
    }
    const fresh = okHits.filter((r) => r.ts > state.last_edit_ts);
    if (!fresh.length) return { ok: false, why: `"${trunc(needle, 40)}" last succeeded BEFORE your latest edit; run it again` };
    return { ok: true, hash: fresh[fresh.length - 1].hash };
  }
  if ((m = /^(?:file|read|path):\s*(.+?)(?:@([0-9a-f]{4,16}))?\s*$/i.exec(spec))) {
    // "file:src/a.js line 1", "read:src/a.js:12", "file:`src/a.js`" all mean src/a.js
    const raw = m[1].replace(/^`|`$/g, '').replace(/(?:[,\s]+(?:at\s+)?lines?\s+\d+(?:-\d+)?|:\d+(?:-\d+)?)\s*$/i, '').trim();
    const p = path.isAbsolute(raw) ? raw : path.join(c.projectDir, raw);
    const sha = (m[2] || '').toLowerCase();
    const cur = fileSha(p);
    const hits = receipts.filter((r) => r.path && samePath(r.path, p));
    if (!hits.length) return { ok: false, why: `${m[1]} was never read this session${tail}` };
    if (cur === null) return { ok: false, why: `${m[1]} does not exist now` };
    const fresh = hits.filter((r) => r.sha === cur && (!sha || r.sha.startsWith(sha)));
    if (!fresh.length) return { ok: false, why: `${m[1]} changed after your last read (current ${cur})` };
    return { ok: true, hash: fresh[fresh.length - 1].hash };
  }
  // free-form receipt ("ran npm test, output shows # pass 4"): accept it if it names a command
  // that actually succeeded after the last edit. Formatting is not the product; evidence is.
  const text = spec.toLowerCase();
  const fresh = receipts.filter((r) => r.ok && r.cmd && !r.via && r.ts > state.last_edit_ts);
  let best = null;
  for (const r of fresh) {
    const words = r.cmd.toLowerCase().replace(/^cd\s+\S+\s*(&&|;)\s*/, '').split(/\s+/).filter((w) => w.length > 1 && !w.startsWith('-')).slice(0, 3);
    if (words.length && words.every((w) => text.includes(w))) best = r;
  }
  if (best) return { ok: true, hash: best.hash };
  // ... or names a file that was read at its current content ("subagent read of src/slug.js")
  const fileHit = freshFileMention(c, receipts, text);
  if (fileHit) return { ok: true, hash: fileHit.hash };
  const named = /\b(npm|pnpm|yarn|pytest|jest|vitest|cargo|go|node|make)\b/.exec(text);
  if (named) return { ok: false, why: `no successful "${named[1]} ..." command ran after your latest edit${tail}` };
  return { ok: false, why: `receipt "${trunc(spec, 40)}" names no command that ran; use cmd:<text> or file:<path>` };
}

function cmdGuard(input, event) {
  const c = ctx(input);
  const state = loadState(c);
  const cfg = c.cfg;
  const model = remember(input, state);
  const isSub = event !== 'Stop' || !!input.agent_id;
  const raw = input.last_assistant_message || lastAssistantFromTranscript(input.transcript_path);
  if (seenBefore(state, 'g:' + event + ':' + sha16(raw) + ':' + (input.stop_hook_active ? 1 : 0))) { saveState(c, state); return; }
  const msg = stripCode(raw);
  const e = entry(loadBankroll(c), model, cfg);
  const tier = tierOf(e.balance, cfg);

  const claims = [];
  let m;
  CLAIM_RE.lastIndex = 0;
  while ((m = CLAIM_RE.exec(msg))) {
    if (/^NOT VERIFIED/i.test(m[1])) continue;
    claims.push({ text: m[1].trim(), receipt: m[2].trim(), wager: clamp(parseInt(m[3], 10) || cfg.wager_floor, cfg.wager_floor, cfg.wager_cap) });
  }
  NOT_VERIFIED_RE.lastIndex = 0;
  const notVerified = (msg.match(NOT_VERIFIED_RE) || []).map((s) => s.trim());
  const wins = [];
  const implicitAllowed = !isSub || cfg.implicit_on_subagents;
  let implicit = implicitAllowed && !claims.length && !notVerified.length && IMPLICIT_RE.test(msg);
  // completion language backed by a real, fresh, successful test run is not a false claim: settle
  // it as a backed claim at the floor wager instead of blocking (this is the honest happy path)
  if (implicit) {
    const backing = autoBacking(c, state, msg);
    if (backing) {
      const key = sha16('auto|' + backing.hash);
      if (!state.blocked_once['win:' + key]) {
        state.blocked_once['win:' + key] = true;
        const label = backing.cmd ? trunc(backing.cmd, 60) : 'read ' + path.basename(backing.path || '');
        appendLine(c.ledger, { kind: 'claim', ts: now(), text: 'implicit: ' + trunc(msg.match(IMPLICIT_RE)[0], 60), receipt: 'auto:' + label, wager: cfg.wager_floor, backed: true, matched: backing.hash, model });
        settle(c, model, 'win', Math.max(1, Math.round(cfg.wager_floor * cfg.win_multiplier * hitRate(e))), 'implicit claim backed by ' + trunc(label, 40));
        wins.push('auto');
      }
      implicit = false;
    }
  }

  const missing = [];
  for (const cl of claims) {
    const key = sha16(cl.text + '|' + cl.receipt);
    const res = resolveReceipt(c, cl.receipt, state, cl.text);
    appendLine(c.ledger, { kind: 'claim', ts: now(), text: cl.text, receipt: cl.receipt, wager: cl.wager, backed: res.ok, matched: res.hash || null, model });
    if (res.ok) {
      if (!state.blocked_once['win:' + key]) {
        state.blocked_once['win:' + key] = true;
        const gain = Math.max(1, Math.round(cl.wager * cfg.win_multiplier * hitRate(e)));
        settle(c, model, 'win', gain, cl.text);
        wins.push(cl.text);
      }
    } else missing.push({ key, claim: cl.text, why: res.why, wager: cl.wager });
  }
  if (implicit) {
    missing.push({ key: sha16('implicit|' + trunc(msg, 200)), claim: 'implicit: ' + trunc(msg.match(IMPLICIT_RE)[0], 60), why: 'no CLAIM line; completion language without a receipt', wager: cfg.wager_floor });
  }
  for (const nv of notVerified) {
    const key = sha16(nv);
    if (!state.blocked_once['nv:' + key] && tier !== 'restricted' && tier !== 'broke') {
      state.blocked_once['nv:' + key] = true;
      settle(c, model, 'credit', cfg.not_verified_credit, nv);
    }
  }

  const active = !!input.stop_hook_active;
  let block = null;
  for (const mi of missing) {
    if (state.blocked_once[mi.key]) continue; // already charged for this exact claim
    state.blocked_once[mi.key] = true;
    // charge every unbacked claim once; block the turn only if this is not already a continuation
    settle(c, model, 'loss', mi.wager, { claim: mi.claim, missing: mi.why });
    appendLine(c.ledger, { kind: 'incident', ts: now(), claim: mi.claim, missing: mi.why, wager_lost: mi.wager, model, event });
    if (!active) { block = block || []; block.push(mi); }
  }
  if (tier === 'broke' && !isSub && !state.blocked_once['broke-handoff'] && !active && !block) {
    state.blocked_once['broke-handoff'] = true;
    block = [{ claim: 'tier broke', why: `balance ${e.balance}. Run node vouch.js handoff, state what is unverifiable, and delegate rework to a haiku/sonnet subagent`, wager: 0 }];
  }
  saveState(c, state);

  if (block) {
    const lines = block.map((b) => `- "${trunc(b.claim, 80)}": ${b.why}`);
    const reason = `vouch claim guard: ${block.length} unbacked claim(s) (-${block.reduce((a, b) => a + b.wager, 0)}, balance ${entry(loadBankroll(c), model, cfg).balance}).\n${lines.join('\n')}\nProduce the receipt (run the command / read the file) and restate as CLAIM: ... | RECEIPT: cmd:<text> or file:<path> | WAGER: n, or restate as CLAIM: NOT VERIFIED - <what you could not prove>. Do not add prose without a claim line.`;
    appendLine(c.ledger, { kind: 'block', ts: now(), event, reason: trunc(reason, 300) });
    if (event === 'TaskCompleted') { process.stderr.write(reason + '\n'); process.exit(2); }
    out({ decision: 'block', reason });
    return;
  }
  if (wins.length) out({ hookSpecificOutput: { hookEventName: event, additionalContext: summary(c, model) } });
}

// ---------------------------------------------------------------- injections
function cmdStart(input) {
  const c = ctx(input);
  const state = loadState(c);
  state.model = detectModel(input, state);
  if (input.transcript_path) state.transcript_path = input.transcript_path;
  saveState(c, state);
  const line = summary(c, state.model) + ' | rule 0: recall is not evidence; Read a file before editing or claiming about it; end completion claims with CLAIM | RECEIPT | WAGER, or CLAIM: NOT VERIFIED.';
  out({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: line } });
}
function cmdPrompt(input, args) {
  const c = ctx(input);
  const state = loadState(c);
  armIfNeeded(c, state, args || []);
  if (!state.invoked) return;
  state.turns++;
  const model = remember(input, state);
  const e = entry(loadBankroll(c), model, c.cfg);
  const tier = tierOf(e.balance, c.cfg);
  const max = c.cfg.max_turns[state.strictness] || c.cfg.max_turns.default;
  const key = `${e.balance}|${tier}|${state.stuck}|${state.turns >= max}`;
  const changed = state.last_inject !== key;
  const due = state.turns % c.cfg.inject_every === 1;
  state.last_inject = key;
  saveState(c, state);
  // token economy: the full line only when something changed or every N turns; otherwise a stub
  if (!changed && !due) {
    out({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: `vouch ${e.balance} ${tier} t${state.turns}/${max}` } });
    return;
  }
  const imp = readLines(c.impossiblePath).slice(-3).map((x) => `IMPOSSIBLE: ${trunc(x.what, 60)}`);
  const parts = [
    `vouch armed (${state.strictness}) | ${model} balance ${e.balance} tier ${tier} | turn ${state.turns}/${max}${state.stuck ? ' | stuck ' + state.stuck : ''}`,
    'rule 0: recall is not evidence. End every completion/verification statement with CLAIM: <what> | RECEIPT: cmd:<text> or file:<path> | WAGER: <50-500>; NOT VERIFIED is a rewarded claim.',
  ];
  if (e.last_loss) parts.push(`last loss: "${trunc(e.last_loss.claim, 50)}" (${trunc(e.last_loss.missing, 40)})`);
  if (state.turns >= max) parts.push('BUDGET EXHAUSTED: stop, run node vouch.js handoff, and reduce the task to its verifiable subset.');
  if (tier === 'default') parts.push('tier default: edits prompt the user; no fan-out.');
  if (tier === 'restricted') parts.push('tier restricted: Write and fan-out denied; every claim needs a receipt.');
  if (tier === 'broke') parts.push('tier broke: relay only; delegate rework to a haiku/sonnet subagent with the handoff.');
  parts.push(...imp);
  out({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: parts.join('\n') } });
}

// ---------------------------------------------------------------- cli commands
function cliCtx() { return ctx({ session_id: process.env.CLAUDE_SESSION_ID, cwd: process.env.CLAUDE_PROJECT_DIR }); }
function cmdInvoke(args) {
  const c = cliCtx();
  const state = loadState(c);
  const arg = (args[0] || 'default').toLowerCase();
  state.invoked = true;
  state.strictness = ['lenient', 'default', 'strict'].includes(arg) ? arg : 'default';
  state.turns = 0; state.last_inject = null;
  saveState(c, state);
  appendLine(c.ledger, { kind: 'invoke', ts: now(), tier_arg: arg, strictness: state.strictness });
  writeJson(path.join(c.vouchDir, 'pending-invoke.json'), { ts: now(), strictness: state.strictness });
  process.stdout.write(`${summary(c, state.model || 'this model')} | strictness ${state.strictness} | budget ${c.cfg.max_turns[state.strictness]} turns\n`);
}
function cmdImpossible(args) {
  const c = cliCtx();
  appendLine(c.impossiblePath, { ts: now(), agent: process.env.CLAUDE_AGENT_ID || c.sessionId, what: args[0] || '', evidence: args.slice(1).join(' ') });
  process.stdout.write('recorded IMPOSSIBLE: ' + (args[0] || '') + '\n');
}
function cmdHandoff() {
  const c = cliCtx();
  const rows = readLines(c.ledger);
  const cmds = rows.filter((r) => r.kind === 'receipt' && r.cmd).slice(-15).map((r) => `- ${r.ok ? 'ok ' : 'FAIL'} ${trunc(r.cmd, 100)}`);
  const edits = [...new Set(rows.filter((r) => r.kind === 'receipt' && EDIT_TOOLS.has(r.tool)).map((r) => r.path))].map((p) => `- ${p}`);
  const unbacked = rows.filter((r) => r.kind === 'incident').slice(-10).map((r) => `- ${trunc(r.claim, 100)} (missing: ${trunc(r.missing, 60)})`);
  const loops = rows.filter((r) => r.kind === 'loop').map((r) => `- ${r.rule}: ${trunc(r.detail, 80)}`);
  const p = path.join(c.vouchDir, `handoff-${c.sessionId}.md`);
  fs.mkdirSync(c.vouchDir, { recursive: true });
  fs.writeFileSync(p, `# vouch handoff (${new Date().toISOString()})\n\n## Commands tried (last 15)\n${cmds.join('\n') || '- none'}\n\n## Files edited\n${edits.join('\n') || '- none'}\n\n## Unbacked claims / incidents\n${unbacked.join('\n') || '- none'}\n\n## Loops tripped\n${loops.join('\n') || '- none'}\n\n## What is unverifiable (fill in)\n- \n\n## Verifiable subset to hand over\n- \n`);
  appendLine(c.ledger, { kind: 'abort', ts: now(), reason: 'handoff', handoff_path: p });
  process.stdout.write(p + '\n');
}
function cmdStatus() {
  const c = cliCtx();
  const bk = loadBankroll(c);
  const models = Object.keys(bk);
  if (!models.length) { process.stdout.write('vouch: no bankroll yet (start ' + c.cfg.start_balance + ')\n'); return; }
  for (const mname of models) {
    const e = bk[mname];
    process.stdout.write(`${mname.padEnd(30)} balance ${String(e.balance).padStart(5)}  tier ${tierOf(e.balance, c.cfg).padEnd(10)} backed ${e.backed} unbacked ${e.unbacked} hit-rate ${(hitRate(e) * 100).toFixed(0)}%\n`);
  }
}
function cmdReset(args) {
  const c = cliCtx();
  const bk = loadBankroll(c);
  if (args[0]) delete bk[args[0]]; else for (const k of Object.keys(bk)) delete bk[k];
  writeJson(c.bankrollPath, bk);
  try { writeJson(c.localBankrollPath, bk); } catch (e) { /* ignore */ }
  process.stdout.write('vouch: bankroll reset\n');
}
function cmdVerify(args) {
  const c = ctx({ session_id: args[0] || process.env.CLAUDE_SESSION_ID, cwd: process.env.CLAUDE_PROJECT_DIR });
  const { receipts, broken } = verifiedReceipts(c);
  const total = readLines(c.ledger).filter((r) => r.kind === 'receipt').length;
  process.stdout.write(broken ? `TAMPERED: chain breaks at ${new Date(broken).toISOString()}; ${receipts.length}/${total} receipts valid\n` : `ok: ${receipts.length}/${total} receipts valid, chain intact\n`);
  process.exit(broken ? 1 : 0);
}
// the measurement: what the session cost and what vouch did about it
function cmdReport(args) {
  const c = ctx({ session_id: args[0] || process.env.CLAUDE_SESSION_ID, cwd: process.env.CLAUDE_PROJECT_DIR });
  const state = loadState(c);
  const rows = readLines(c.ledger);
  const claims = rows.filter((r) => r.kind === 'claim');
  const incidents = rows.filter((r) => r.kind === 'incident');
  const blocks = rows.filter((r) => r.kind === 'block');
  const loops = rows.filter((r) => r.kind === 'loop');
  const receipts = rows.filter((r) => r.kind === 'receipt');
  const firstBlock = blocks.length ? blocks[0].ts : null;
  let turns = 0, inTok = 0, outTok = 0, cacheRead = 0, cacheWrite = 0, reworkOut = 0, model = state.model;
  const tp = state.transcript_path;
  if (tp && fs.existsSync(tp)) {
    for (const l of fs.readFileSync(tp, 'utf8').split('\n')) {
      if (!l.includes('"assistant"') || !l.includes('"usage"')) continue;
      try {
        const o = JSON.parse(l);
        if (o.type !== 'assistant' || !o.message || !o.message.usage) continue;
        const u = o.message.usage; turns++;
        inTok += u.input_tokens || 0; outTok += u.output_tokens || 0;
        cacheRead += u.cache_read_input_tokens || 0; cacheWrite += u.cache_creation_input_tokens || 0;
        model = o.message.model || model;
        const ts = o.timestamp ? Date.parse(o.timestamp) : 0;
        if (firstBlock && ts && ts > firstBlock) reworkOut += u.output_tokens || 0;
      } catch (e) { /* skip */ }
    }
  }
  const lines = [
    `vouch report  session ${c.sessionId}  model ${model || 'unknown'}`,
    `assistant turns      ${turns}${tp ? '' : '   (no transcript path recorded; run at least one hook in the session)'}`,
    `tokens in/out        ${inTok} / ${outTok}   cache read/write ${cacheRead} / ${cacheWrite}`,
    `output after 1st block ${reworkOut}   (rework proxy: tokens spent after vouch first blocked a claim)`,
    `receipts             ${receipts.length}   hooks ${state.hooks_n} avg ${state.hooks_n ? (state.hooks_ms / state.hooks_n).toFixed(1) : '0'} ms in-process`,
    `claims backed/unbacked ${claims.filter((x) => x.backed).length} / ${claims.filter((x) => !x.backed).length}   implicit ${incidents.filter((x) => /^implicit/.test(x.claim)).length}`,
    `lock denials         ${incidents.filter((x) => /^grounding-lock/.test(x.claim)).length}   test-protect ${incidents.filter((x) => /^test-protect/.test(x.claim)).length}   loops ${loops.length}   blocks ${blocks.length}`,
    `coins lost           ${incidents.reduce((a, x) => a + (x.wager_lost || 0), 0) + loops.reduce((a, x) => a + (x.wager_lost || 0), 0)}`,
  ];
  process.stdout.write(lines.join('\n') + '\n');
}

// ---------------------------------------------------------------- main
function main() {
  const [cmd, ...args] = process.argv.slice(2);
  try {
    switch (cmd) {
      case 'receipt': { const i = readStdin(); return cmdReceiptHook(i, i.hook_event_name || 'PostToolUse'); }
      case 'lock': return cmdLock(readStdin());
      case 'tier': return cmdTier(readStdin(), args);
      case 'guard': { const i = readStdin(); return cmdGuard(i, i.hook_event_name || 'Stop'); }
      case 'start': return cmdStart(readStdin());
      case 'prompt': return cmdPrompt(readStdin(), args);
      case 'invoke': return cmdInvoke(args);
      case 'impossible': return cmdImpossible(args);
      case 'handoff': return cmdHandoff();
      case 'status': return cmdStatus();
      case 'reset': return cmdReset(args);
      case 'verify': return cmdVerify(args);
      case 'report': return cmdReport(args);
      default: process.stdout.write('usage: vouch.js receipt|lock|tier|guard|start|prompt|invoke|impossible|handoff|status|reset|verify|report\n');
    }
  } catch (e) {
    try { fs.appendFileSync(path.join(os.homedir(), '.claude', 'vouch', 'errors.log'), new Date().toISOString() + ' ' + cmd + ' ' + (e && e.stack || e) + '\n'); } catch (_) { /* ignore */ }
    process.exit(0); // a broken hook must never break the session
  }
}
main();
