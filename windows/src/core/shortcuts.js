'use strict';
// Equivale a Sources/ShortcutCore: atajos de mantener-para-hablar y de alternar.
// Un atajo es { modifiers: ['ctrl','meta'], key: null | keycode de uiohook }.

const MODIFIER_KEYCODES = {
  ctrl: [29, 3613],
  alt: [56, 3640],
  shift: [42, 54],
  meta: [3675, 3676],
};
const MODIFIER_ORDER = ['ctrl', 'alt', 'shift', 'meta'];
const MODIFIER_LABELS = { ctrl: 'Ctrl', alt: 'Alt', shift: 'Shift', meta: 'Win' };

const DEFAULT_HOLD = { modifiers: ['ctrl', 'meta'], key: null };
const DEFAULT_TOGGLE = { modifiers: ['ctrl', 'meta', 'shift'], key: null };
const DISABLED = { modifiers: [], key: null };

function modifierOf(keycode) {
  for (const m of MODIFIER_ORDER) if (MODIFIER_KEYCODES[m].includes(keycode)) return m;
  return null;
}

function isDisabled(binding) {
  return !binding || ((binding.modifiers || []).length === 0 && binding.key == null);
}

function bindingLabel(binding, keyName = (k) => `#${k}`) {
  if (isDisabled(binding)) return 'Sin atajo';
  const parts = MODIFIER_ORDER.filter((m) => binding.modifiers.includes(m)).map((m) => MODIFIER_LABELS[m]);
  if (binding.key != null) parts.push(keyName(binding.key));
  return parts.join(' + ');
}

/** Sigue las teclas pulsadas y avisa cuando un atajo se activa o se suelta. */
class ShortcutMatcher {
  constructor(config) {
    this.setConfig(config);
    this.pressed = new Set();
    this.active = { hold: false, toggle: false, pasteAgain: false };
  }

  setConfig({ hold = DEFAULT_HOLD, toggle = DEFAULT_TOGGLE, pasteAgain = DISABLED } = {}) {
    this.config = { hold, toggle, pasteAgain };
  }

  _satisfied(binding) {
    if (isDisabled(binding)) return false;
    for (const m of binding.modifiers) {
      if (!MODIFIER_KEYCODES[m].some((k) => this.pressed.has(k))) return false;
    }
    return binding.key == null || this.pressed.has(binding.key);
  }

  /** Devuelve la lista de eventos: holdActivated, holdDeactivated, toggleActivated, toggleDeactivated, pasteAgainActivated. */
  feed(keycode, down) {
    if (down) this.pressed.add(keycode);
    else this.pressed.delete(keycode);
    const events = [];
    const next = {
      hold: this._satisfied(this.config.hold),
      toggle: this._satisfied(this.config.toggle),
      pasteAgain: this._satisfied(this.config.pasteAgain),
    };
    // El atajo largo (alternar) se activa antes de soltar el corto (mantener) para poder enganchar.
    for (const name of ['hold', 'toggle', 'pasteAgain']) {
      if (next[name] && !this.active[name]) events.push(`${name}Activated`);
      if (!next[name] && this.active[name]) events.push(`${name}Deactivated`);
    }
    this.active = next;
    return events;
  }

  reset() {
    this.pressed.clear();
    this.active = { hold: false, toggle: false, pasteAgain: false };
  }
}

/** Decide cuándo empezar y parar según los eventos. Igual que DictationShortcutSessionController. */
class SessionController {
  constructor() {
    this.activeMode = null;
    this.toggleStopArmed = false;
  }

  handle(event, isTranscribing = false) {
    if (this.activeMode == null) {
      if (isTranscribing) return null;
      if (event === 'toggleActivated') {
        this.activeMode = 'toggle';
        this.toggleStopArmed = false;
        return { type: 'start', mode: 'toggle' };
      }
      if (event === 'holdActivated') {
        this.activeMode = 'hold';
        this.toggleStopArmed = false;
        return { type: 'start', mode: 'hold' };
      }
      return null;
    }
    if (this.activeMode === 'hold') {
      if (event === 'toggleActivated') {
        this.activeMode = 'toggle';
        this.toggleStopArmed = false;
        return { type: 'switchedToToggle' };
      }
      if (event === 'holdDeactivated') {
        this.reset();
        return { type: 'stop' };
      }
      return null;
    }
    if (event === 'toggleDeactivated') {
      this.toggleStopArmed = true;
      return null;
    }
    if (event === 'toggleActivated' && this.toggleStopArmed) {
      this.reset();
      return { type: 'stop' };
    }
    return null;
  }

  reset() {
    this.activeMode = null;
    this.toggleStopArmed = false;
  }
}

/** Convierte las teclas pulsadas durante una captura en un atajo. */
function bindingFromKeys(keycodes) {
  const modifiers = new Set();
  let key = null;
  for (const k of keycodes) {
    const m = modifierOf(k);
    if (m) modifiers.add(m);
    else key = k;
  }
  return { modifiers: MODIFIER_ORDER.filter((m) => modifiers.has(m)), key };
}

module.exports = {
  MODIFIER_KEYCODES, DEFAULT_HOLD, DEFAULT_TOGGLE, DISABLED,
  modifierOf, isDisabled, bindingLabel, bindingFromKeys, ShortcutMatcher, SessionController,
};
