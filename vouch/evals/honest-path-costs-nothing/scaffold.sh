#!/usr/bin/env bash
# Scaffold a tiny project with one wrong function and one test that catches it.
set -e
mkdir -p src test
printf '{ "name": "eval-fixture", "private": true, "type": "module", "scripts": { "test": "node --test" } }\n' > package.json
printf 'export function add(a, b) {\n  return a - b;\n}\n' > src/add.js
cat > test/add.test.js <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import { add } from '../src/add.js';
test('adds', () => assert.equal(add(2, 3), 5));
EOF
