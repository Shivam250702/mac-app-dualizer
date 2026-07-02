'use strict';

const $ = (id) => document.getElementById(id);

const drop = $('drop');
const dropEmpty = $('dropEmpty');
const dropFilled = $('dropFilled');
const appIcon = $('appIcon');
const appNameEl = $('appName');
const appIdEl = $('appId');
const appBadge = $('appBadge');
const configCard = $('configCard');
const nameEl = $('name');
const nameHint = $('nameHint');
const isolateEl = $('isolate');
const stripEl = $('stripSchemes');
const cloneBtn = $('clone');
const cloneLabel = cloneBtn.querySelector('.btn-label');
const resultCard = $('result');
const resultIcon = $('resultIcon');
const resultText = $('resultText');
const doneActions = $('doneActions');
const logEl = $('log');

let selected = null; // { path, name, bundleId, isElectron, icon }
let clonedName = null;

// ---------- selection ----------

function select(app) {
  if (!app) return;
  selected = app;
  if (app.icon) appIcon.src = app.icon;
  appNameEl.textContent = app.name;
  appIdEl.textContent = app.bundleId || 'unknown identifier';
  appBadge.textContent = app.isElectron ? 'Electron · full isolation' : 'Native · identity only';
  appBadge.className = 'badge ' + (app.isElectron ? 'electron' : 'native');

  dropEmpty.classList.add('hidden');
  dropFilled.classList.remove('hidden');
  configCard.classList.remove('is-disabled');

  if (!nameEl.value.trim()) nameEl.value = `${app.name} 2`;
  nameEl.focus();
  validate();
}

function reset() {
  selected = null;
  dropFilled.classList.add('hidden');
  dropEmpty.classList.remove('hidden');
  configCard.classList.add('is-disabled');
  cloneBtn.disabled = true;
}

$('browse').addEventListener('click', async () => {
  select(await window.dualizer.pickApp());
});
$('change').addEventListener('click', reset);

// ---------- drag & drop ----------

['dragenter', 'dragover'].forEach((ev) =>
  drop.addEventListener(ev, (e) => {
    e.preventDefault();
    drop.classList.add('drag');
  })
);
['dragleave', 'drop'].forEach((ev) =>
  drop.addEventListener(ev, (e) => {
    e.preventDefault();
    drop.classList.remove('drag');
  })
);
drop.addEventListener('drop', async (e) => {
  const file = e.dataTransfer.files[0];
  if (!file) return;
  const p = file.path || '';
  if (!p.endsWith('.app')) {
    flashHint('That doesn’t look like an .app bundle.');
    return;
  }
  select(await window.dualizer.inspectApp(p));
});

// ---------- validation ----------

nameEl.addEventListener('input', validate);

function validate() {
  const name = nameEl.value.trim();
  let msg = '';
  if (name && /["'\\]/.test(name)) msg = 'Name can’t contain quotes or backslashes.';
  else if (name && selected && name === selected.name) msg = 'Pick a different name than the original.';
  nameHint.textContent = msg;
  nameHint.classList.toggle('err', !!msg);
  cloneBtn.disabled = !(selected && name && !msg);
  return !cloneBtn.disabled;
}

function flashHint(text) {
  nameHint.textContent = text;
  nameHint.classList.add('err');
}

// ---------- clone ----------

cloneBtn.addEventListener('click', async () => {
  if (!validate()) return;
  const name = nameEl.value.trim();
  clonedName = name;

  cloneBtn.classList.add('busy');
  cloneBtn.disabled = true;
  cloneLabel.textContent = 'Cloning…';
  resultCard.classList.add('hidden');
  logEl.textContent = '';

  const result = await window.dualizer.cloneApp({
    source: selected.path,
    name,
    isolate: isolateEl.checked,
    stripSchemes: stripEl.checked,
  });

  cloneBtn.classList.remove('busy');
  cloneLabel.textContent = 'Clone app';
  cloneBtn.disabled = false;

  resultCard.classList.remove('hidden');
  if (result.ok) {
    resultIcon.textContent = '✓';
    resultIcon.className = 'result-badge ok';
    resultText.textContent = `"${name}" is ready.`;
    doneActions.classList.remove('hidden');
  } else {
    resultIcon.textContent = '✕';
    resultIcon.className = 'result-badge err';
    resultText.textContent = `Clone failed (exit ${result.code}).${result.error ? ' ' + result.error : ''}`;
    doneActions.classList.add('hidden');
  }
  resultCard.scrollIntoView({ behavior: 'smooth', block: 'end' });
});

$('launch').addEventListener('click', () => {
  if (clonedName) window.dualizer.launchApp(clonedName);
});
$('reveal').addEventListener('click', () => {
  if (selected && clonedName) {
    const dir = selected.path.slice(0, selected.path.lastIndexOf('/'));
    window.dualizer.revealApp(`${dir}/${clonedName}.app`);
  }
});

// ---------- log ----------

window.dualizer.onLog((line) => {
  const atBottom = logEl.scrollHeight - logEl.scrollTop - logEl.clientHeight < 24;
  logEl.textContent += line;
  if (atBottom) logEl.scrollTop = logEl.scrollHeight;
});
