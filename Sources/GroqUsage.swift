import Foundation

/// Límites del plan gratuito de Groq para Whisper (whisper-large-v3 y -turbo).
enum GroqFreePlanLimits {
    static let audioSecondsPerHour: Double = 7_200
    static let audioSecondsPerDay: Double = 28_800
}

/// Última lectura de los límites que Groq devuelve en cada respuesta.
struct GroqRateLimitSnapshot: Codable, Equatable {
    /// Peticiones permitidas al día (cabecera `x-ratelimit-limit-requests`).
    let limitRequests: Int
    /// Peticiones que quedaban al responder (`x-ratelimit-remaining-requests`).
    let remainingRequests: Int
    /// Segundos hasta el reinicio diario (`x-ratelimit-reset-requests`).
    let resetSeconds: Double?
    let capturedAt: Date

    /// Peticiones restantes ahora: si el día ya se reinició, vuelve al límite completo.
    func remaining(at now: Date = Date()) -> Int {
        guard let resetSeconds, now >= capturedAt.addingTimeInterval(resetSeconds) else { return remainingRequests }
        return limitRequests
    }

    func secondsUntilReset(at now: Date = Date()) -> Double? {
        guard let resetSeconds else { return nil }
        return max(0, capturedAt.addingTimeInterval(resetSeconds).timeIntervalSince(now))
    }
}

enum GroqRateLimitParser {
    /// Convierte duraciones como "2m59.56s", "7.66s" o "1h2m" en segundos.
    static func seconds(fromDuration text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let regex = try? NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)(ms|h|m|s)") else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        var total = 0.0
        var matched = 0
        regex.enumerateMatches(in: trimmed, range: range) { match, _, _ in
            guard let match,
                  let valueRange = Range(match.range(at: 1), in: trimmed),
                  let unitRange = Range(match.range(at: 2), in: trimmed),
                  let value = Double(trimmed[valueRange]) else { return }
            matched += 1
            switch trimmed[unitRange] {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "ms": total += value / 1000
            default: total += value
            }
        }
        return matched > 0 ? total : nil
    }

    static func snapshot(header: (String) -> String?, now: Date = Date()) -> GroqRateLimitSnapshot? {
        guard let limitText = header("x-ratelimit-limit-requests"), let limit = Int(limitText),
              let remainingText = header("x-ratelimit-remaining-requests"), let remaining = Int(remainingText) else {
            return nil
        }
        let reset = header("x-ratelimit-reset-requests").flatMap(seconds(fromDuration:))
        return GroqRateLimitSnapshot(limitRequests: limit, remainingRequests: remaining, resetSeconds: reset, capturedAt: now)
    }
}

/// Guarda la última lectura de límites de Groq para enseñarla en Insights. No guarda contenido ni claves.
final class GroqUsageStore: ObservableObject {
    static let shared = GroqUsageStore()
    private static let storageKey = "groq_rate_limit_snapshot"

    @Published private(set) var snapshot: GroqRateLimitSnapshot?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            snapshot = try? JSONDecoder().decode(GroqRateLimitSnapshot.self, from: data)
        }
    }

    /// Lee las cabeceras de una respuesta de Groq; ignora cualquier otro proveedor.
    func record(response: HTTPURLResponse, host: String?) {
        guard host?.lowercased() == "api.groq.com",
              let snapshot = GroqRateLimitParser.snapshot(header: { response.value(forHTTPHeaderField: $0) }) else { return }
        DispatchQueue.main.async {
            self.snapshot = snapshot
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
    }
}
