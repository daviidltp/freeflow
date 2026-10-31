'use strict';
const path = require('node:path');
const { app, BrowserWindow, Tray, Menu, ipcMain, screen, shell, session, nativeImage, clipboard } = require('electron');
const { uIOhook, UiohookKey } = require('uiohook-napi');

const { Store } = require('./store');
const platform = require('./platform');
const shortcuts = require('../core/shortcuts');
const models = require('../core/models');
const prompts = require('../core/prompts');
const styles = require('../core/styles');
const vocabulary = require('../core/vocabulary');
const { transcribe, validateApiKey } = require('../core/transcribe');
const { PostProcessingService } = require('../core/postprocess');

const ICON = path.join(__dirname, '../../assets/icon.png');
const RENDERER = (file) => path.join(__dirname, '../renderer', file);
const PRELOAD = path.join(__dirname, 'preload.js');
const MIN_RECORDING_MS = 350;

if (!app.requestSingleInstanceLock()) app.quit();

let store;
let tray;
let settingsWin;
let overlayWin;
let recorderWin;
let matcher;
const session_ = new shortcuts.SessionController();
let state = 'idle'; // idle | recording | processing
let startContext = Promise.resolve({});
let lastResult = '';
let capture = null; // { resolve, pressed:Set, peak:Set }
let injecting = false;

const keyNames = Object.fromEntries(Object.entries(UiohookKey).map(([name, code]) => [code, name]));
const keyName = (code) => keyNames[code] || `#${code}`;

// ---------- ventanas ----------
function webPreferences() {
  return { preload: PRELOAD, contextIsolation: true, nodeIntegration: false, sandbox: false };
}

function createRecorder() {
  recorderWin = new BrowserWindow({ show: false, webPreferences: { ...webPreferences(), backgroundThrottling: false } });
  recorderWin.loadFile(RENDERER('recorder.html'));
}

function createOverlay() {
  overlayWin = new BrowserWindow({
    width: 300, height: 64, show: false, frame: false, transparent: true, resizable: false, movable: false,
    focusable: false, skipTaskbar: true, alwaysOnTop: true, hasShadow: false, webPreferences: webPreferences(),
  });
  overlayWin.setAlwaysOnTop(true, 'screen-saver');
  overlayWin.setIgnoreMouseEvents(true);
  overlayWin.loadFile(RENDERER('overlay.html'));
}

function placeOverlay() {
  const area = screen.getPrimaryDisplay().workArea;
  const [w, h] = overlayWin.getSize();
  overlayWin.setPosition(Math.round(area.x + (area.width - w) / 2), Math.round(area.y + area.height - h - 24));
}

function overlay(message) {
  if (!overlayWin || overlayWin.isDestroyed()) return;
  overlayWin.webContents.send('overlay', message);
  if (message.state === 'hidden') {
    setTimeout(() => { if (state === 'idle' && !overlayWin.isDestroyed()) overlayWin.hide(); }, 250);
  } else {
    placeOverlay();
    overlayWin.showInactive();
  }
}

function openSettings(page) {
  if (settingsWin && !settingsWin.isDestroyed()) {
    settingsWin.show();
    settingsWin.focus();
    if (page) settingsWin.webContents.send('navigate', page);
    return;
  }
  settingsWin = new BrowserWindow({
    width: 980, height: 680, minWidth: 760, minHeight: 520, title: 'FreeFlow', icon: ICON,
    backgroundColor: '#f6f4ef', autoHideMenuBar: true, webPreferences: webPreferences(),
  });
  settingsWin.setMenu(null);
  settingsWin.loadFile(RENDERER('settings.html'), { hash: page || '' });
  settingsWin.webContents.setWindowOpenHandler(({ url }) => { shell.openExternal(url); return { action: 'deny' }; });
}

