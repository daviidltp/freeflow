'use strict';
const ff = window.freeflow;
const $ = (id) => document.getElementById(id);
let settings;
let meta;
let labels;

const TEXT_FIELDS = ['apiKey', 'baseURL', 'transcriptionAPIURL', 'transcriptionAPIKey', 'transcriptionModel', 'llmModel', 'fallbackModel', 'language', 'outputLanguage'];
const CHECK_FIELDS = ['cleanupEnabled', 'restoreClipboard', 'playSounds', 'launchAtLogin', 'editMode'];
const AREA_FIELDS = ['vocabulary', 'replacements', 'customSystemPrompt'];

function debounce(fn, ms = 400) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

async function save(patch) {
  const result = await ff.setSettings(patch);
  settings = result.settings;
  labels = result.labels;
  renderShortcuts();
}

function showPage(page) {
  const id = ['general', 'shortcuts', 'style', 'dictionary', 'prompt', 'history'].includes(page) ? page : 'general';
  document.querySelectorAll('.page').forEach((p) => p.classList.toggle('active', p.id === `page-${id}`));
  document.querySelectorAll('#nav button').forEach((b) => b.classList.toggle('active', b.dataset.page === id));
  if (id === 'history') renderHistory();
  if (id === 'general') loadMicrophones();
  history.replaceState(null, '', `#${id}`);
}

// ----- General -----
function fillForm() {
  for (const k of TEXT_FIELDS) $(k).value = settings[k] || '';
  for (const k of CHECK_FIELDS) $(k).checked = !!settings[k];
  for (const k of AREA_FIELDS) $(k).value = settings[k] || '';
  $('baseURL').placeholder = meta.defaultBaseURL;
  $('tModels').innerHTML = meta.transcriptionModels.map((m) => `<option value="${m}">`).join('');
  $('lModels').innerHTML = meta.llmModels.map((m) => `<option value="${m}">`).join('');
  $('version').textContent = `Versión ${meta.version}`;
}

async function loadMicrophones() {
  const select = $('microphoneId');
  try {
    const probe = await navigator.mediaDevices.getUserMedia({ audio: true });
    probe.getTracks().forEach((t) => t.stop());
  } catch { /* sin permiso: se listan sin nombre */ }
  const devices = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === 'audioinput');
  select.innerHTML = '<option value="">Predeterminado del sistema</option>'
    + devices.map((d, i) => `<option value="${d.deviceId}">${(d.label || `Micrófono ${i + 1}`).replace(/</g, '&lt;')}</option>`).join('');
  select.value = settings.microphoneId || '';
}

$('saveKey').addEventListener('click', async () => {
  const status = $('keyStatus');
  status.className = 'status';
  status.textContent = 'Comprobando…';
  const patch = {
    apiKey: $('apiKey').value.trim(),
    baseURL: $('baseURL').value.trim() || meta.defaultBaseURL,
    transcriptionAPIURL: $('transcriptionAPIURL').value.trim(),
    transcriptionAPIKey: $('transcriptionAPIKey').value.trim(),
  };
  const ok = await ff.validateKey({ apiKey: patch.apiKey, baseURL: patch.baseURL });
  if (!ok) { status.className = 'status bad'; status.textContent = 'La API key no ha funcionado. Revisa la clave y la URL.'; return; }
  if (patch.transcriptionAPIURL || patch.transcriptionAPIKey) {
    const ok2 = await ff.validateKey({ apiKey: patch.transcriptionAPIKey || patch.apiKey, baseURL: patch.transcriptionAPIURL || patch.baseURL });
    if (!ok2) { status.className = 'status bad'; status.textContent = 'La API de transcripción no ha funcionado.'; return; }
  }
  await save(patch);
  status.className = 'status ok';
  status.textContent = 'Guardada. Ya puedes dictar.';
});

for (const k of ['transcriptionModel', 'llmModel', 'fallbackModel', 'language', 'outputLanguage']) {
  $(k).addEventListener('input', debounce(() => save({ [k]: $(k).value.trim() })));
}
for (const k of CHECK_FIELDS) $(k).addEventListener('change', () => save({ [k]: $(k).checked }));
for (const k of AREA_FIELDS) $(k).addEventListener('input', debounce(() => save({ [k]: $(k).value })));
$('microphoneId').addEventListener('change', () => save({ microphoneId: $('microphoneId').value }));
document.querySelectorAll('[data-link]').forEach((a) => a.addEventListener('click', (e) => { e.preventDefault(); ff.openExternal(a.dataset.link); }));

// ----- Atajos -----
function renderShortcuts() {
  document.querySelectorAll('[data-shortcut]').forEach((btn) => {
    const key = btn.dataset.shortcut;
    btn.textContent = labels[key.replace('Shortcut', '')];
  });
}

document.querySelectorAll('[data-shortcut]').forEach((btn) => {
  btn.addEventListener('click', async () => {
    btn.classList.add('capturing');
    btn.textContent = 'Pulsa la combinación…';
    const binding = await ff.captureShortcut();
    btn.classList.remove('capturing');
    if (binding) await save({ [btn.dataset.shortcut]: binding });
    else renderShortcuts();
  });
  btn.addEventListener('contextmenu', async (e) => {
    e.preventDefault();
    await save({ [btn.dataset.shortcut]: { modifiers: [], key: null } });
  });
});
$('resetShortcuts').addEventListener('click', () => save({
  holdShortcut: { modifiers: ['ctrl', 'meta'], key: null },
  toggleShortcut: { modifiers: ['ctrl', 'meta', 'shift'], key: null },
  pasteAgainShortcut: { modifiers: [], key: null },
}));

