'use strict';
//
// iconbadge.js — draw a colored badge (filled circle + white ring) in the
// bottom-right corner of every PNG in a .iconset directory, so a cloned app is
// visually distinct in the Dock and Cmd-Tab.
//
// Usage: node iconbadge.js --dir <iconset-dir> --color "#d97757"
//
// Requires the pure-JS `pngjs` package (a dependency of this project). It is
// resolved from this checkout's node_modules, from the current directory, or —
// when invoked from a bare git clone as
//   npx --yes -p pngjs node src/iconbadge.js --dir ... --color ...
// — from the npx cache. (npx only puts that cache's bin/ on PATH; its packages
// are not require()-able on their own, which used to make this step skip silently.)
//
const fs = require('node:fs');
const path = require('node:path');

function loadPngjs() {
  const starts = [__dirname, process.cwd()];
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    // "<prefix>/node_modules/.bin" -> "<prefix>", whose node_modules require() will search
    if (path.basename(dir) === '.bin' && path.basename(path.dirname(dir)) === 'node_modules') {
      starts.push(path.dirname(path.dirname(dir)));
    }
  }
  return require(require.resolve('pngjs', { paths: starts }));
}

let PNG;
try {
  ({ PNG } = loadPngjs());
} catch {
  console.error('iconbadge: pngjs not available; skipping icon badge.');
  process.exit(2);
}

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : def;
}

function hexToRgb(hex) {
  const h = hex.replace('#', '');
  const full = h.length === 3 ? h.split('').map((c) => c + c).join('') : h;
  const n = parseInt(full, 16);
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

const dir = arg('--dir');
const color = arg('--color', '#d97757');
if (!dir || !fs.existsSync(dir)) {
  console.error('iconbadge: --dir is required and must exist');
  process.exit(1);
}
const { r, g, b } = hexToRgb(color);

function badge(file) {
  const png = PNG.sync.read(fs.readFileSync(file));
  const { width, height } = png;
  if (width < 32) return; // too small to matter
  const R = Math.round(width * 0.22);
  const cx = width - R - Math.round(width * 0.07);
  const cy = height - R - Math.round(height * 0.07);
  const ring = Math.max(2, Math.round(R * 0.16));
  for (let y = Math.max(0, cy - R - ring); y < Math.min(height, cy + R + ring); y++) {
    for (let x = Math.max(0, cx - R - ring); x < Math.min(width, cx + R + ring); x++) {
      const dx = x - cx;
      const dy = y - cy;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist > R) continue;
      const idx = (width * y + x) << 2;
      if (dist > R - ring) {
        png.data[idx] = 255;
        png.data[idx + 1] = 255;
        png.data[idx + 2] = 255;
      } else {
        png.data[idx] = r;
        png.data[idx + 1] = g;
        png.data[idx + 2] = b;
      }
      png.data[idx + 3] = 255;
    }
  }
  fs.writeFileSync(file, PNG.sync.write(png));
}

let n = 0;
for (const f of fs.readdirSync(dir)) {
  if (f.toLowerCase().endsWith('.png')) {
    try {
      badge(path.join(dir, f));
      n++;
    } catch (e) {
      console.error(`iconbadge: failed on ${f}: ${e.message}`);
    }
  }
}
console.log(`iconbadge: badged ${n} image(s) with ${color}`);
