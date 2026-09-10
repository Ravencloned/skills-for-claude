# Third-party notices

vouch's engine (`scripts/vouch.js`) is original code. The contract prose in `SKILL.md` and the
agent contract in `agents/vouch-verifier.md` adapt ideas and short phrasings from the MIT-licensed
projects below. No file was copied verbatim. Attribution is kept here as the MIT license asks.

| project | license | what vouch reuses |
|---|---|---|
| obra/superpowers | MIT | the verification-before-completion "iron law"; "rulings, not stalls" and the four stop conditions; the ban on performative agreement |
| addyosmani/agent-skills | MIT | the "ASSUMPTIONS I'M MAKING" pre-flight block; "push back when warranted" |
| AlethiaQuizForge/claude-guard-hooks | MIT | the shape of a Stop guard that checks completion language against a command ledger |
| SteelDynamite/pi-read-before-write | MIT | read-before-edit with a content fingerprint |
| Pinperepette/grounded | MIT | "assume the model is wrong, verify everything" framing for the grounding lock |
| midego1/claude-orchestrate | MIT | the evidence-or-FAIL verifier contract, verifier one tier below the producer, the 3-dispatch cap, typed failure triage |
| ekamphuis82/claude-code-swarm | MIT | the inline floor and cost gate before any fan-out |
| kenn-io/kata | MIT | single-writer ledger keys |
| affaan-m/everything-claude-code | MIT | the rationalization-phrase list behind the implicit-claim regex |
| karanb192/claude-code-hooks | MIT | protect-tests and config-guard patterns |
| drona23/claude-token-efficient | MIT | the "do not guess APIs, versions, SHAs" line |

Re-implemented from a description only, no code reused: Chorus-AIDLC/Chorus (AGPL-3.0) hook wiring
for agent teams; anthropics/claude-code ralph-wiggum (Anthropic terms) Stop-hook loop pattern.

Research citations are listed in `reference.md`.
