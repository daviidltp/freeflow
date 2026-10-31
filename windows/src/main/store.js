'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { app, safeStorage } = require('electron');
const shortcuts = require('../core/shortcuts');
const models = require('../core/models');

const DEFAULTS = {
  apiKey: '',
  baseURL: models.DEFAULT_BASE_URL,
  transcriptionAPIURL: '',
  transcriptionAPIKey: '',
  transcriptionModel: models.DEFAULT_TRANSCRIPTION_MODEL,
  llmModel: models.DEFAULT_LLM_MODEL,
  fallbackModel: '',
  language: '',
  outputLanguage: '',
  cleanupEnabled: true,
  customSystemPrompt: '',
  vocabulary: '',
  replacements: '',
  holdShortcut: shortcuts.DEFAULT_HOLD,
  toggleShortcut: shortcuts.DEFAULT_TOGGLE,
  pasteAgainShortcut: shortcuts.DISABLED,
  editMode: false,
  restoreClipboard: true,
  playSounds: true,
  launchAtLogin: false,
  microphoneId: '',
  styles: {},
  customPrompts: {},
  extraApps: {},
  removedApps: {},
  timeouts: { transcription: 20, postProcessing: 20 },
};

const SECRET_KEYS = ['apiKey', 'transcriptionAPIKey'];

class Store {
  constructor(dir = app.getPath('userData')) {
    this.file = path.join(dir, 'settings.json');
    this.historyFile = path.join(dir, 'history.json');
    this.data = { ...DEFAULTS };
    this.load();
  }

  load() {
    try {
      const raw = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      for (const key of Object.keys(DEFAULTS)) if (key in raw) this.data[key] = raw[key];
      for (const key of SECRET_KEYS) this.data[key] = this._decrypt(raw[key]);
    } catch {
      /* primer arranque */
    }
  }

  _encrypt(value) {
    if (!value) return '';
    if (safeStorage.isEncryptionAvailable()) return `enc:${safeStorage.encryptString(value).toString('base64')}`;
    return `raw:${value}`;
  }

  _decrypt(value) {
    if (!value) return '';
    if (value.startsWith('enc:')) {
      try { return safeStorage.decryptString(Buffer.from(value.slice(4), 'base64')); } catch { return ''; }
    }
    return value.startsWith('raw:') ? value.slice(4) : '';
  }

  save() {
    const out = { ...this.data };
    for (const key of SECRET_KEYS) out[key] = this._encrypt(this.data[key]);
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    fs.writeFileSync(this.file, JSON.stringify(out, null, 2));
  }

  get(key) { return this.data[key]; }
  all() { return { ...this.data }; }

  set(patch) {
    for (const key of Object.keys(patch)) if (key in DEFAULTS) this.data[key] = patch[key];
    this.save();
  }

  // Historial (solo local)
  history() {
    try { return JSON.parse(fs.readFileSync(this.historyFile, 'utf8')); } catch { return []; }
  }

  addHistory(item) {
    const items = [item, ...this.history()].slice(0, 100);
    fs.writeFileSync(this.historyFile, JSON.stringify(items, null, 2));
    return items;
  }

  clearHistory() { fs.writeFileSync(this.historyFile, '[]'); }
}

module.exports = { Store, DEFAULTS };
