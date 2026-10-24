import Foundation

enum DictationStatsTests {
    static func run() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        TestSupport.expectEqual(DictationStatsStore.wordCount(in: "  hola   qué\ntal "), 3)
        TestSupport.expectEqual(DictationStatsStore.wordCount(in: "   "), 0)

        let store = DictationStatsStore(fileURL: nil, calendar: calendar)
        TestSupport.expectEqual(store.totalWords, 0)
        TestSupport.expectEqual(store.currentStreak(now: now), 0)
        TestSupport.expect(store.wordsPerMinute == nil, "Sin dictados con duración no hay WPM")

        store.record(words: 0, seconds: 5, date: now)
        TestSupport.expectEqual(store.entries.count, 0)

        store.record(words: 60, seconds: 30, date: now)
        store.record(words: 30, seconds: 30, date: now.addingTimeInterval(-day))
        store.record(words: 10, seconds: nil, date: now.addingTimeInterval(-2 * day))
        TestSupport.expectEqual(store.totalWords, 100)
        TestSupport.expectEqual(store.currentStreak(now: now), 3)
        TestSupport.expectEqual(store.wordsPerMinute, 90)

        let week = store.wordsByDay(days: 7, now: now)
        TestSupport.expectEqual(week.count, 7)
        TestSupport.expectEqual(week.last?.words, 60)
        TestSupport.expectEqual(week[4].words, 10)
        TestSupport.expectEqual(week[0].words, 0)
        TestSupport.expectEqual(store.dictationCount, 3)
        TestSupport.expectEqual(store.longestStreak(), 3)
        store.record(words: 5, seconds: 3, date: now.addingTimeInterval(-10 * day))
        TestSupport.expectEqual(store.longestStreak(), 3)

        TestSupport.expectEqual(DictationFixes.correctedWords(raw: "um so hola eh mundo", processed: "So, hola mundo."), 2)
        TestSupport.expectEqual(
            DictationFixes.dictionaryFixes(in: "Cutmax y cutmax, Budky", vocabulary: "Cutmax", replacementRules: "budgy => Budky"),
            3
        )
        TestSupport.expectEqual(UsageCategory.category(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap"), .workMessages)
        TestSupport.expectEqual(UsageCategory.category(appName: "Claude", bundleIdentifier: nil), .aiPrompts)
        TestSupport.expectEqual(UsageCategory.category(appName: "Figma", bundleIdentifier: nil), .other)

        TestSupport.expectEqual(store.audioSeconds(since: now.addingTimeInterval(-day / 2)), 30)
        TestSupport.expectEqual(store.audioSeconds(since: now.addingTimeInterval(-2 * day)), 60)

        TestSupport.expectEqual(GroqRateLimitParser.seconds(fromDuration: "2m59.56s"), 179.56)
        TestSupport.expectEqual(GroqRateLimitParser.seconds(fromDuration: "7.66s"), 7.66)
        TestSupport.expectEqual(GroqRateLimitParser.seconds(fromDuration: "1h2m"), 3720)
        TestSupport.expect(GroqRateLimitParser.seconds(fromDuration: "abc") == nil, "Duración inválida")
        let headers = [
            "x-ratelimit-limit-requests": "2000",
            "x-ratelimit-remaining-requests": "1990",
            "x-ratelimit-reset-requests": "10m0s",
        ]
        let snapshot = GroqRateLimitParser.snapshot(header: { headers[$0] }, now: now)
        TestSupport.expectEqual(snapshot?.remaining(at: now), 1990)
        TestSupport.expectEqual(snapshot?.remaining(at: now.addingTimeInterval(700)), 2000)
        TestSupport.expect(GroqRateLimitParser.snapshot(header: { _ in nil }) == nil, "Sin cabeceras no hay lectura")

        // Si hoy aún no se ha dictado, la racha de ayer sigue viva; si falta un día entero, se rompe.
        TestSupport.expectEqual(store.currentStreak(now: now.addingTimeInterval(day)), 3)
        TestSupport.expectEqual(store.currentStreak(now: now.addingTimeInterval(2 * day)), 0)
    }
}
