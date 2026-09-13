// Runs the false-completion corpus through the claim guard: each message is a Stop (or SubagentStop)
// in its own fresh session; expected verdicts are block or pass. Exit 1 on any misclassification.
'use strict';
const fs = require('fs');
const { execFileSync } = require('child_process');
const [corpusPath, engine, proj] = process.argv.slice(2);
const corpus = JSON.parse(fs.readFileSync(corpusPath, 'utf8'));
// a fresh bankroll per corpus item: verdicts must not depend on what earlier tests did to the balance
const home = fs.mkdtempSync(require('path').join(require('os').tmpdir(), 'vouch-corpus-'));
let p = 0, f = 0;
for (const c of corpus) {
  const sid = 'c-' + c.id;
  const env = Object.assign({}, process.env, { CLAUDE_SESSION_ID: sid, VOUCH_HOME: require('path').join(home, c.id) });
  // setup: one receipt or a list of them ("cmd:<command>", "read:<project-relative file>", "failcmd:<command>"), in order
  [].concat(c.setup || []).forEach((s, i) => {
    if (s.startsWith('cmd:')) {
      execFileSync('node', [engine, 'receipt'], { input: JSON.stringify({ session_id: sid, cwd: proj, hook_event_name: 'PostToolUse', tool_name: 'Bash', tool_use_id: 's' + i + '-' + sid, tool_input: { command: s.slice(4) }, tool_response: {} }), env });
    } else if (s.startsWith('read:')) {
      const fp = require('path').join(proj, s.slice(5));
      execFileSync('node', [engine, 'receipt'], { input: JSON.stringify({ session_id: sid, cwd: proj, hook_event_name: 'PostToolUse', tool_name: 'Read', tool_use_id: 'r' + i + '-' + sid, tool_input: { file_path: fp }, tool_response: {} }), env });
    } else if (s.startsWith('failcmd:')) {
      execFileSync('node', [engine, 'receipt'], { input: JSON.stringify({ session_id: sid, cwd: proj, hook_event_name: 'PostToolUseFailure', tool_name: 'Bash', tool_use_id: 'f' + i + '-' + sid, tool_input: { command: s.slice(8) }, tool_response: { stderr: 'fail' } }), env });
    } else throw new Error('corpus ' + c.id + ': unknown setup ' + s);
  });
  const inp = { session_id: sid, cwd: proj, hook_event_name: c.event || 'Stop', stop_hook_active: false, last_assistant_message: c.msg };
  if (c.event === 'SubagentStop') { inp.agent_id = 'agx'; inp.agent_type = 'general-purpose'; }
  const outp = execFileSync('node', [engine, 'guard'], { input: JSON.stringify(inp), env }).toString();
  const blocked = /"decision":"block"/.test(outp);
  const want = c.expect === 'block';
  if (blocked === want) { p++; console.log('  ok   corpus ' + c.id); }
  else { f++; console.log('  FAIL corpus ' + c.id + ' expected ' + c.expect + ' got ' + (blocked ? 'block' : 'pass')); }
}
console.log('  corpus ' + p + '/' + (p + f));
process.exit(f ? 1 : 0);
