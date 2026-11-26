# Arquitectura

FreeFlow es un dictado para la barra de menús de macOS. Usa `swiftc` directamente y Make. Cambiar a Swift Package Manager o Xcode requiere permiso expreso.

| Ruta | Responsabilidad |
| --- | --- |
| `Sources/App.swift`, `Sources/AppDelegate.swift` | Ciclo de vida |
| `Sources/AppState.swift` | Estado y coordinación del flujo |
| `Sources/AudioRecorder.swift` | Captura y conversión del audio |
| `Sources/TranscriptionService.swift`, `Sources/RealtimeTranscriptionService.swift` | Proveedores de transcripción |
| `Sources/PostProcessingService.swift` | Limpieza y modo de edición |
| `Sources/AppContextService.swift` | Contexto y capturas de la app activa |
| `Sources/ShortcutCore/` | Modelo de atajos, coincidencias y sesión |
| `Sources/PipelineHistoryStore.swift` | Historial local |
| `Sources/UpdateManager.swift` | Actualizador |
| `Sources/SettingsView.swift`, `Sources/SetupView.swift` | Interfaz SwiftUI |
| `Tests/` | Pruebas ejecutables sin dependencias |
