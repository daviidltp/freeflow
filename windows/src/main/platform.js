'use strict';
// Todo lo que toca el sistema: ventana activa, portapapeles y pegado.
const { clipboard } = require('electron');
const { uIOhook, UiohookKey } = require('uiohook-napi');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const TERMINALS = new Set(['windowsterminal', 'cmd', 'powershell', 'pwsh', 'conhost', 'wezterm-gui', 'alacritty', 'mintty']);

async function activeApp() {
  try {
    const mod = await import('active-win');
    const win = await (mod.default || mod.activeWindow)();
    if (!win) return {};
    const exe = win.owner && win.owner.path ? win.owner.path.split(/[\\/]/).pop() : '';
    return {
      appName: win.owner && win.owner.name,
      processName: exe.replace(/\.exe$/i, '').toLowerCase(),
      windowTitle: win.title,
    };
  } catch {
    return {};
  }
}

const isTerminal = (processName) => TERMINALS.has(String(processName || '').toLowerCase());

function tapCtrl(key) {
  uIOhook.keyTap(key, [UiohookKey.Ctrl]);
}

/** Pega `text` en el campo activo con Ctrl+V y, si se pide, devuelve el portapapeles anterior. */
async function pasteText(text, { restore = true } = {}) {
  const previous = restore ? clipboard.readText() : null;
  clipboard.writeText(text);
  await sleep(40);
  tapCtrl(UiohookKey.V);
  if (restore) {
    await sleep(500);
    // Solo se restaura si nadie ha copiado nada mientras tanto.
    if (clipboard.readText() === text) clipboard.writeText(previous || '');
  }
}

/** Copia la selección actual con Ctrl+C y la devuelve ('' si no hay). */
async function readSelection() {
  const previous = clipboard.readText();
  const marker = `__freeflow_${Date.now()}__`;
  clipboard.writeText(marker);
  tapCtrl(UiohookKey.C);
  await sleep(180);
  const selected = clipboard.readText();
  clipboard.writeText(previous);
  return selected === marker ? '' : selected;
}

module.exports = { activeApp, isTerminal, pasteText, readSelection, sleep };
