#!/usr/bin/env node
//
// dualize — thin Node CLI wrapper around clone-app.sh.
//
// Usage:
//   node bin/dualize.js --source "/Applications/Claude.app" --name "Claude 2"
//   npx . --source "/Applications/Slack.app" --name "Slack Work"
//
// All flags are passed straight through to clone-app.sh.
//
'use strict';

const { spawn } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

const script = path.join(__dirname, '..', 'clone-app.sh');
if (!fs.existsSync(script)) {
  console.error(`clone-app.sh not found at ${script}`);
  process.exit(1);
}

if (process.platform !== 'darwin') {
  console.error('dualize only works on macOS.');
  process.exit(1);
}

const child = spawn('bash', [script, ...process.argv.slice(2)], { stdio: 'inherit' });
child.on('exit', (code) => process.exit(code ?? 1));
child.on('error', (err) => {
  console.error(err.message);
  process.exit(1);
});
