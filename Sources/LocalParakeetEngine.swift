import Foundation

/// Dónde se transcribe el audio: en la nube con el proveedor configurado (Groq por defecto)
/// o en el propio Mac con Parakeet.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case cloud
    case parakeet

    static let storageKey = "transcription_engine"
    static let parakeetModelName = "parakeet-tdt-0.6b-v3"

    var id: String { rawValue }

    static var current: TranscriptionEngine {
        get { TranscriptionEngine(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .cloud }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    var label: String {
        switch self {
        case .cloud: return "En la nube"
        case .parakeet: return "En tu Mac (Parakeet)"
        }
    }

    var detail: String {
        switch self {
        case .cloud:
            return "Envía el audio al proveedor configurado (Groq con Whisper large-v3). Respeta tu vocabulario."
        case .parakeet:
            return "Parakeet TDT 0.6B v3 transcribe sin conexión y sin enviar tu audio. La primera vez descarga unos 600 MB."
        }
    }
}

enum LocalParakeetError: LocalizedError {
    case helperMissing
    case notRunning
    case loadFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing: return "No se encuentra el transcriptor local de Parakeet en la app."
        case .notRunning: return "El transcriptor local de Parakeet se ha cerrado."
        case let .loadFailed(message): return "No se pudo cargar Parakeet: \(message)"
        case let .transcriptionFailed(message): return "Parakeet no pudo transcribir: \(message)"
        }
    }
}

/// Lanza el ayudante `freeflow-parakeet` (Contents/Helpers) una sola vez, lo mantiene vivo
/// con el modelo cargado y le pasa rutas de audio por la entrada estándar.
/// Todo su estado se toca solo desde `queue` (y `status`, solo en el hilo principal).
final class LocalParakeetEngine: ObservableObject, @unchecked Sendable {
    static let shared = LocalParakeetEngine()

    enum Status: Equatable {
        case stopped
        case loading
        case ready
        case failed(String)
    }

    /// Estado para la interfaz; se publica en el hilo principal.
    @Published private(set) var status: Status = .stopped

    private let queue = DispatchQueue(label: "app.freeflow.parakeet")
    private var state: Status = .stopped
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<String, Error>] = [:]
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []

    private var helperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/freeflow-parakeet")
    }

    /// Arranca el ayudante y carga el modelo en segundo plano, para que el primer dictado no espere.
    func warmUp() {
        queue.async { self.startIfNeeded() }
    }

    /// Cierra el ayudante y libera la memoria del modelo.
    func stop() {
        queue.async {
            self.process?.terminate()
        }
    }

    func transcribe(fileURL: URL) async throws -> String {
        try await waitUntilReady()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.state == .ready, let input = self.input else {
                    continuation.resume(throwing: LocalParakeetError.notRunning)
                    return
                }
                let id = self.nextID
                self.nextID += 1
                self.pending[id] = continuation
                let request: [String: Any] = ["id": id, "path": fileURL.path]
                guard var data = try? JSONSerialization.data(withJSONObject: request) else {
                    self.pending[id] = nil
                    continuation.resume(throwing: LocalParakeetError.transcriptionFailed("petición no válida"))
                    return
                }
                data.append(0x0A)
                input.write(data)
            }
        }
    }

    // MARK: - Proceso

    private func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.startIfNeeded()
                switch self.state {
                case .ready:
                    continuation.resume()
                case let .failed(message):
                    continuation.resume(throwing: LocalParakeetError.loadFailed(message))
                case .loading, .stopped:
                    self.readyWaiters.append(continuation)
                }
            }
        }
    }

    /// Solo en `queue`.
    private func startIfNeeded() {
        guard process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            setState(.failed(LocalParakeetError.helperMissing.localizedDescription))
            failReadyWaiters(LocalParakeetError.helperMissing)
            return
        }

        let process = Process()
        process.executableURL = helperURL
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.queue.async { self.consume(data) }
        }
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            self.queue.async { self.handleTermination(of: finished) }
        }

        do {
            try process.run()
        } catch {
            setState(.failed(error.localizedDescription))
            failReadyWaiters(LocalParakeetError.loadFailed(error.localizedDescription))
            return
        }
        self.process = process
        input = stdinPipe.fileHandleForWriting
        buffer = Data()
        setState(.loading)
    }

    private func handleTermination(of finished: Process) {
        guard finished === process else { return }
        (finished.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        input = nil
        let error: Error
        if case let .failed(message) = state {
            error = LocalParakeetError.loadFailed(message)
        } else {
            error = LocalParakeetError.notRunning
            setState(.stopped)
        }
        failReadyWaiters(error)
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values {
            continuation.resume(throwing: error)
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            handle(object)
        }
    }

    private func handle(_ object: [String: Any]) {
        if let event = object["event"] as? String {
            switch event {
            case "loading":
                setState(.loading)
            case "ready":
                setState(.ready)
                let waiters = readyWaiters
                readyWaiters.removeAll()
                waiters.forEach { $0.resume() }
            case "error":
                let message = object["message"] as? String ?? "error desconocido"
                setState(.failed(message))
                failReadyWaiters(LocalParakeetError.loadFailed(message))
            default:
                break
            }
            return
        }
        guard let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) else { return }
        if let text = object["text"] as? String {
            continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            let message = object["error"] as? String ?? "error desconocido"
            continuation.resume(throwing: LocalParakeetError.transcriptionFailed(message))
        }
    }

    private func failReadyWaiters(_ error: Error) {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
    }

    private func setState(_ newState: Status) {
        state = newState
        DispatchQueue.main.async { self.status = newState }
    }
}
