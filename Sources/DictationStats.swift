import Foundation

/// Un dictado terminado: solo cuenta palabras y duración, nunca el texto ni el audio.
struct DictationStatEntry: Codable, Equatable {
    let date: Date
    let words: Int
    /// Segundos grabados; nil en los dictados importados del historial antiguo.
    let seconds: Double?
    /// App donde se dictó, para el reparto de uso; nil en dictados antiguos.
    var appName: String? = nil
    var bundleIdentifier: String? = nil
    /// Palabras que la limpieza cambió respecto a la transcripción literal.
    var correctedWords: Int? = nil
    /// Veces que el diccionario (palabras o correcciones) aparece en el texto final.
    var dictionaryFixes: Int? = nil
}

/// Tipos de uso que se muestran en "Desktop usage".
enum UsageCategory: String, CaseIterable {
    case aiPrompts = "AI prompts"
    case emails = "Emails"
    case workMessages = "Work messages"
    case personalMessages = "Personal messages"
    case documents = "Documents"
    case other = "Other tasks"

    var icon: String {
        switch self {
        case .aiPrompts: return "cpu"
        case .emails: return "envelope"
        case .workMessages: return "text.bubble"
        case .personalMessages: return "message"
        case .documents: return "doc.text"
        case .other: return "infinity"
        }
    }

    /// Clasifica por el identificador o el nombre de la app; lo que no se reconoce va a "Other tasks".
    static func category(appName: String?, bundleIdentifier: String?) -> UsageCategory {
        let haystack = ((bundleIdentifier ?? "") + " " + (appName ?? "")).lowercased()
        func matches(_ keys: [String]) -> Bool { keys.contains { haystack.contains($0) } }
        if matches(["chatgpt", "openai", "claude", "anthropic", "cursor", "codex", "copilot", "gemini", "perplexity", "terminal", "iterm", "warp", "ghostty", "t3 code", "xcode", "vscode", "visual studio"]) { return .aiPrompts }
        if matches(["com.apple.mail", "outlook", "spark", "superhuman", "airmail", "mimestream", "gmail"]) { return .emails }
        if matches(["slack", "teams", "linear", "asana"]) { return .workMessages }
        if matches(["whatsapp", "telegram", "imessage", "com.apple.mobilesms", "messages", "discord", "signal", "instagram"]) { return .personalMessages }
        if matches(["pages", "word", "notion", "obsidian", "notes", "docs", "bear", "textedit", "pdf", "preview", "keynote", "numbers", "excel"]) { return .documents }
        return .other
    }
}

/// Cálculos puros sobre un dictado ya terminado.
enum DictationFixes {
    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// Palabras de la transcripción literal que ya no aparecen en el texto final (muletillas, errores, cambios).
    static func correctedWords(raw: String, processed: String) -> Int {
        var remaining: [String: Int] = [:]
        for word in normalizedWords(processed) { remaining[word, default: 0] += 1 }
        var corrected = 0
        for word in normalizedWords(raw) {
            if let count = remaining[word], count > 0 {
                remaining[word] = count - 1
            } else {
                corrected += 1
            }
        }
        return corrected
    }

    /// Cuántas veces aparecen en el texto final las palabras del diccionario y los destinos de las correcciones.
    static func dictionaryFixes(in text: String, vocabulary: String, replacementRules: String) -> Int {
        var terms = vocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for line in replacementRules.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "=>")
            if parts.count == 2 { terms.append(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        let lowered = text.lowercased()
        var total = 0
        for term in Set(terms.filter { !$0.isEmpty }) {
            let needle = term.lowercased()
            var searchRange = lowered.startIndex..<lowered.endIndex
            while let found = lowered.range(of: needle, range: searchRange) {
                total += 1
                searchRange = found.upperBound..<lowered.endIndex
            }
        }
        return total
    }
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

    func record(
        words: Int,
        seconds: Double?,
        date: Date = Date(),
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        correctedWords: Int? = nil,
        dictionaryFixes: Int? = nil
    ) {
        guard words > 0 else { return }
        entries.append(DictationStatEntry(
            date: date,
            words: words,
            seconds: seconds,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            correctedWords: correctedWords,
            dictionaryFixes: dictionaryFixes
        ))
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

    /// Segundos de audio grabados desde `date` (solo dictados con duración conocida).
    func audioSeconds(since date: Date) -> Double {
        entries.reduce(0) { total, entry in
            entry.date >= date ? total + (entry.seconds ?? 0) : total
        }
    }

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

    /// La racha más larga de días seguidos con dictados.
    func longestStreak() -> Int {
        let days = Set(entries.map { calendar.startOfDay(for: $0.date) }).sorted()
        var best = 0
        var current = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        return best
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
