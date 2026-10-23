import Foundation

/// Fixed, case-insensitive fixes applied to the final text, one rule per line
/// as `wrong => right`. They run after cleanup so they do not depend on the
/// model recognizing a misheard term.
enum VocabularyReplacements {
    static let storageKey = "vocabulary_replacements"

    static func apply(_ text: String, rules: String) -> String {
        var result = text
        for line in rules.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let wrong = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wrong.isEmpty, !right.isEmpty else { continue }
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: wrong) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: right)
            )
        }
        return result
    }

    static func applyStored(_ text: String) -> String {
        let fixed = apply(text, rules: UserDefaults.standard.string(forKey: storageKey) ?? "")
        return restoreCasing(fixed, vocabulary: UserDefaults.standard.string(forKey: "custom_vocabulary") ?? "")
    }

    /// Whisper sometimes shouts a glossary term ("CUTMAX"). Any vocabulary term
    /// that shows up fully upper-cased is put back to the spelling in the
    /// vocabulary. Terms that are themselves all caps (API) are left alone.
    static func restoreCasing(_ text: String, vocabulary: String) -> String {
        var result = text
        let terms = vocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for term in terms where term.count > 1 && term != term.uppercased() {
            let shouted = term.uppercased()
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: shouted) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: term)
            )
        }
        return result
    }

    /// Short glossary sent to the transcription model as its `prompt`, so it
    /// spells the terms right from the start. Kept well under Whisper's limit.
    static func transcriptionPrompt(fromVocabulary vocabulary: String) -> String? {
        let terms = vocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        return String(("Glosario: " + terms.joined(separator: ", ") + ".").prefix(600))
    }
}
