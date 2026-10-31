'use strict';
// Equivale a Sources/VocabularyReplacements.swift.

const escapeRegExp = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const boundary = (term, flags) =>
  new RegExp(`(?<![\\p{L}\\p{N}])${escapeRegExp(term)}(?![\\p{L}\\p{N}])`, flags);

function vocabularyTerms(vocabulary) {
  return String(vocabulary || '').split(/[\n,;]/).map((t) => t.trim()).filter(Boolean);
}

/** Reglas fijas `mal => bien`, una por línea, sin distinguir mayúsculas. */
function applyReplacements(text, rules) {
  let result = text;
  for (const line of String(rules || '').split(/\r?\n/)) {
    const parts = line.split('=>');
    if (parts.length !== 2) continue;
    const wrong = parts[0].trim();
    const right = parts[1].trim();
    if (!wrong || !right) continue;
    result = result.replace(boundary(wrong, 'giu'), () => right);
  }
  return result;
}

/** Whisper a veces grita un término del glosario ("CUTMAX"): se restaura su grafía. */
function restoreCasing(text, vocabulary) {
  let result = text;
  for (const term of vocabularyTerms(vocabulary)) {
    if ([...term].length <= 1 || term === term.toUpperCase()) continue;
    result = result.replace(boundary(term.toUpperCase(), 'gu'), () => term);
  }
  return result;
}

function applyStored(text, { replacements, vocabulary }) {
  return restoreCasing(applyReplacements(text, replacements), vocabulary);
}

/** Glosario corto que se manda a Whisper como `prompt`. */
function transcriptionPrompt(vocabulary) {
  const terms = vocabularyTerms(vocabulary);
  if (!terms.length) return null;
  return `Glosario: ${terms.join(', ')}.`.slice(0, 600);
}

function dedupeTerms(vocabulary) {
  const seen = new Set();
  return vocabularyTerms(vocabulary).filter((t) => {
    const k = t.toLowerCase();
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

module.exports = { applyReplacements, restoreCasing, applyStored, transcriptionPrompt, vocabularyTerms, dedupeTerms };
