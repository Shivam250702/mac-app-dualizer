'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dualizer', {
  pickApp: () => ipcRenderer.invoke('pick-app'),
  cloneApp: (opts) => ipcRenderer.invoke('clone-app', opts),
  launchApp: (name) => ipcRenderer.invoke('launch-app', name),
  revealApp: (appPath) => ipcRenderer.invoke('reveal-app', appPath),
  onLog: (cb) => ipcRenderer.on('clone-log', (_e, line) => cb(line)),
});
