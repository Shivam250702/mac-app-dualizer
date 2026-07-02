'use strict';

const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('node:path');
const { spawn } = require('node:child_process');
const fs = require('node:fs');

const SCRIPT = path.join(__dirname, '..', 'clone-app.sh');

function createWindow() {
  const win = new BrowserWindow({
    width: 720,
    height: 760,
    minWidth: 560,
    minHeight: 600,
    title: 'Mac App Dualizer',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  return win;
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// --- IPC ---------------------------------------------------------------------

// Let the user pick an .app from /Applications.
ipcMain.handle('pick-app', async () => {
  const res = await dialog.showOpenDialog({
    title: 'Choose an app to clone',
    defaultPath: '/Applications',
    properties: ['openFile'],
    filters: [{ name: 'Applications', extensions: ['app'] }],
  });
  if (res.canceled || res.filePaths.length === 0) return null;
  const appPath = res.filePaths[0];
  const info = readAppInfo(appPath);
  return { path: appPath, ...info };
});

// Run the clone script, streaming output back to the renderer.
ipcMain.handle('clone-app', async (event, opts) => {
  return new Promise((resolve) => {
    if (!fs.existsSync(SCRIPT)) {
      resolve({ ok: false, code: 1, error: `clone-app.sh missing at ${SCRIPT}` });
      return;
    }
    const args = [SCRIPT, '--source', opts.source, '--name', opts.name];
    if (opts.dest) args.push('--dest-dir', opts.dest);
    if (!opts.isolate) args.push('--no-isolate');
    if (opts.stripSchemes) args.push('--strip-schemes');

    const child = spawn('bash', args, { env: process.env });
    const send = (line) => event.sender.send('clone-log', line);

    child.stdout.on('data', (d) => send(d.toString()));
    child.stderr.on('data', (d) => send(d.toString()));
    child.on('error', (err) => resolve({ ok: false, code: 1, error: err.message }));
    child.on('close', (code) => resolve({ ok: code === 0, code }));
  });
});

ipcMain.handle('launch-app', async (_e, name) => {
  const child = spawn('open', ['-a', name]);
  return new Promise((r) => child.on('close', (c) => r(c === 0)));
});

ipcMain.handle('reveal-app', async (_e, appPath) => {
  shell.showItemInFolder(appPath);
});

function readAppInfo(appPath) {
  const plist = path.join(appPath, 'Contents', 'Info.plist');
  const read = (key) => {
    try {
      return require('node:child_process')
        .execFileSync('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, plist])
        .toString()
        .trim();
    } catch {
      return '';
    }
  };
  const isElectron = fs.existsSync(path.join(appPath, 'Contents', 'Resources', 'app.asar'));
  return {
    name: read('CFBundleName') || path.basename(appPath, '.app'),
    bundleId: read('CFBundleIdentifier'),
    isElectron,
  };
}
