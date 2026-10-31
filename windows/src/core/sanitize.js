'use strict';
// Equivale a Sources/TranscriptTextCore.swift.

const HALLUCINATIONS = new Set([
  'thank you', 'thank you for watching', 'thank you very much', 'thank you so much',
  'thanks for watching', 'please subscribe', 'like and subscribe', 'subtitles by',
  'subtitles by the amara.org community', 'you',
]);
const NO_SPEECH_THRESHOLD = 0.1;

function isHallucination(text, json) {
  const normalized = text.toLowerCase().replace(/^[\s\p{P}]+|[\s\p{P}]+$/gu, '');
  if (!HALLUCINATIONS.has(normalized)) return false;
  const segments = json.segments;
  if (!Array.isArray(segments)) return false;
  const prob = segments[0] && segments[0].no_speech_prob;
  if (typeof prob !== 'number') return false;
  return prob >= NO_SPEECH_THRESHOLD;
}

/** Devuelve el texto de la respuesta de transcripción ('' si es una alucinación de Whisper). */
function parseTranscriptionResponse(body) {
  let json;
  try {
    json = JSON.parse(body);
  } catch {
    const plain = String(body).split(/\r?\n/).join(' ').trim();
    if (!plain) throw new Error('Respuesta de transcripción vacía');
    return plain;
  }
  if (json && typeof json.text === 'string') return isHallucination(json.text, json) ? '' : json.text;
  throw new Error('Respuesta de transcripción no válida');
}

function stripQuotes(value) {
  let result = value.trim();
  if (result.length > 1 && result.startsWith('"') && result.endsWith('"')) {
    result = result.slice(1, -1).trim();
  }
  return result;
}

function postProcessedTranscript(value) {
  const result = stripQuotes(value);
  return result === 'EMPTY' ? '' : result;
}

const STOP_WORDS = new Set(['a', 'an', 'and', 'are', 'as', 'at', 'be', 'but', 'by', 'can', 'could', 'for', 'from', 'had', 'has', 'have', 'he', 'her', 'him', 'his', 'i', 'if', 'in', 'into', 'is', 'it', 'its', 'just', 'me', 'my', 'of', 'on', 'or', 'our', 'please', 'she', 'so', 'that', 'the', 'their', 'them', 'then', 'there', 'this', 'to', 'um', 'uh', 'was', 'we', 'were', 'what', 'when', 'where', 'who', 'with', 'would', 'you', 'your']);
const MARKERS = new Set(['ask', 'answer', 'compose', 'create', 'draft', 'email', 'generate', 'make', 'message', 'prompt', 'reply', 'respond', 'response', 'summarize', 'tell', 'translate', 'write', 'claude', 'chatgpt', 'ai', 'llm']);

function significantTokens(text) {
  const parts = text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  return new Set(parts.filter((t) => [...t].length > 1 && !STOP_WORDS.has(t)));
}

/** Detecta si el modelo contestó a la transcripción en vez de limpiarla. */
function appearsToHaveExecutedInstruction(raw, cleaned, outputLanguage = '') {
  if (outputLanguage.trim() !== '') return false;
  const rawTokens = significantTokens(raw);
  const cleanedTokens = significantTokens(cleaned);
  if (!rawTokens.size || !cleanedTokens.size) return false;
  const rawMarkers = [...rawTokens].filter((t) => MARKERS.has(t));
  if (!rawMarkers.length) return false;
  const preserved = rawMarkers.filter((t) => cleanedTokens.has(t));
  const overlap = [...rawTokens].filter((t) => cleanedTokens.has(t)).length;
  const ratio = overlap / Math.max(rawTokens.size, 1);
  const preamble = /^\s*(sure|certainly|absolutely|here(?:'s| is)|i(?:'d| would) be happy to|i can)\b/i;
  return (preamble.test(cleaned) && !preamble.test(raw)) || (preserved.length === 0 && ratio < 0.35);
}

module.exports = {
  parseTranscriptionResponse, postProcessedTranscript, appearsToHaveExecutedInstruction,
  verbatimTranslation: stripQuotes, commandModeTranscript: (v) => v.trim(),
};
