'use strict';
//
// registry.js — tiny JSON registry of clones created by this tool.
// Stored at ~/.config/mac-app-dualizer/clones.json
//
// Subcommands:
//   node registry.js add --name N --source S --dest D --isolate 1 --strip 0 --tint "#hex"
//   node registry.js list           -> prints JSON array
//   node registry.js get <name>     -> prints one entry as JSON (empty if none)
//   node registry.js remove <name>
//
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const DIR = path.join(os.homedir(), '.config', 'mac-app-dualizer');
const FILE = path.join(DIR, 'clones.json');

function load() {
  try {
    return JSON.parse(fs.readFileSync(FILE, 'utf8'));
  } catch {
    return [];
  }
}
function save(list) {
  fs.mkdirSync(DIR, { recursive: true });
  fs.writeFileSync(FILE, JSON.stringify(list, null, 2) + '\n');
}
function flag(name, def) {
  const i = process.argv.indexOf(name);
  return i !== -1 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : def;
}

const [cmd, ...rest] = process.argv.slice(2);

if (cmd === 'add') {
  const entry = {
    name: flag('--name'),
    source: flag('--source'),
    dest: flag('--dest'),
    isolate: flag('--isolate', '1') === '1',
    stripSchemes: flag('--strip', '0') === '1',
    tint: flag('--tint', ''),
    updatedAt: new Date().toISOString(),
  };
  if (!entry.name) {
    console.error('registry add: --name required');
    process.exit(1);
  }
  const list = load().filter((x) => x.name !== entry.name);
  list.push(entry);
  save(list);
} else if (cmd === 'list') {
  process.stdout.write(JSON.stringify(load(), null, 2));
} else if (cmd === 'get') {
  const e = load().find((x) => x.name === rest[0]);
  process.stdout.write(e ? JSON.stringify(e) : '');
} else if (cmd === 'remove') {
  save(load().filter((x) => x.name !== rest[0]));
} else {
  console.error(`registry: unknown command "${cmd}"`);
  process.exit(1);
}
