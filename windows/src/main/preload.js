'use strict';
const { contextBridge, ipcRenderer } = require('electron');

const invoke = (channel) => (...args) => ipcRenderer.invoke(channel, ...args);
const on = (channel) => (callback) => {
  const handler = (_e, ...args) => callback(...args);
  ipcRenderer.on(channel, handler);
  return () => ipcRenderer.removeListener(channel, handler);
};

contextBridge.exposeInMainWorld('freeflow', {
  getSettings: invoke('settings:get'),
  setSettings: invoke('settings:set'),
  getMeta: invoke('meta:get'),
  validateKey: invoke('api:validate'),
  captureShortcut: invoke('shortcut:capture'),
  cancelCapture: invoke('shortcut:cancel'),
  shortcutLabel: invoke('shortcut:label'),
  getHistory: invoke('history:get'),
  clearHistory: invoke('history:clear'),
  copy: invoke('clipboard:write'),
  openExternal: invoke('open:external'),
  onNavigate: on('navigate'),
  onHistoryChanged: on('history:changed'),
  // grabadora
  onRecStart: on('rec:start'),
  onRecStop: on('rec:stop'),
  onRecCancel: on('rec:cancel'),
  sendLevel: (level) => ipcRenderer.send('rec:level', level),
  replyStop: (id, payload) => ipcRenderer.send(id, payload),
  // isla
  onOverlay: on('overlay'),
  onLevel: on('level'),
  onSound: on('sound'),
});
