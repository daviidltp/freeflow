import Foundation

/// Registro local de cuánto tarda cada paso del dictado, para medir cambios de rendimiento.
/// Una línea por dictado en Application Support/FreeFlow/timings.csv; no guarda texto ni audio.
enum DictationTimingLog {
    private static let header = "date,screen_analysis,app,transcription_ms,context_wait_ms,post_processing_ms,total_ms\n"

    static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
    }

    static func append(
        screenAnalysis: Bool,
        app: String?,
        transcription: Duration,
        contextWait: Duration,
        postProcessing: Duration,
        total: Duration
    ) {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let directory = support.appendingPathComponent("FreeFlow", isDirectory: true)
        let url = directory.appendingPathComponent("timings.csv")
        let appName = (app ?? "").replacingOccurrences(of: ",", with: " ")
        let line = [
            ISO8601DateFormatter().string(from: Date()),
            screenAnalysis ? "on" : "off",
            appName,
            String(milliseconds(transcription)),
            String(milliseconds(contextWait)),
            String(milliseconds(postProcessing)),
            String(milliseconds(total)),
        ].joined(separator: ",") + "\n"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
