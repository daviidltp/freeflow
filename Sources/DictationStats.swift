import Foundation

/// Un dictado terminado: solo cuenta palabras y duración, nunca el texto ni el audio.
struct DictationStatEntry: Codable, Equatable {
    let date: Date
    let words: Int
    /// Segundos grabados; nil en los dictados importados del historial antiguo.
    let seconds: Double?
}

/// Estadísticas de la pantalla Home (racha, palabras, palabras por minuto).
/// Se guardan en un JSON local aparte del historial, sin contenido de los dictados.
final class DictationStatsStore: ObservableObject {
    @Published private(set) var entries: [DictationStatEntry] = []

    private let fileURL: URL?
    private let calendar: Calendar

    init(fileURL: URL? = DictationStatsStore.defaultFileURL(), calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        load()
    }

    static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func defaultFileURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = appSupport.appendingPathComponent(AppName.displayName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("dictation-stats.json")
    }

    // MARK: Escritura

    func record(words: Int, seconds: Double?, date: Date = Date()) {
        guard words > 0 else { return }
        entries.append(DictationStatEntry(date: date, words: words, seconds: seconds))
        save()
    }

    /// Primera ejecución: importa las palabras del historial que ya existía para que Home no empiece en cero.
    func seedIfEmpty(from history: [PipelineHistoryItem]) {
        guard entries.isEmpty, !history.isEmpty else { return }
        entries = history
            .map { item in
                let text = item.postProcessedTranscript.isEmpty ? item.rawTranscript : item.postProcessedTranscript
                return DictationStatEntry(date: item.timestamp, words: Self.wordCount(in: text), seconds: nil)
            }
            .filter { $0.words > 0 }
            .sorted { $0.date < $1.date }
        save()
    }

    // MARK: Lectura

    var totalWords: Int {
        entries.reduce(0) { $0 + $1.words }
    }

    /// Palabras por minuto sobre los dictados con duración conocida; nil si todavía no hay ninguno.
    var wordsPerMinute: Int? {
        let timed = entries.compactMap { entry -> (Int, Double)? in
            guard let seconds = entry.seconds, seconds >= 1 else { return nil }
            return (entry.words, seconds)
        }
        let seconds = timed.reduce(0) { $0 + $1.1 }
        guard seconds > 0 else { return nil }
        let words = timed.reduce(0) { $0 + $1.0 }
        return Int((Double(words) / (seconds / 60)).rounded())
    }

    var dictationCount: Int { entries.count }

    /// Palabras de cada uno de los últimos `days` días (el último elemento es hoy).
    func wordsByDay(days: Int, now: Date = Date()) -> [(day: Date, words: Int)] {
        let today = calendar.startOfDay(for: now)
        var totals: [Date: Int] = [:]
        for entry in entries {
            totals[calendar.startOfDay(for: entry.date), default: 0] += entry.words
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, totals[day] ?? 0)
        }
    }

    /// Días seguidos con al menos un dictado. Si hoy aún no has dictado, la racha de ayer sigue viva.
    func currentStreak(now: Date = Date()) -> Int {
        let days = Set(entries.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else {
                return 0
            }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    // MARK: Disco

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([DictationStatEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