function createTray() {
  tray = new Tray(nativeImage.createFromPath(ICON).resize({ width: 16, height: 16 }));
  tray.setToolTip('FreeFlow');
  tray.on('click', () => openSettings());
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Abrir FreeFlow', click: () => openSettings() },
    { label: 'Pegar el último dictado', click: () => pasteAgain() },
    { type: 'separator' },
    { label: 'Salir', click: () => app.quit() },
  ]));
}

// ---------- atajos globales ----------
function shortcutConfig() {
  return {
    hold: store.get('holdShortcut'),
    toggle: store.get('toggleShortcut'),
    pasteAgain: store.get('pasteAgainShortcut'),
  };
}

function onKey(keycode, down) {
  if (injecting) return;
  if (capture) return captureKey(keycode, down);
  if (down && keycode === UiohookKey.Escape && state === 'recording') return cancelRecording();
  for (const event of matcher.feed(keycode, down)) {
    if (event === 'pasteAgainActivated') { pasteAgain(); continue; }
    const action = session_.handle(event, state === 'processing');
    if (!action) continue;
    if (action.type === 'start') startRecording();
    else if (action.type === 'stop') stopRecording();
  }
}

function captureKey(keycode, down) {
  if (down) {
    if (keycode === UiohookKey.Escape) { const c = capture; capture = null; c.resolve(null); return; }
    capture.pressed.add(keycode);
    capture.peak.add(keycode);
  } else {
    capture.pressed.delete(keycode);
    if (capture.pressed.size === 0 && capture.peak.size > 0) {
      const c = capture;
      capture = null;
      c.resolve(shortcuts.bindingFromKeys([...c.peak]));
    }
  }
}

function startKeyboard() {
  matcher = new shortcuts.ShortcutMatcher(shortcutConfig());
  uIOhook.on('keydown', (e) => onKey(e.keycode, true));
  uIOhook.on('keyup', (e) => onKey(e.keycode, false));
  uIOhook.start();
}

// ---------- dictado ----------
function sound(name) {
  if (store.get('playSounds') && overlayWin && !overlayWin.isDestroyed()) overlayWin.webContents.send('sound', name);
}

function startRecording() {
  if (state !== 'idle') return;
  if (!store.get('apiKey')) {
    session_.reset();
    overlay({ state: 'error', message: 'Falta la API key. Ábrela en los ajustes.' });
    setTimeout(() => overlay({ state: 'hidden' }), 3500);
    openSettings('general');
    return;
  }
  state = 'recording';
  startContext = platform.activeApp();
  recorderWin.webContents.send('rec:start', store.get('microphoneId'));
  overlay({ state: 'recording' });
  sound('dictation-start');
}

function cancelRecording() {
  session_.reset();
  state = 'idle';
  recorderWin.webContents.send('rec:cancel');
  overlay({ state: 'hidden' });
}

async function stopRecording() {
  if (state !== 'recording') return;
  state = 'processing';
  sound('dictation-stop');
  overlay({ state: 'processing' });
  try {
    const recording = await ipcInvoke(recorderWin, 'rec:stop');
    if (recording && recording.error) throw new Error(recording.error);
    if (!recording || recording.durationMs < MIN_RECORDING_MS || recording.peak < 0.01) {
      state = 'idle';
      return overlay({ state: 'hidden' });
    }
    await runPipeline(recording);
    state = 'idle';
    overlay({ state: 'hidden' });
  } catch (error) {
    state = 'idle';
    session_.reset();
    overlay({ state: 'error', message: friendlyError(error) });
    setTimeout(() => { if (state === 'idle') overlay({ state: 'hidden' }); }, 4500);
  }
}

function friendlyError(error) {
  const message = (error && error.message) || String(error);
  if (/\b401\b/.test(message)) return 'La API key no es válida.';
  if (/\b429\b|rate-limited/.test(message)) return 'Límite de peticiones alcanzado. Prueba en un minuto.';
  if (/fetch failed|ENOTFOUND|network/i.test(message)) return 'Sin conexión.';
  return message.length > 110 ? `${message.slice(0, 107)}…` : message;
}

