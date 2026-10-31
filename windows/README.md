# FreeFlow para Windows

Misma idea que la app de Mac: mantienes un atajo, hablas, y el texto limpio se pega en el campo activo. Funciona en Windows 10 y 11 (64 bits).

## Instalar

1. Descarga `FreeFlow-Setup-<versión>.exe` desde la última release que empiece por `windows-v` en [Releases](https://github.com/daviidltp/freeflow/releases).
2. Ejecútalo. Windows avisará de que no está firmado: **Más información → Ejecutar de todas formas**.
3. Abre FreeFlow, pega tu API key de [Groq](https://console.groq.com/keys) y pulsa **Guardar y comprobar**.

## Usar

- **Mantener para hablar:** `Ctrl + Win`. Mantén, habla, suelta.
- **Alternar:** `Ctrl + Win + Shift`. Si empiezas manteniendo `Ctrl + Win` y añades `Shift`, la grabación se engancha y puedes soltar.
- `Esc` cancela una grabación.
- `Fn` no existe en Windows, por eso los atajos por defecto son distintos a los del Mac. Se cambian en **Atajos**.

Qué es igual que en el Mac: transcripción con Whisper, limpieza con el mismo prompt, vocabulario y reemplazos fijos, estilos por tipo de app, modo edición, historial local y proveedores compatibles con OpenAI.

Qué es distinto:

- Las apps se reconocen por el nombre del `.exe` (por ejemplo `whatsapp`, `slack`, `outlook`), no por identificador de bundle.
- No hay análisis de pantalla; el contexto es el nombre de la app y el título de la ventana.
- No hay actualizaciones automáticas todavía: se instala la nueva versión encima.

## Desarrollo

Requiere Node 20 o superior.

```bash
cd windows
npm install
npm test        # lógica compartida (prompts, estilos, atajos, API) sin tocar Windows
npm start       # abre la app (en Mac los atajos globales piden permiso de Accesibilidad)
npm run dist    # instalador .exe (hay que ejecutarlo en Windows)
```

El instalador lo construye `.github/workflows/windows.yml` en un runner de Windows: en cada PR que toque `windows/` sube el `.exe` como artefacto, y al empujar una etiqueta `windows-vX.Y.Z` crea la release.

## Estructura

- `src/core/`: lógica sin dependencias de Electron (se prueba con `npm test`). Es el equivalente de los ficheros Swift del mismo nombre.
- `src/main/`: proceso principal: atajos globales, grabación, pegado, bandeja.
- `src/renderer/`: ajustes, isla de grabación y grabadora oculta.
