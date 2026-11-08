import FluidAudio
import Foundation

// freeflow-parakeet: transcribe audio en local con Parakeet TDT 0.6B v3.
//
// Protocolo por líneas JSON:
// - Al arrancar escribe {"event":"loading"} y, con el modelo listo, {"event":"ready"}.
//   La primera vez descarga el modelo (~600 MB) y lo guarda en la caché de FluidAudio.
// - Cada línea de entrada es {"id": 1, "path": "/ruta/audio.wav"} y su respuesta es
//   {"id": 1, "text": "..."} o {"id": 1, "error": "..."}.
// - {"id": 2, "warm": true} transcribe un segundo de silencio para despertar el chip (el Mac lo
//   pone en reposo si Parakeet lleva un rato sin usarse) y responde {"id": 2, "text": ""}.
// - Si no puede cargar el modelo escribe {"event":"error","message":"..."} y sale con código 1.

struct Request: Decodable {
    let id: Int
    let path: String?
    let warm: Bool?
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
                    if request.warm == true {
                        _ = try await manager.transcribe([Float](repeating: 0, count: 16_000), decoderState: &state)
                        emit(["id": request.id, "text": ""])
                        continue
                    }
                    guard let path = request.path else {
                        emit(["id": request.id, "error": "falta la ruta del audio"])
                        continue
                    }
                    let result = try await manager.transcribe(URL(fileURLWithPath: path), decoderState: &state)
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
