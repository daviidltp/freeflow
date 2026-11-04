import Foundation
import os.log

private let transcriptTextLog = OSLog(
    subsystem: "com.zachlatta.freeflow",
    category: "Transcription"
)

enum TranscriptionResponseParsingError: Error, Equatable {
    case invalidResponse
}

enum TranscriptionResponseParser {
    // Whisper can emit these stock phrases for silence or background noise.
    // Only suppress them when segment metadata independently reports a high
    // probability of no speech, which protects genuine short dictations.
    private static let hallucinationPhrases: Set<String> = [
        "thank you",
        "thank you for watching",
        "thank you very much",
        "thank you so much",
        "thanks for watching",
        "please subscribe",
        "like and subscribe",
        "subtitles by",
        "subtitles by the amara.org community",
        "you"
    ]

    // Tuned conservatively against roughly 500 quiet, noisy, and real-speech
    // samples to minimize the chance of filtering genuine short dictations.
    private static let hallucinationNoSpeechThreshold = 0.1

    static func parse(_ data: Data) throws -> String {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw TranscriptionResponseParsingError.invalidResponse
        }

        if let json = object as? [String: Any],
           let text = json["text"] as? String {
            if isHallucination(text: text, json: json) {
                return ""
            }
            return text
        }

        let plainText = String(data: data, encoding: .utf8) ?? ""
        let text = plainText
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranscriptionResponseParsingError.invalidResponse
        }

        return text
    }

    private static func isHallucination(text: String, json: [String: Any]) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        guard hallucinationPhrases.contains(normalized) else {
            return false
        }

        guard let segments = json["segments"] as? [[String: Any]] else {
            os_log(
                .info,
                log: transcriptTextLog,
                "Skipping hallucination filter for '%{public}@': provider response has no segments/no_speech metadata",
                normalized
            )
            return false
        }

        guard let noSpeechProb = segments.first?["no_speech_prob"] as? Double else {
            os_log(
                .info,
                log: transcriptTextLog,
                "Skipping hallucination filter for '%{public}@': provider response omitted no_speech_prob",
                normalized
            )
            return false
        }
        return noSpeechProb >= hallucinationNoSpeechThreshold
    }
}

enum TranscriptOutputSanitizer {
    // Verbatim translation deliberately preserves the cleanup prompt's EMPTY
    // sentinel because "empty" can be legitimate translated speech here.
    static func verbatimTranslation(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 1 {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    static func postProcessedTranscript(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 1 {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if result == "EMPTY" {
            return ""
        }

        return result
    }

    static func commandModeTranscript(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func appearsToHaveExecutedInstruction(
        rawTranscript: String,
        cleanedTranscript: String,
        outputLanguage: String
    ) -> Bool {
        guard outputLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let rawTokens = significantTokens(in: rawTranscript)
        let cleanedTokens = significantTokens(in: cleanedTranscript)
        guard !rawTokens.isEmpty, !cleanedTokens.isEmpty else { return false }

        let instructionMarkers: Set<String> = [
            "ask", "answer", "compose", "create", "draft", "email", "generate", "make",
            "message", "prompt", "reply", "respond", "response", "summarize", "tell",
            "translate", "write", "claude", "chatgpt", "ai", "llm"
        ]
        let rawMarkers = rawTokens.intersection(instructionMarkers)
        guard !rawMarkers.isEmpty else { return false }

        let preservedMarkers = rawMarkers.intersection(cleanedTokens)
        let overlap = rawTokens.intersection(cleanedTokens)
        let overlapRatio = Double(overlap.count) / Double(max(rawTokens.count, 1))
        let assistantPreamblePattern = #"(?i)^\s*(sure|certainly|absolutely|here(?:'s| is)|i(?:'d| would) be happy to|i can)\b"#
        let cleanedHasAssistantPreamble = cleanedTranscript.range(
            of: assistantPreamblePattern,
            options: .regularExpression
        ) != nil
        let rawHasSamePreamble = rawTranscript.range(
            of: assistantPreamblePattern,
            options: .regularExpression
        ) != nil

        return (cleanedHasAssistantPreamble && !rawHasSamePreamble)
            || (preservedMarkers.isEmpty && overlapRatio < 0.35)
    }

    private static func significantTokens(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "could",
            "for", "from", "had", "has", "have", "he", "her", "him", "his", "i", "if",
            "in", "into", "is", "it", "its", "just", "me", "my", "of", "on", "or", "our",
            "please", "she", "so", "that", "the", "their", "them", "then", "there", "this",
            "to", "um", "uh", "was", "we", "were", "what", "when", "where", "who", "with",
            "would", "you", "your"
        ]

        let normalized = text.lowercased()
        let parts = normalized.split { character in
            !character.isLetter && !character.isNumber
        }

        return Set(parts.map(String.init).filter { token in
            token.count > 1 && !stopWords.contains(token)
        })
    }
}

/// Decide si una transcripción corta ya sale limpia de Whisper y puede pegarse sin
/// pasar por el LLM de limpieza (~0,5 s menos). Es conservadora: cualquier señal de
/// autocorrección, muletilla, puntuación dictada o sintaxis técnica la manda al LLM.
enum ShortTranscriptCleanupPolicy {
    static let maxWords = 4

    private static let llmTriggerWords: Set<String> = [
        // Autocorrecciones ("compra plátanos, no, aceite").
        "no", "perdón", "perdon", "digo", "mejor", "sea", "quiero", "decir",
        "sorry", "wait", "actually", "mean", "nu", "non", "nein",
        // Muletillas que el LLM debe quitar o convertir en EMPTY.
        "eh", "ehm", "em", "emm", "um", "uh", "uhm", "erm", "mm", "mmm", "hmm", "ah", "este",
        // Puntuación, formato o sintaxis dictados.
        "coma", "comma", "punto", "puntos", "period", "dot", "underscore", "guion", "guión",
        "dash", "barra", "slash", "arroba", "comillas", "paréntesis", "parentesis",
        "interrogación", "interrogacion", "exclamación", "exclamacion", "línea", "linea",
        "párrafo", "parrafo", "newline", "enter", "lista", "list", "bullet",
    ]

    /// `true` cuando se puede usar la transcripción tal cual.
    static func canSkipCleanup(_ transcript: String) -> Bool {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first(where: { $0.isLetter || $0.isNumber }) else { return false }
        // Whisper suele devolver la frase ya con mayúscula; si no, que la arregle el LLM.
        if first.isLetter && !first.isUppercase { return false }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard (1...maxWords).contains(words.count) else { return false }
        for word in words {
            let token = word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            if token.isEmpty || llmTriggerWords.contains(token) { return false }
        }
        return true
    }

    /// Texto final para una frase corta sin pasar por el LLM, o `nil` si hace falta el LLM.
    /// Solo aplica los estilos que se pueden reproducir sin ambigüedad: formal (tal cual)
    /// y casual sin instrucciones personalizadas (sin ¿ ¡ y sin punto final).
    static func cleanedWithoutLLM(
        _ transcript: String,
        style: WritingStyle,
        hasCustomStyleInstruction: Bool
    ) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSkipCleanup(trimmed) else { return nil }
        switch style {
        case .formal:
            return trimmed
        case .casual where !hasCustomStyleInstruction:
            var text = trimmed.replacingOccurrences(of: "¿", with: "").replacingOccurrences(of: "¡", with: "")
            if text.hasSuffix("."), !text.hasSuffix("..") { text.removeLast() }
            return text
        default:
            return nil
        }
    }
}
