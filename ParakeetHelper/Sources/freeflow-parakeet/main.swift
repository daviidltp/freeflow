import FluidAudio
import Foundation

// freeflow-parakeet: transcribe audio en local con Parakeet TDT 0.6B v3.
//
// Protocolo por líneas JSON:
// - Al arrancar escribe {"event":"loading"} y, con el modelo listo, {"event":"ready"}.
//   La primera vez descarga el modelo (~600 MB) y lo guarda en la caché de FluidAudio.
// - Cada línea de entrada es {"id": 1, "path": "/ruta/audio.wav"} y su respuesta es
//   {"id": 1, "text": "..."} o {"id": 1, "error": "..."}.
// - Si no puede cargar el modelo escribe {"event":"error","message":"..."} y sale con código 1.

struct Request: Decodable {
    let id: Int
    let path: String
}

let output = FileHandle.standardOutput

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          var line = String(data: data, encoding: .utf8) else { return }
    line += "\n"
    output.write(Data(line.utf8))
}

@main
struct FreeFlowParakeet {
    static func main() async {
        emit(["event": "loading"])
        let manager: AsrManager
        do {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            manager = AsrManager(config: .default)
            try await manager.loadModels(models)
        } catch {
            emit(["event": "error", "message": "\(error)"])
            exit(1)
        }
        emit(["event": "ready"])

        let decoder = JSONDecoder()
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard let data = line.data(using: .utf8),
                      let request = try? decoder.decode(Request.self, from: data) else {
                    continue
                }
                do {
                    var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
                    let result = try await manager.transcribe(
                        URL(fileURLWithPath: request.path),
                        decoderState: &state
                    )
                    emit(["id": request.id, "text": result.text])
                } catch {
                    emit(["id": request.id, "error": "\(error)"])
                }
            }
        } catch {
            // La entrada se ha cerrado: la app ha terminado.
        }
        exit(0)
    }
}
