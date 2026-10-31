'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const sanitize = require('../src/core/sanitize');
const vocab = require('../src/core/vocabulary');
const styles = require('../src/core/styles');
const models = require('../src/core/models');
const pp = require('../src/core/postprocess');
const sc = require('../src/core/shortcuts');
const { transcribe } = require('../src/core/transcribe');

test('filtra alucinaciones de Whisper solo si no_speech_prob es alto', () => {
  const quiet = JSON.stringify({ text: 'Thank you.', segments: [{ no_speech_prob: 0.6 }] });
  const real = JSON.stringify({ text: 'Thank you.', segments: [{ no_speech_prob: 0.01 }] });
  assert.equal(sanitize.parseTranscriptionResponse(quiet), '');
  assert.equal(sanitize.parseTranscriptionResponse(real), 'Thank you.');
});

test('EMPTY y comillas se limpian', () => {
  assert.equal(sanitize.postProcessedTranscript('EMPTY'), '');
  assert.equal(sanitize.postProcessedTranscript('  "hola"  '), 'hola');
});

test('detecta cuando el modelo ejecuta la instrucción', () => {
  assert.equal(sanitize.appearsToHaveExecutedInstruction('write a message to john saying im late', 'Sure, here is a message: Dear John, I will be late.'), true);
  assert.equal(sanitize.appearsToHaveExecutedInstruction('write a message to john saying im late', 'Write a message to John saying I\'m late.'), false);
});

test('reemplazos fijos y restauración de mayúsculas', () => {
  assert.equal(vocab.applyStored('hola CUTMAX y kat max', { replacements: 'kat max => Cutmax', vocabulary: 'Cutmax' }), 'hola Cutmax y Cutmax');
  assert.equal(vocab.restoreCasing('usa la API', 'API'), 'usa la API');
  assert.equal(vocab.transcriptionPrompt('a, b\nc'), 'Glosario: a, b, c.');
  assert.equal(vocab.transcriptionPrompt(''), null);
});

test('clasifica la app por proceso y por título en navegadores', () => {
  assert.equal(styles.classifyGroup({}, { processName: 'WhatsApp.exe' }), 'personal');
  assert.equal(styles.classifyGroup({}, { processName: 'Slack.exe' }), 'work');
  assert.equal(styles.classifyGroup({}, { processName: 'chrome.exe', windowTitle: 'Bandeja - Gmail' }), 'email');
  assert.equal(styles.classifyGroup({}, { processName: 'notepad.exe' }), 'other');
  assert.equal(styles.classifyGroup({ extraApps: { work: ['notepad'] } }, { processName: 'notepad.exe' }), 'work');
  assert.equal(styles.classifyGroup({ removedApps: { work: ['slack'] } }, { processName: 'slack.exe' }), 'other');
});

test('Formal no añade instrucción; los demás sí', () => {
  assert.equal(styles.styleInstructionFor({}, { processName: 'slack.exe' }), null);
  const out = styles.styleInstructionFor({ styles: { personal: 'veryCasual' } }, { processName: 'telegram.exe' });
  assert.match(out, /STYLE OVERRIDE/);
  assert.match(out, /"very casual"/);
  // Un estilo que no existe en ese grupo vuelve a Formal
  assert.equal(styles.styleInstructionFor({ styles: { work: 'veryCasual' } }, { processName: 'slack.exe' }), null);
});

test('configuración de modelos', () => {
  assert.equal(models.modelConfig('gpt-oss-20b').reasoningEffort, 'low');
  assert.equal(models.modelConfig('qwen/qwen3.8-27b').stripThinkTags, true);
  assert.equal(models.stripThinkTags('<think>x</think>\nhola'), 'hola');
  assert.equal(models.stripThinkTags('<think>cortado'), '');
  assert.equal(models.responseFormat('whisper-large-v3'), 'verbose_json');
  assert.equal(models.responseFormat('gpt-4o-transcribe'), 'json');
});

test('parseo de duraciones de Groq', () => {
  assert.equal(pp.parseDuration('7.66s'), 7.66);
  assert.equal(pp.parseDuration('2m59.56s'), 179.56);
  assert.equal(pp.parseDuration('1h2m3.5s'), 3723.5);
  assert.equal(pp.parseDuration('120ms'), 0.12);
  assert.equal(pp.parseDuration('abc'), null);
});

function llmResponse(content) {
  return { ok: true, status: 200, json: async () => ({ choices: [{ message: { content } }] }), text: async () => '' };
}

