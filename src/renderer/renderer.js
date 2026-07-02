'use strict';

const $ = (id) => document.getElementById(id);

const sourceEl = $('source');
const nameEl = $('name');
const appInfoEl = $('appInfo');
const isolateEl = $('isolate');
const stripEl = $('stripSchemes');
const cloneBtn = $('clone');
const logEl = $('log');
const doneActions = $('doneActions');
const launchBtn = $('launch');
const revealBtn = $('reveal');

let selected = null; // { path, name, bundleId, isElectron }
let clonedName = null;
let clonedPath = null;

function refreshCloneEnabled() {
  cloneBtn.disabled = !(selected && nameEl.value.trim());
}

function appendLog(text) {
  const atBottom = logEl.scrollHeight - logEl.scrollTop - logEl.clientHeight < 20;
  logEl.textContent += text;
  if (atBottom) logEl.scrollTop = logEl.scrollHeight;
}

$('browse').addEventListener('click', async () => {
  const app = await window.dualizer.pickApp();
  if (!app) return;
  selected = app;
  sourceEl.value = app.path;
  appInfoEl.textContent = app.isElectron
    ? `Electron app · ${app.bundleId || 'unknown id'} · full isolation supported`
    : `Native app · ${app.bundleId || 'unknown id'} · identity change only (data may be shared)`;
  if (!nameEl.value.trim()) nameEl.value = `${app.name} 2`;
  refreshCloneEnabled();
});

nameEl.addEventListener('input', refreshCloneEnabled);

cloneBtn.addEventListener('click', async () => {
  if (!selected) return;
  const name = nameEl.value.trim();
  if (/["'\\]/.test(name)) {
    appendLog('\nError: name must not contain quotes or backslashes.\n');
    return;
  }
  cloneBtn.disabled = true;
  doneActions.classList.add('hidden');
  logEl.textContent = '';
  clonedName = name;
  clonedPath = null;

  const result = await window.dualizer.cloneApp({
    source: selected.path,
    name,
    isolate: isolateEl.checked,
    stripSchemes: stripEl.checked,
  });

  if (result.ok) {
    appendLog(`\n✓ Clone created: "${name}"\n`);
    doneActions.classList.remove('hidden');
  } else {
    appendLog(`\n✗ Clone failed (exit ${result.code}). ${result.error || ''}\n`);
  }
  cloneBtn.disabled = false;
});

launchBtn.addEventListener('click', () => {
  if (clonedName) window.dualizer.launchApp(clonedName);
});

revealBtn.addEventListener('click', () => {
  // Reveal by re-deriving the .app path from the source's folder + clone name.
  if (selected && clonedName) {
    const dir = selected.path.slice(0, selected.path.lastIndexOf('/'));
    window.dualizer.revealApp(`${dir}/${clonedName}.app`);
  }
});

window.dualizer.onLog((line) => appendLog(line));
