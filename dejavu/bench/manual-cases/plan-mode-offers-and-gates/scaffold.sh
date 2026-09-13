#!/usr/bin/env bash
# Scaffold a tiny Node project so the engine detects JavaScript and finds a project license.
# Shared by both eval cases; nothing here needs npm install.
set -e
mkdir -p src docs
printf '{ "name": "eval-fixture", "private": true, "version": "0.0.1", "license": "MIT", "type": "module", "dependencies": { "express": "^4.19.0" }, "scripts": { "start": "node src/server.js" } }\n' > package.json
cat > src/server.js <<'EOF'
import express from 'express';
const app = express();
app.get('/health', (req, res) => res.json({ ok: true }));
app.listen(3000);
EOF
printf 'MIT License\n\nCopyright (c) 2026 eval-fixture\n' > LICENSE
printf '# eval-fixture\n\nA small Express API used by the dejavu eval cases.\n' > README.md