// ----- Estilo -----
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function appsOf(group) {
  const removed = (settings.removedApps || {})[group.id] || [];
  const builtIn = group.builtIn.filter((a) => !removed.includes(a));
  const extra = ((settings.extraApps || {})[group.id] || []).filter((a) => !builtIn.includes(a));
  return [...builtIn, ...extra];
}

async function moveApp(groupId, app, remove) {
  const extraApps = { ...(settings.extraApps || {}) };
  const removedApps = { ...(settings.removedApps || {}) };
  const builtInOf = (id) => meta.groups.find((g) => g.id === id).builtIn;
  for (const g of meta.groups) {
    extraApps[g.id] = (extraApps[g.id] || []).filter((a) => a !== app);
    if (builtInOf(g.id).includes(app)) {
      const list = new Set(removedApps[g.id] || []);
      if (remove || g.id !== groupId) list.add(app); else list.delete(app);
      removedApps[g.id] = [...list];
    }
  }
  if (!remove && !builtInOf(groupId).includes(app)) extraApps[groupId] = [...(extraApps[groupId] || []), app];
  await save({ extraApps, removedApps });
  renderStyles();
}

function renderStyles() {
  const root = $('groups');
  root.innerHTML = '';
  for (const group of meta.groups) {
    const chosen = group.styles.includes((settings.styles || {})[group.id]) ? settings.styles[group.id] : 'formal';
    const el = document.createElement('div');
    el.className = 'group';
    el.innerHTML = `<h2>${esc(group.title)}</h2><div class="styles">${group.styles.map((s) => `
      <button class="style ${s === chosen ? 'selected' : ''}" data-style="${s}"><b>${esc(meta.styleInfo[s].title)}</b><span>${esc(meta.styleInfo[s].summary)}</span></button>`).join('')}</div>
      <div class="apps">${appsOf(group).map((a) => `<span class="app">${esc(a)}<button data-remove="${esc(a)}" title="Quitar">×</button></span>`).join('')}
        ${group.id === 'other' ? '<span class="hint" style="margin:0">Todas las demás apps</span>' : '<input placeholder="Añadir app (ej. notepad)" data-add>'}</div>`;
    el.querySelectorAll('[data-style]').forEach((b) => b.addEventListener('click', async () => {
      await save({ styles: { ...(settings.styles || {}), [group.id]: b.dataset.style } });
      renderStyles();
    }));
    el.querySelectorAll('[data-remove]').forEach((b) => b.addEventListener('click', () => moveApp(group.id, b.dataset.remove, true)));
    const add = el.querySelector('[data-add]');
    if (add) add.addEventListener('keydown', (e) => {
      if (e.key !== 'Enter') return;
      const name = add.value.trim().toLowerCase().replace(/\.exe$/, '');
      if (name) moveApp(group.id, name, false);
    });
    root.appendChild(el);
  }
  const styleEditor = document.createElement('div');
  styleEditor.className = 'card';
  styleEditor.innerHTML = '<h2>Instrucciones de cada estilo</h2><p class="hint">Es lo que se le añade al prompt. Puedes editarlo; vacío usa el de serie.</p>';
  for (const id of ['casual', 'veryCasual', 'excited']) {
    const d = document.createElement('details');
    d.className = 'edit';
    d.innerHTML = `<summary>${esc(meta.styleInfo[id].title)}</summary><textarea rows="9" class="mono"></textarea>`;
    const ta = d.querySelector('textarea');
    ta.value = (settings.customPrompts || {})[id] || meta.styleInfo[id].instruction;
    ta.addEventListener('input', debounce(() => {
      const value = ta.value.trim();
      const customPrompts = { ...(settings.customPrompts || {}) };
      if (!value || value === meta.styleInfo[id].instruction.trim()) delete customPrompts[id]; else customPrompts[id] = value;
      save({ customPrompts });
    }));
    styleEditor.appendChild(d);
  }
  root.appendChild(styleEditor);
}

// ----- Prompt -----
$('useDefaultPrompt').addEventListener('click', () => { $('customSystemPrompt').value = meta.defaultPrompt; save({ customSystemPrompt: meta.defaultPrompt }); });
$('clearPrompt').addEventListener('click', () => { $('customSystemPrompt').value = ''; save({ customSystemPrompt: '' }); });

// ----- Historial -----
async function renderHistory() {
  const items = await ff.getHistory();
  const list = $('historyList');
  list.innerHTML = items.length ? '' : '<p class="hint">Todavía no has dictado nada.</p>';
  for (const item of items) {
    const el = document.createElement('div');
    el.className = 'item';
    el.innerHTML = `<div class="meta"><span>${new Date(item.at).toLocaleString('es-ES')}${item.app ? ` · ${esc(item.app)}` : ''}</span><button>Copiar</button></div>
      <p>${esc(item.text)}</p>
      <details><summary class="hint">Transcripción original</summary><p>${esc(item.raw)}</p></details>`;
    el.querySelector('button').addEventListener('click', (e) => { ff.copy(item.text); e.target.textContent = 'Copiado'; });
    list.appendChild(el);
  }
}
$('clearHistory').addEventListener('click', async () => { await ff.clearHistory(); renderHistory(); });

// ----- Arranque -----
document.querySelectorAll('#nav button').forEach((b) => b.addEventListener('click', () => showPage(b.dataset.page)));
ff.onNavigate(showPage);
ff.onHistoryChanged(() => { if ($('page-history').classList.contains('active')) renderHistory(); });

(async () => {
  [{ settings, labels }, meta] = await Promise.all([ff.getSettings(), ff.getMeta()]);
  fillForm();
  renderShortcuts();
  renderStyles();
  showPage(location.hash.slice(1));
})();