// Espera a que el usuario suelte Ctrl/Win/Shift/Alt para que el pegado no se mezcle con sus teclas.
async function waitForModifiersReleased() {
  for (let i = 0; i < 30; i += 1) {
    const held = [...matcher.pressed].some((k) => shortcuts.modifierOf(k));
    if (!held) return;
    await platform.sleep(50);
  }
}

async function paste(text) {
  await waitForModifiersReleased();
  injecting = true;
  try {
    await platform.pasteText(text, { restore: store.get('restoreClipboard') });
  } finally {
    injecting = false;
    matcher.reset();
  }
  sound('paste');
}

async function runPipeline(recording) {
  const s = store.all();
  const apiKey = s.transcriptionAPIKey || s.apiKey;
  const transcriptionURL = s.transcriptionAPIURL || s.baseURL;
  const raw = await transcribe({
    audio: Buffer.from(recording.audio),
    mimeType: recording.mimeType,
    fileName: `audio.${recording.mimeType.includes('ogg') ? 'ogg' : 'webm'}`,
    apiKey,
    baseURL: transcriptionURL,
    model: s.transcriptionModel,
    language: s.language,
    vocabularyPrompt: vocabulary.transcriptionPrompt(s.vocabulary),
    timeoutSeconds: s.timeouts.transcription,
  });
  if (!raw.trim()) return;

  const context = await startContext;
  const contextSummary = [context.appName && `App: ${context.appName}`, context.windowTitle && `Window: ${context.windowTitle}`]
    .filter(Boolean).join('\n');
  const llm = new PostProcessingService({
    apiKey: s.apiKey, baseURL: s.baseURL, model: s.llmModel, fallbackModel: s.fallbackModel, timeoutSeconds: s.timeouts.postProcessing,
  });

  // Modo edición: si hay texto seleccionado, la voz es una orden sobre ese texto.
  if (s.editMode && !platform.isTerminal(context.processName)) {
    await waitForModifiersReleased();
    injecting = true;
    let selected = '';
    try { selected = await platform.readSelection(); } finally { injecting = false; matcher.reset(); }
    if (selected.trim()) {
      const edited = await llm.commandTransform({
        selectedText: selected, voiceCommand: raw, contextSummary, vocabulary: s.vocabulary, outputLanguage: s.outputLanguage,
      });
      return finish(raw, edited.transcript, context, edited.prompt);
    }
  }

  let cleaned = raw.trim();
  let prompt = '';
  if (s.cleanupEnabled) {
    const result = await llm.postProcess({
      transcript: raw, contextSummary, vocabulary: s.vocabulary, customSystemPrompt: s.customSystemPrompt,
      outputLanguage: s.outputLanguage, dictationLanguage: s.language,
      styleInstruction: styles.styleInstructionFor(s, context),
    });
    cleaned = result.transcript;
    prompt = result.prompt;
  } else if (s.outputLanguage.trim()) {
    const result = await llm.translateVerbatim({ transcript: raw, targetLanguage: s.outputLanguage });
    cleaned = result.transcript;
    prompt = result.prompt;
  }
  return finish(raw, cleaned, context, prompt);
}

async function finish(raw, cleaned, context, prompt) {
  const s = store.all();
  const finalText = vocabulary.applyStored(cleaned, { replacements: s.replacements, vocabulary: s.vocabulary });
  if (!finalText.trim()) return;
  lastResult = finalText;
  store.addHistory({
    id: Date.now(), at: new Date().toISOString(), raw, text: finalText, app: context.appName || '', prompt,
  });
  if (settingsWin && !settingsWin.isDestroyed()) settingsWin.webContents.send('history:changed');
  await paste(finalText);
}

async function pasteAgain() {
  const text = lastResult || (store.history()[0] || {}).text;
  if (text) await paste(text);
}

