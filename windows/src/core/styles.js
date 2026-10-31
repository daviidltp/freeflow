'use strict';
// Equivale a Sources/WritingStyle.swift. En Windows las apps se reconocen por el
// nombre del .exe (en Mac era el identificador de bundle).

const STYLE_GROUPS = ['personal', 'work', 'email', 'other'];

const GROUP_TITLES = {
  personal: 'Personal messages',
  work: 'Work messages',
  email: 'Email',
  other: 'Other',
};

const AVAILABLE_STYLES = {
  personal: ['formal', 'casual', 'veryCasual'],
  work: ['formal', 'casual', 'excited'],
  email: ['formal', 'casual', 'excited'],
  other: ['formal', 'casual', 'excited'],
};

// Nombres de proceso (sin .exe, en minúsculas).
const BUILT_IN_APPS = {
  personal: ['whatsapp', 'telegram', 'discord', 'signal', 'messenger', 'viber', 'line'],
  work: ['slack', 'teams', 'ms-teams', 'zoom', 'linear', 'webex'],
  email: ['outlook', 'olk', 'thunderbird', 'mailspring', 'superhuman', 'hxoutlook'],
  other: [],
};

const STYLE_TITLES = { formal: 'Formal.', casual: 'Casual', veryCasual: 'very casual', excited: 'Excited!' };
const STYLE_SUMMARIES = {
  formal: 'Caps + Punctuation',
  casual: 'Caps + Less punctuation',
  veryCasual: 'No Caps + Less punctuation',
  excited: 'More exclamations',
};

const STYLE_INSTRUCTIONS = {
  formal: null,
  casual: `- Capitalize the first word of each sentence and proper nouns as usual.
- Do not put a period at the end of the message, nor at the end of a line or list item.
- Keep commas exactly where normal writing would put them.
- Always keep accents and diacritics (á, é, í, ó, ú, ñ, ü), including on question words like "qué", "cómo" and "cuándo".
- Keep question marks and exclamation marks at the end of a sentence, but never write the opening Spanish marks ¿ and ¡.
- These rules apply to every line, including list items.
Examples:
"Hey, are you free for lunch tomorrow? Let's do 12 if that works for you." -> "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you"
"Hola, ¿qué tal? Te escribo luego." -> "Hola, qué tal? Te escribo luego"`,
  veryCasual: `- Write everything in lowercase: the first word of every sentence, of every line and of every list item, and the pronoun "I". Keep capitals only in vocabulary terms, acronyms and brand names.
- Do not put a period at the end of the message, nor at the end of a line or list item.
- Keep commas exactly where normal writing would put them.
- Always keep accents and diacritics (á, é, í, ó, ú, ñ, ü), including on question words like "qué", "cómo" and "cuándo".
- Keep question marks and exclamation marks at the end of a sentence, but never write the opening Spanish marks ¿ and ¡.
- These rules apply to every line, including list items and the line that introduces a list.
Examples:
"Hey, are you free for lunch tomorrow? Let's do 12 if that works for you." -> "hey, are you free for lunch tomorrow? let's do 12 if that works for you"
"Hola, ¿qué tal? Te escribo luego." -> "hola, qué tal? te escribo luego"
"¿Cómo estás? Estoy en casa, ¿vienes?" -> "cómo estás? estoy en casa, vienes?"
"Lista de la compra: plátanos, aceite, agua." -> "lista de la compra: plátanos, aceite, agua"`,
  excited: `- Keep normal capitalization and punctuation.
- End sentences that express enthusiasm, thanks, congratulations or good news with an exclamation mark instead of a period.
- Use exclamation marks naturally, not on every sentence, and never add emoji.
Examples:
"Hey, if you're free, let's chat about the great results." -> "Hey, if you're free, let's chat about the great results!"
"Gracias por la ayuda, me ha encantado." -> "¡Gracias por la ayuda, me ha encantado!"`,
};

const BROWSER_KEYS = ['safari', 'chrome', 'firefox', 'arc', 'brave', 'edge', 'opera', 'vivaldi', 'comet', 'msedge'];
const WEB_TITLE_RULES = [
  ['email', ['gmail', 'outlook', 'proton mail', 'yahoo mail', 'icloud mail', 'fastmail', 'hey.com']],
  ['work', ['slack', 'microsoft teams', 'linkedin', 'google chat', 'linear']],
  ['personal', ['whatsapp', 'telegram', 'discord', 'messenger', 'instagram', 'signal', 'imessage']],
];

function stylePromptInstruction(style, group, customBody) {
  const defaultBody = STYLE_INSTRUCTIONS[style];
  if (!defaultBody) return null;
  const trimmed = (customBody || '').trim();
  const body = trimmed || defaultBody;
  const name = STYLE_TITLES[style].replace(/^[.!]+|[.!]+$/g, '');
  return `STYLE OVERRIDE (highest priority). The user chose the "${name}" writing style for this destination (${GROUP_TITLES[group]}). It replaces every earlier rule about capitalization, sentence punctuation and final periods, including "fix punctuation, capitalization" and "use normal sentence punctuation". Follow it exactly:
${body}
The style changes only capitalization, the final period and the opening ¿ ¡ marks. Never add, remove or reword content, never change accents, and keep the spelling of vocabulary terms, commands and file paths.`;
}

/**
 * Clasifica la app donde se dicta. `prefs` = { styles, customPrompts, extraApps, removedApps }.
 */
function classifyGroup(prefs, { appName, processName, windowTitle }) {
  const proc = String(processName || '').toLowerCase().replace(/\.exe$/, '');
  const extra = prefs.extraApps || {};
  const removed = prefs.removedApps || {};
  if (proc) {
    for (const g of STYLE_GROUPS) if ((extra[g] || []).includes(proc)) return g;
    for (const g of STYLE_GROUPS) {
      if (BUILT_IN_APPS[g].includes(proc) && !(removed[g] || []).includes(proc)) return g;
    }
    if (STYLE_GROUPS.some((g) => (removed[g] || []).includes(proc))) return 'other';
  }
  const lowerName = String(appName || '').toLowerCase();
  const isBrowser = BROWSER_KEYS.some((k) => proc.includes(k) || lowerName.includes(k));
  if (isBrowser && windowTitle) {
    const title = windowTitle.toLowerCase();
    for (const [group, keys] of WEB_TITLE_RULES) if (keys.some((k) => title.includes(k))) return group;
  }
  const hay = `${proc} ${lowerName}`;
  const has = (keys) => keys.some((k) => hay.includes(k));
  if (has(['whatsapp', 'telegram', 'discord', 'signal'])) return 'personal';
  if (has(['slack', 'teams', 'zoom'])) return 'work';
  if (has(['outlook', 'thunderbird', 'superhuman', 'mailspring'])) return 'email';
  return 'other';
}

function styleFor(prefs, group) {
  const chosen = (prefs.styles || {})[group];
  return AVAILABLE_STYLES[group].includes(chosen) ? chosen : 'formal';
}

/** Instrucción de estilo para el dictado en esta app, o null si es Formal. */
function styleInstructionFor(prefs, app) {
  const group = classifyGroup(prefs, app);
  const style = styleFor(prefs, group);
  return stylePromptInstruction(style, group, (prefs.customPrompts || {})[style]);
}

module.exports = {
  STYLE_GROUPS, GROUP_TITLES, AVAILABLE_STYLES, BUILT_IN_APPS, STYLE_TITLES, STYLE_SUMMARIES, STYLE_INSTRUCTIONS,
  classifyGroup, styleFor, styleInstructionFor, stylePromptInstruction,
};
