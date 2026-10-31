'use strict';
// Ventana oculta que graba el micrófono y manda el nivel de voz a la isla.
let stream;
let recorder;
let chunks = [];
let audioCtx;
let analyser;
let meterTimer;
let peak = 0;
let startedAt = 0;
let cancelled = false;

async function open(deviceId) {
  const audio = { echoCancellation: false, noiseSuppression: true, autoGainControl: true, channelCount: 1 };
  if (deviceId) audio.deviceId = { exact: deviceId };
  try {
    return await navigator.mediaDevices.getUserMedia({ audio });
  } catch (error) {
    if (!deviceId) throw error;
    return navigator.mediaDevices.getUserMedia({ audio: { ...audio, deviceId: undefined } });
  }
}

function startMeter() {
  audioCtx = new AudioContext();
  analyser = audioCtx.createAnalyser();
  analyser.fftSize = 512;
  audioCtx.createMediaStreamSource(stream).connect(analyser);
  const data = new Float32Array(analyser.fftSize);
  meterTimer = setInterval(() => {
    analyser.getFloatTimeDomainData(data);
    let sum = 0;
    for (const v of data) sum += v * v;
    const rms = Math.sqrt(sum / data.length);
    peak = Math.max(peak, rms);
    window.freeflow.sendLevel(Math.min(1, rms * 6));
  }, 33);
}

function release() {
  clearInterval(meterTimer);
  if (audioCtx) audioCtx.close();
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = undefined;
  audioCtx = undefined;
}

window.freeflow.onRecStart(async (deviceId) => {
  cancelled = false;
  chunks = [];
  peak = 0;
  try {
    stream = await open(deviceId);
    const mimeType = ['audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus'].find((t) => MediaRecorder.isTypeSupported(t));
    recorder = new MediaRecorder(stream, { mimeType, audioBitsPerSecond: 64000 });
    recorder.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
    startedAt = performance.now();
    recorder.start(250);
    startMeter();
  } catch (error) {
    recorder = undefined;
    release();
    startError = error;
  }
});

let startError = null;

window.freeflow.onRecStop(async (replyId) => {
  if (!recorder) {
    const message = startError ? `No se pudo abrir el micrófono: ${startError.name}` : 'No hay grabación';
    startError = null;
    window.freeflow.replyStop(replyId, { error: message, durationMs: 0, peak: 0 });
    return;
  }
  const finished = new Promise((resolve) => { recorder.onstop = resolve; });
  const durationMs = performance.now() - startedAt;
  if (recorder.state !== 'inactive') recorder.stop();
  await finished;
  const type = recorder.mimeType || 'audio/webm';
  const blob = new Blob(chunks, { type });
  const audio = new Uint8Array(await blob.arrayBuffer());
  const result = { audio, mimeType: type.split(';')[0], durationMs, peak };
  recorder = undefined;
  release();
  window.freeflow.replyStop(replyId, result);
});

window.freeflow.onRecCancel(() => {
  cancelled = true;
  if (recorder && recorder.state !== 'inactive') {
    recorder.onstop = null;
    recorder.stop();
  }
  recorder = undefined;
  release();
});
