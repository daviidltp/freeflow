'use strict';
// Equivale a Sources/ModelConfiguration.swift.

const DEFAULT_BASE_URL = 'https://api.groq.com/openai/v1';
const DEFAULT_LLM_MODEL = 'openai/gpt-oss-20b';
const DEFAULT_FALLBACK_MODEL = 'qwen/qwen3.8-27b';
const DEFAULT_TRANSCRIPTION_MODEL = 'whisper-large-v3';
const LLM_MODELS = ['openai/gpt-oss-20b', 'openai/gpt-oss-120b', 'openai/gpt-oss-safeguard-20b', 'qwen/qwen3.8-27b'];
const TRANSCRIPTION_MODELS = ['whisper-large-v3', 'whisper-large-v3-turbo'];
const VERBOSE_JSON_MODELS = new Set(['whisper-1', 'whisper-large-v3', 'whisper-large-v3-turbo']);

const ALIASES = {
  'qwen3-32b': 'qwen/qwen3-32b',
  'qwen3.6-27b': 'qwen/qwen3.6-27b',
  'qwen3.8-27b': 'qwen/qwen3.8-27b',
  'gpt-oss-20b': 'openai/gpt-oss-20b',
  'gpt-oss-120b': 'openai/gpt-oss-120b',
  'gpt-oss-safeguard-20b': 'openai/gpt-oss-safeguard-20b',
};

function modelConfig(model) {
  let m = String(model || '').trim().toLowerCase();
  m = ALIASES[m] || m;
  const none = { maxCompletionTokens: null, reasoningEffort: null, includeReasoning: null, stripThinkTags: false };
  if (m === 'openai/gpt-oss-20b') return { ...none, maxCompletionTokens: 4096, reasoningEffort: 'low', includeReasoning: false };
  if (m === 'qwen/qwen3-32b') return { ...none, stripThinkTags: true };
  if (m === 'qwen/qwen3.8-27b' || m === 'qwen/qwen3.6-27b') {
    return { ...none, reasoningEffort: 'none', includeReasoning: false, stripThinkTags: true };
  }
  return none;
}

function nonContentRequestOptions(model, temperature) {
  const options = { model, temperature };
  const cfg = modelConfig(model);
  if (cfg.maxCompletionTokens != null) options.max_completion_tokens = cfg.maxCompletionTokens;
  else if (model === DEFAULT_LLM_MODEL) options.max_completion_tokens = 4096;
  if (cfg.reasoningEffort != null) options.reasoning_effort = cfg.reasoningEffort;
  else if (model === DEFAULT_LLM_MODEL) options.reasoning_effort = 'low';
  if (cfg.includeReasoning != null) options.include_reasoning = cfg.includeReasoning;
  else if (model === DEFAULT_LLM_MODEL) options.include_reasoning = false;
  return options;
}

function stripThinkTags(text) {
  let cleaned = String(text).replace(/^(?:\s*<think>[\s\S]*?<\/think>)+/, '');
  cleaned = cleaned.replace(/^\s*<think>[\s\S]*$/, '');
  return cleaned.trim();
}

function responseFormat(model) {
  return VERBOSE_JSON_MODELS.has(String(model || '').trim().toLowerCase()) ? 'verbose_json' : 'json';
}

module.exports = {
  DEFAULT_BASE_URL, DEFAULT_LLM_MODEL, DEFAULT_FALLBACK_MODEL, DEFAULT_TRANSCRIPTION_MODEL,
  LLM_MODELS, TRANSCRIPTION_MODELS, modelConfig, nonContentRequestOptions, stripThinkTags, responseFormat,
};
