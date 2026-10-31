<p align="center">
  <img src="Resources/AppIcon-Source.png" width="128" height="128" alt="FreeFlow icon">
</p>

<h1 align="center">FreeFlow</h1>

<p align="center">
  Free and open source alternative to <a href="https://wisprflow.ai">Wispr Flow</a>, <a href="https://superwhisper.com">Superwhisper</a>, and <a href="https://monologue.to">Monologue</a>.
</p>

<p align="center">
  <sub>Fork de <a href="https://github.com/zachlatta/freeflow">zachlatta/freeflow</a> con mejoras propias · Apple Silicon e Intel</sub>
</p>

---

<p align="center">
  <img src="Resources/demo.gif" alt="FreeFlow demo" width="600">
</p>

<p align="center">
  <i>Thank you to <a href="https://github.com/marcbodea">@marcbodea</a> for maintaining FreeFlow!</i>
</p>

## Overview

FreeFlow is a free Mac dictation app inspired by [Wispr Flow](https://wisprflow.ai/), [Superwhisper](https://superwhisper.com/), and [Monologue](https://www.monologue.to/). It gives you fast AI transcription, context-aware cleanup, and voice-driven text editing without a monthly subscription.

## Windows

Hay una versión para Windows 10 y 11 con las mismas funciones. Se descarga como instalador `.exe` desde [Releases](https://github.com/daviidltp/freeflow/releases) (las que empiezan por `windows-v`). Instrucciones y diferencias con el Mac en [windows/README.md](windows/README.md).

## Instalación

Esta versión no está firmada ni notarizada por Apple (no hay cuenta de pago detrás), así que **no hay un `.dmg` que descargar**: la compilas en tu Mac con un solo comando y macOS no la bloquea.

**Qué diferencia a este fork del original:** el vocabulario personalizado se envía también a Whisper y se aplican reemplazos fijos tras la limpieza, se restaura la capitalización de los términos cuando Whisper los grita en mayúsculas, hay icono en blanco y negro y las actualizaciones apuntan a este repo.

### Requisitos

- Un Mac con macOS 13 o superior.
- Las herramientas de línea de comandos de Apple. Si no las tienes: `xcode-select --install`.
- Una API key gratuita de [Groq](https://console.groq.com/keys) (o cualquier proveedor compatible con OpenAI).

### Pasos

```bash
git clone https://github.com/daviidltp/freeflow.git
cd freeflow
./install.sh
```

El script compila la app (un par de minutos la primera vez), la copia a `/Applications` y la abre.

### Primer arranque

1. Concede los permisos que pide: **Micrófono**, **Accesibilidad** (para pegar el texto) y **Reconocimiento de voz**.
2. Pega tu API key de Groq en los ajustes.
3. Mantén pulsada `Fn` para hablar, o pulsa `Command-Fn` para empezar y parar. El texto se pega en el campo activo.

### Si algo falla

- **"No se puede abrir porque no se puede verificar al desarrollador"**: solo pasa si has copiado la app desde otro Mac. Ejecuta `xattr -dr com.apple.quarantine /Applications/FreeFlow.app` o haz clic derecho → Abrir.
- **Los permisos desaparecen tras recompilar**: al firmar sin identidad (ad-hoc) macOS trata cada compilación como una app nueva. Vuelve a conceder Micrófono y Accesibilidad en Ajustes del Sistema → Privacidad y seguridad (quita la entrada vieja y añade la nueva).
- **Actualizar**: `git pull && ./install.sh`.

### Modificarla

Es código abierto (MIT). Haz tu propio fork, cámbialo (con Claude Code, Codex o a mano) y vuelve a ejecutar `./install.sh`. Más detalles en [CONTRIBUTING.md](CONTRIBUTING.md).

## Features

- **Custom shortcuts:** Customize both hold-to-talk and toggle dictation shortcuts. If your toggle shortcut extends your hold shortcut, you can start in hold mode and press the extra modifier keys to latch into tap mode without stopping the recording.
- **Context-aware cleanup:** FreeFlow can read nearby app context so names, terms, and phrases are spelled correctly when you dictate into email, terminals, docs, and other apps.
- **Original-field insertion (opt in):** Enable **Insert into the original field** in Settings → General → Text insertion to keep dictation tied to its starting field when switching windows. This is off by default and applies to new dictations; otherwise dictation pastes into the currently focused field. Changed or unavailable fields and unconfirmed writes leave the transcript available through Paste Again rather than risking a misplaced or duplicate paste. Paste fallback, or Enter when an editor loses background focus, may briefly activate the original app before restoring your previous focus.
- **Custom vocabulary:** Add names, jargon, and project-specific words that FreeFlow should preserve during cleanup.
- **OpenAI-compatible providers:** Use Groq by default, or configure a custom model and API URL in settings.

## Edit Mode

Edit Mode lets you highlight existing text and transform it with a spoken instruction, like "make this shorter" or "turn this into bullets." Enable it in settings, then use your normal dictation shortcut on selected text, or choose Manual mode to require an extra modifier key.

## Privacy

There is no FreeFlow server, so FreeFlow does not store or retain your data. The only information that leaves your computer are API calls to your configured transcription and LLM provider.

## Custom Cleanup

If you'd rather keep cleanup more literal and less context-aware, you can paste this simpler prompt into the custom system prompt setting:

<details>
  <summary>Simple post-processing prompt</summary>

  <pre><code>You are a dictation post-processor. You receive raw speech-to-text output and return clean text ready to be typed into an application.

Your job:
- Remove filler words (um, uh, you know, like) unless they carry meaning.
- Fix spelling, grammar, and punctuation errors.
- When the transcript already contains a word that is a close misspelling of a name or term from the context or custom vocabulary, correct the spelling. Never insert names or terms from context that the speaker did not say.
- Preserve the speaker's intent, tone, and meaning exactly.

Output rules:
- Return ONLY the cleaned transcript text, nothing else. So NEVER output words like "Here is the cleaned transcript text:"
- If the transcription is empty, return exactly: EMPTY
- Do not add words, names, or content that are not in the transcription. The context is only for correcting spelling of words already spoken.
- Do not change the meaning of what was said.

Example:
RAW_TRANSCRIPTION: "hey um so i just wanted to like follow up on the meating from yesterday i think we should definately move the dedline to next friday becuz the desine team still needs more time to finish the mock ups and um yeah let me know if that works for you ok thanks"

Then your response would be ONLY the cleaned up text, so here your response is ONLY:
"Hey, I just wanted to follow up on the meeting from yesterday. I think we should definitely move the deadline to next Friday because the design team still needs more time to finish the mockups. Let me know if that works for you. Thanks."</code></pre>
</details>

## Using a Local Model

FreeFlow can use OpenAI-compatible local or self-hosted providers instead of Groq. In settings, configure the API base URL and model IDs for your local LLM provider, such as Ollama, LM Studio, or another OpenAI-compatible server. If your transcription backend uses a different endpoint from your LLM backend, set the transcription API URL separately.

Local models are often slower than hosted providers, especially on cold start, long recordings, or busy hardware.

<details>
  <summary>Configure longer timeouts for local models</summary>

  FreeFlow keeps the default network timeout at 20 seconds, but you can extend it with macOS defaults:

```bash
defaults write com.zachlatta.freeflow transcription_timeout_seconds -float 120
defaults write com.zachlatta.freeflow post_processing_timeout_seconds -float 120
defaults write com.zachlatta.freeflow context_request_timeout_seconds -float 120
```

The timeout keys are:

- `transcription_timeout_seconds`: audio transcription requests
- `post_processing_timeout_seconds`: transcript cleanup and edit mode requests
- `context_request_timeout_seconds`: nearby app context requests

Only positive values are used. Remove a custom timeout to return to the 20-second default:

```bash
defaults delete com.zachlatta.freeflow transcription_timeout_seconds
defaults delete com.zachlatta.freeflow post_processing_timeout_seconds
defaults delete com.zachlatta.freeflow context_request_timeout_seconds
```

</details>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up the project, build, test, and submit changes.

## License

Licensed under the MIT license.