test('postProcess envía el prompt con vocabulario y estilo', async () => {
  pp.clearCooldowns();
  let body;
  const svc = new pp.PostProcessingService({ apiKey: 'k', fetchImpl: async (_u, init) => { body = JSON.parse(init.body); return llmResponse('Hola, qué tal.'); } });
  const res = await svc.postProcess({ transcript: 'hola que tal', vocabulary: 'Cutmax', styleInstruction: 'STYLE OVERRIDE X' });
  assert.equal(res.transcript, 'Hola, qué tal.');
  assert.equal(body.model, 'openai/gpt-oss-20b');
  assert.equal(body.reasoning_effort, 'low');
  assert.match(body.messages[0].content, /Cutmax/);
  assert.match(body.messages[0].content, /STYLE OVERRIDE X/);
  assert.match(body.messages[1].content, /Apply the STYLE OVERRIDE/);
});

test('con 429 pasa al modelo de respaldo y registra el enfriamiento', async () => {
  pp.clearCooldowns();
  const seen = [];
  const svc = new pp.PostProcessingService({
    apiKey: 'k',
    fetchImpl: async (_u, init) => {
      const model = JSON.parse(init.body).model;
      seen.push(model);
      if (model === 'openai/gpt-oss-20b') {
        return { ok: false, status: 429, headers: new Headers({ 'retry-after': '30' }), text: async () => 'limit' };
      }
      return llmResponse('ok');
    },
  });
  assert.equal((await svc.postProcess({ transcript: 'hola' })).transcript, 'ok');
  assert.deepEqual(seen, ['openai/gpt-oss-20b', 'qwen/qwen3.8-27b']);
  assert.equal(pp.inCooldown('openai/gpt-oss-20b'), true);
  seen.length = 0;
  await svc.postProcess({ transcript: 'hola' });
  assert.deepEqual(seen, ['qwen/qwen3.8-27b']);
  pp.clearCooldowns();
});

test('si el modelo contesta en vez de limpiar, se devuelve el texto crudo', async () => {
  pp.clearCooldowns();
  const svc = new pp.PostProcessingService({ apiKey: 'k', fetchImpl: async () => llmResponse('Sure, here is the message: Dear John, I am late.') });
  const res = await svc.postProcess({ transcript: ' write a message to john saying im late ' });
  assert.equal(res.transcript, 'write a message to john saying im late');
});

test('transcribe manda multipart con modelo, idioma y glosario', async () => {
  let form;
  const text = await transcribe({
    audio: Buffer.from('x'), apiKey: 'k', language: 'es', vocabularyPrompt: 'Glosario: A.',
    fetchImpl: async (url, init) => { form = init.body; assert.match(url, /audio\/transcriptions$/); return { ok: true, status: 200, text: async () => '{"text":"hola"}' }; },
  });
  assert.equal(text, 'hola');
  assert.equal(form.get('model'), 'whisper-large-v3');
  assert.equal(form.get('language'), 'es');
  assert.equal(form.get('response_format'), 'verbose_json');
  assert.equal(form.get('prompt'), 'Glosario: A.');
});

test('atajos: mantener y soltar', () => {
  const m = new sc.ShortcutMatcher({});
  const s = new sc.SessionController();
  const run = (k, d) => m.feed(k, d).map((e) => s.handle(e)).filter(Boolean);
  assert.deepEqual(run(29, true), []);
  assert.deepEqual(run(3675, true), [{ type: 'start', mode: 'hold' }]);
  assert.deepEqual(run(3675, false), [{ type: 'stop' }]);
  run(29, false);
});

test('atajos: engancha a modo alternar al añadir Shift y para con una segunda pulsación', () => {
  const m = new sc.ShortcutMatcher({});
  const s = new sc.SessionController();
  const run = (k, d) => m.feed(k, d).map((e) => s.handle(e)).filter(Boolean);
  run(29, true); run(3675, true);
  assert.deepEqual(run(42, true), [{ type: 'switchedToToggle' }]);
  assert.deepEqual(run(42, false), []);
  run(3675, false); run(29, false);
  // segunda pulsación de la combinación larga
  run(29, true); run(3675, true);
  assert.deepEqual(run(42, true), [{ type: 'stop' }]);
});

test('atajos: etiquetas y captura', () => {
  assert.equal(sc.bindingLabel(sc.DEFAULT_HOLD), 'Ctrl + Win');
  assert.equal(sc.bindingLabel(sc.DISABLED), 'Sin atajo');
  assert.deepEqual(sc.bindingFromKeys([3675, 29, 57]), { modifiers: ['ctrl', 'meta'], key: 57 });
});

test('atajo de pegar de nuevo', () => {
  const m = new sc.ShortcutMatcher({ pasteAgain: { modifiers: ['ctrl', 'alt'], key: 47 } });
  m.feed(29, true); m.feed(56, true);
  assert.deepEqual(m.feed(47, true), ['pasteAgainActivated']);
});
