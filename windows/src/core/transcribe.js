'use strict';
// Equivale a Sources/TranscriptionService.swift.

const models = require('./models');
const sanitize = require('./sanitize');

function normalizedBaseURL(value) {
  const url = new URL(String(value || models.DEFAULT_BASE_URL).trim());
  if (!/^https?:$/.test(url.protocol)) throw new Error('La URL de la API debe empezar por http o https');
  return url.toString().replace(/\/+$/, '');
}

async function validateApiKey(key, baseURL = models.DEFAULT_BASE_URL, fetchImpl = fetch) {
  const trimmed = String(key || '').trim();
  if (!trimmed) return false;
  try {
    const response = await fetchImpl(`${normalizedBaseURL(baseURL)}/models`, {
      headers: { Authorization: `Bearer ${trimmed}` },
      signal: AbortSignal.timeout(10000),
    });
    return response.status === 200;
  } catch {
    return false;
  }
}

/** Sube el audio y devuelve el texto. `audio` es un Buffer. */
async function transcribe({ audio, fileName = 'audio.webm', mimeType = 'audio/webm', apiKey, baseURL, model, language, vocabularyPrompt, timeoutSeconds = 20, fetchImpl = fetch }) {
  const useModel = String(model || '').trim() || models.DEFAULT_TRANSCRIPTION_MODEL;
  const form = new FormData();
  form.append('file', new Blob([audio], { type: mimeType }), fileName);
  form.append('model', useModel);
  form.append('response_format', models.responseFormat(useModel));
  if (language && language.trim()) form.append('language', language.trim());
  if (vocabularyPrompt) form.append('prompt', vocabularyPrompt);
  let response;
  try {
    response = await fetchImpl(`${normalizedBaseURL(baseURL)}/audio/transcriptions`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
      signal: AbortSignal.timeout(timeoutSeconds * 1000),
    });
  } catch (e) {
    if (e && (e.name === 'TimeoutError' || e.name === 'AbortError')) {
      throw new Error(`La transcripción tardó más de ${timeoutSeconds}s`);
    }
    throw e;
  }
  const body = await response.text();
  if (!response.ok) throw new Error(`Transcripción fallida (${response.status}): ${body.slice(0, 300)}`);
  return sanitize.parseTranscriptionResponse(body);
}

module.exports = { transcribe, validateApiKey, normalizedBaseURL };