// ---------- IPC ----------
function ipcInvoke(win, channel) {
  return new Promise((resolve, reject) => {
    const id = `${channel}:${Date.now()}`;
    const timer = setTimeout(() => reject(new Error('No se pudo cerrar la grabación')), 8000);
    ipcMain.once(id, (_e, payload) => { clearTimeout(timer); resolve(payload); });
    win.webContents.send(channel, id);
  });
}

function applySettings() {
  matcher.setConfig(shortcutConfig());
  matcher.reset();
  try { app.setLoginItemSettings({ openAtLogin: !!store.get('launchAtLogin') }); } catch { /* sin permiso */ }
}

function labels() {
  const s = store.all();
  return {
    hold: shortcuts.bindingLabel(s.holdShortcut, keyName),
    toggle: shortcuts.bindingLabel(s.toggleShortcut, keyName),
    pasteAgain: shortcuts.bindingLabel(s.pasteAgainShortcut, keyName),
  };
}

function registerIpc() {
  ipcMain.handle('settings:get', () => ({ settings: store.all(), labels: labels() }));
  ipcMain.handle('settings:set', (_e, patch) => { store.set(patch); applySettings(); return { settings: store.all(), labels: labels() }; });
  ipcMain.handle('meta:get', () => ({
    defaultPrompt: prompts.DEFAULT_SYSTEM_PROMPT,
    llmModels: models.LLM_MODELS,
    transcriptionModels: models.TRANSCRIPTION_MODELS,
    defaultBaseURL: models.DEFAULT_BASE_URL,
    groups: styles.STYLE_GROUPS.map((id) => ({
      id, title: styles.GROUP_TITLES[id], styles: styles.AVAILABLE_STYLES[id], builtIn: styles.BUILT_IN_APPS[id],
    })),
    styleInfo: Object.fromEntries(Object.keys(styles.STYLE_TITLES).map((id) => [id, {
      title: styles.STYLE_TITLES[id], summary: styles.STYLE_SUMMARIES[id], instruction: styles.STYLE_INSTRUCTIONS[id],
    }])),
    version: app.getVersion(),
  }));
  ipcMain.handle('api:validate', (_e, { apiKey, baseURL }) => validateApiKey(apiKey, baseURL || models.DEFAULT_BASE_URL));
  ipcMain.handle('shortcut:capture', () => new Promise((resolve) => {
    session_.reset();
    capture = { resolve, pressed: new Set(), peak: new Set() };
  }));
  ipcMain.handle('shortcut:cancel', () => { if (capture) { const c = capture; capture = null; c.resolve(null); } });
  ipcMain.handle('shortcut:label', (_e, binding) => shortcuts.bindingLabel(binding, keyName));
  ipcMain.handle('history:get', () => store.history());
  ipcMain.handle('history:clear', () => { store.clearHistory(); return []; });
  ipcMain.handle('clipboard:write', (_e, text) => clipboard.writeText(String(text)));
  ipcMain.handle('open:external', (_e, url) => { if (/^https:\/\//.test(url)) shell.openExternal(url); });
  ipcMain.on('rec:level', (_e, level) => {
    if (overlayWin && !overlayWin.isDestroyed()) overlayWin.webContents.send('level', level);
  });
}

// ---------- arranque ----------
app.on('second-instance', () => openSettings());
app.on('window-all-closed', () => { /* sigue en la bandeja */ });

app.whenReady().then(() => {
  store = new Store();
  session.defaultSession.setPermissionRequestHandler((_wc, permission, cb) => cb(permission === 'media'));
  session.defaultSession.setPermissionCheckHandler((_wc, permission) => permission === 'media');
  registerIpc();
  createRecorder();
  createOverlay();
  createTray();
  startKeyboard();
  applySettings();
  if (!store.get('apiKey') || !app.getLoginItemSettings().wasOpenedAtLogin) openSettings(store.get('apiKey') ? '' : 'general');
});

app.on('will-quit', () => { try { uIOhook.stop(); } catch { /* ya parado */ } });
