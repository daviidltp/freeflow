import Foundation

/// Registro local de cuánto tarda cada paso del dictado, para medir cambios de rendimiento.
/// Una línea por dictado en Application Support/FreeFlow/timings.csv; no guarda texto ni audio.
enum DictationTimingLog {
    /// Si cambian las columnas, el archivo anterior se guarda como timings-<fecha>.csv y se empieza uno nuevo.
    static let header = "date,screen_analysis,app,audio_s,words,transcription_model,cleanup_model,transcription_ms,context_wait_ms,post_processing_ms,total_ms\n"

    static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
    }

    static func append(
        screenAnalysis: Bool,
        app: String?,
        audioSeconds: Double,
        words: Int,
        transcriptionModel: String,
        cleanupModel: String,
        transcription: Duration,
        contextWait: Duration,
        postProcessing: Duration,
        total: Duration
    ) {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let directory = support.appendingPathComponent("FreeFlow", isDirectory: true)
        let url = directory.appendingPathComponent("timings.csv")
        let clean: (String?) -> String = { ($0 ?? "").replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "\n", with: " ") }
        let appName = clean(app)
        let line = [
            ISO8601DateFormatter().string(from: Date()),
            screenAnalysis ? "on" : "off",
            appName,
            String(format: "%.1f", audioSeconds),
            String(words),
            clean(transcriptionModel),
            clean(cleanupModel.isEmpty ? "none" : cleanupModel),
            String(milliseconds(transcription)),
            String(milliseconds(contextWait)),
            String(milliseconds(postProcessing)),
            String(milliseconds(total)),
        ].joined(separator: ",") + "\n"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        rotateIfHeaderChanged(url)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private static func rotateIfHeaderChanged(_ url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        let firstBytes = (try? handle.read(upToCount: header.utf8.count)) ?? Data()
        try? handle.close()
        guard String(decoding: firstBytes, as: UTF8.self) != header else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let archived = url.deletingLastPathComponent().appendingPathComponent("timings-\(stamp).csv")
        try? FileManager.default.moveItem(at: url, to: archived)
    }

    /// Modelo que de verdad respondió, leído de la primera línea del prompt de depuración ("Model: …").
    static func model(fromDebugPrompt prompt: String) -> String {
        guard let firstLine = prompt.split(separator: "\n", maxSplits: 1).first,
              firstLine.hasPrefix("Model: ") else { return "" }
        return String(firstLine.dropFirst("Model: ".count)).trimmingCharacters(in: .whitespaces)
    }
}
