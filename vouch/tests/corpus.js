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
  if (c.setup && c.setup.startsWith('cmd:')) {
    execFileSync('node', [engine, 'receipt'], { input: JSON.stringify({ session_id: sid, cwd: proj, hook_event_name: 'PostToolUse', tool_name: 'Bash', tool_use_id: 's-' + sid, tool_input: { command: c.setup.slice(4) }, tool_response: {} }), env });
  }
  if (c.setup && c.setup.startsWith('read:')) {
    const fp = require('path').join(proj, c.setup.slice(5));
    execFileSync('node', [engine, 'receipt'], { input: JSON.stringify({ session_id: sid, cwd: proj, hook_event_name: 'PostToolUse', tool_name: 'Read', tool_use_id: 'r-' + sid, tool_input: { file_path: fp }, tool_response: {} }), env });
  }
  if (c.setup && c.setup.startsWith('failcmd:')) {
    execFileSync('node', [engine, 'receipt'], { input: JSON.stringify({ session_id: sid, cwd: proj, hook_event_name: 'PostToolUseFailure', tool_name: 'Bash', tool_use_id: 'f-' + sid, tool_input: { command: c.setup.slice(8) }, tool_response: { stderr: 'fail' } }), env });
  }
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
