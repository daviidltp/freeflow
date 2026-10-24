import SwiftUI

/// Estadísticas de uso con el diseño de Wispr: velocidad, correcciones, palabras, uso por tipo de app y racha.
struct InsightsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        InsightsContent(stats: appState.dictationStats, history: appState.pipelineHistory)
    }
}

private struct InsightsContent: View {
    private enum InsightsTab: String, CaseIterable, Identifiable {
        case usage = "Your usage"
        case voice = "Your voice"
        var id: String { rawValue }
    }

    @ObservedObject var stats: DictationStatsStore
    let history: [PipelineHistoryItem]
    @State private var tab: InsightsTab = .usage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader("Insights")
                tabBar
                switch tab {
                case .usage: usage
                case .voice: voice
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 28) {
                ForEach(InsightsTab.allCases) { option in
                    Button {
                        tab = option
                    } label: {
                        VStack(spacing: 10) {
                            Text(option.rawValue)
                                .font(WisprFonts.figtree(15, weight: tab == option ? .semibold : .medium))
                                .foregroundStyle(tab == option ? WisprPalette.foreground : WisprPalette.mutedForeground)
                            Rectangle()
                                .fill(tab == option ? WisprPalette.foreground : Color.clear)
                                .frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Rectangle().fill(WisprPalette.border).frame(height: 1)
        }
    }

    // MARK: Your usage

    private var totalFixes: Int {
        stats.entries.reduce(0) { $0 + ($1.correctedWords ?? 0) + ($1.dictionaryFixes ?? 0) }
    }
    private var correctedWords: Int { stats.entries.reduce(0) { $0 + ($1.correctedWords ?? 0) } }
    private var dictionaryFixes: Int { stats.entries.reduce(0) { $0 + ($1.dictionaryFixes ?? 0) } }

    private var usage: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                speedCard
                statCard(value: totalFixes.formatted(), label: "FIXES MADE BY \(AppName.displayName.uppercased())") {
                    detailRow("\(correctedWords.formatted()) words corrected")
                    detailRow("\(dictionaryFixes.formatted()) dictionary fixes")
                }
                statCard(value: stats.totalWords.formatted(), label: "TOTAL WORDS DICTATED") {
                    HStack(spacing: 8) {
                        Image(systemName: "desktopcomputer")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Desktop")
                            Text("\(stats.totalWords.formatted()) words")
                        }
                    }
                    .font(WisprFonts.figtree(15))
                    .foregroundStyle(WisprPalette.foreground)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) {
                DesktopUsageCard(entries: stats.entries)
                    .frame(maxWidth: .infinity)
                StreakCard(stats: stats)
                    .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var speedCard: some View {
        let wpm = stats.wordsPerMinute
        let progress = min(Double(wpm ?? 0) / 200, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text(wpm.map(String.init) ?? "–")
                .font(WisprFonts.figtree(28, weight: .medium))
                .foregroundStyle(WisprPalette.foreground)
            Text("WORDS PER MINUTE")
                .font(WisprFonts.figtree(12, weight: .medium))
                .tracking(1)
                .foregroundStyle(WisprPalette.mutedForeground)
            SpeedGauge(progress: progress, wpm: wpm)
                .frame(maxWidth: .infinity)
                .frame(height: 104)
        }
        .padding(22)
        .insightsCardBackground()
    }

    private func statCard<Detail: View>(value: String, label: String, @ViewBuilder detail: () -> Detail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(value)
                .font(WisprFonts.figtree(28, weight: .medium))
                .foregroundStyle(WisprPalette.foreground)
            Text(label)
                .font(WisprFonts.figtree(12, weight: .medium))
                .tracking(1)
                .foregroundStyle(WisprPalette.mutedForeground)
                .lineLimit(1)
            Rectangle().fill(WisprPalette.border).frame(height: 1).padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 10) {
                detail()
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .insightsCardBackground()
    }

    private func detailRow(_ text: String) -> some View {
        Text(text)
            .font(WisprFonts.figtree(15))
            .foregroundStyle(WisprPalette.foreground)
    }

    // MARK: Your voice

    private var voice: some View {
        let average = stats.dictationCount == 0 ? 0 : stats.totalWords / stats.dictationCount
        let longest = stats.entries.map(\.words).max() ?? 0
        return VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                simpleCard(value: average == 0 ? "–" : "\(average)", label: "AVG. WORDS PER DICTATION")
                simpleCard(value: longest == 0 ? "–" : "\(longest)", label: "LONGEST DICTATION (WORDS)")
                simpleCard(value: stats.dictationCount.formatted(), label: "DICTATIONS")
            }
            .fixedSize(horizontal: false, vertical: true)
            TopWordsCard(history: history)
        }
    }

    private func simpleCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(value)
                .font(WisprFonts.figtree(28, weight: .medium))
                .foregroundStyle(WisprPalette.foreground)
            Text(label)
                .font(WisprFonts.figtree(12, weight: .medium))
                .tracking(1)
                .foregroundStyle(WisprPalette.mutedForeground)
                .lineLimit(1)
        }
        .padding(22)
        .insightsCardBackground()
    }
}

private extension View {
    func insightsCardBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WisprPalette.backgroundSecondary))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WisprPalette.border, lineWidth: 1))
    }
}

// MARK: - Gauge

/// Semicírculo de velocidad: el tramo oscuro crece con las palabras por minuto (tope 200).
private struct SpeedGauge: View {
    let progress: Double
    let wpm: Int?

    private var typingMultiple: String? {
        guard let wpm, wpm > 0 else { return nil }
        return String(format: "%.1f×", Double(wpm) / 40)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GaugeArc(progress: 1)
                .stroke(WisprPalette.sand700.opacity(0.55), style: StrokeStyle(lineWidth: 16, lineCap: .round))
            if progress > 0 {
                GaugeArc(progress: progress)
                    .stroke(WisprPalette.teal900, style: StrokeStyle(lineWidth: 16, lineCap: .round))
            }
            VStack(spacing: 0) {
                Text("vs. typing")
                    .font(WisprFonts.figtree(13))
                    .foregroundStyle(WisprPalette.mutedForeground)
                Text(typingMultiple ?? "–")
                    .font(WisprFonts.figtree(20, weight: .semibold))
                    .foregroundStyle(WisprPalette.foreground)
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 6)
    }
}

private struct GaugeArc: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height) - 10
        let center = CGPoint(x: rect.midX, y: rect.maxY - 10)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(180 + 180 * progress),
            clockwise: false
        )
        return path
    }
}

// MARK: - Desktop usage

private struct DesktopUsageCard: View {
    let entries: [DictationStatEntry]

    private var wordsByCategory: [(category: UsageCategory, words: Int, dictations: Int)] {
        var words: [UsageCategory: Int] = [:]
        var counts: [UsageCategory: Int] = [:]
        for entry in entries {
            let category = UsageCategory.category(appName: entry.appName, bundleIdentifier: entry.bundleIdentifier)
            words[category, default: 0] += entry.words
            counts[category, default: 0] += 1
        }
        let order: [UsageCategory] = [.other, .aiPrompts, .emails, .workMessages, .personalMessages, .documents]
        return order.map { (category: $0, words: words[$0] ?? 0, dictations: counts[$0] ?? 0) }
    }

    private var totalApps: Int {
        Set(entries.compactMap { $0.appName }).count
    }

    var body: some View {
        let rows = wordsByCategory
        let total = max(rows.reduce(0) { $0 + $1.words }, 1)
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .firstTextBaseline) {
                Text("Desktop usage")
                    .font(WisprFonts.figtree(28, weight: .medium))
                    .foregroundStyle(WisprPalette.foreground)
                Spacer()
                Text("TOTAL APPS USED | \(totalApps)")
                    .font(WisprFonts.figtree(11, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(WisprPalette.mutedForeground)
            }
            VStack(spacing: 18) {
                ForEach(rows, id: \.category) { row in
                    usageRow(row.category, words: row.words, dictations: row.dictations, total: total, isTop: row.words > 0 && row.words == rows.map(\.words).max())
                }
            }
        }
        .padding(22)
        .insightsCardBackground()
    }

    private func usageRow(_ category: UsageCategory, words: Int, dictations: Int, total: Int, isTop: Bool) -> some View {
        let share = Double(words) / Double(total)
        return HStack(spacing: 14) {
            Image(systemName: category.icon)
                .font(.system(size: 16))
                .frame(width: 24)
                .foregroundStyle(WisprPalette.foreground)
            GeometryReader { geometry in
                // La barra más larga ocupa hasta ~62 % del ancho; el resto se queda en chip pequeño.
                let longest = geometry.size.width * 0.62
                let width = max(54, longest * share)
                HStack(spacing: 14) {
                    Text("\(Int((share * 100).rounded()))%")
                        .font(WisprFonts.figtree(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: width, height: 28)
                        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(isTop ? WisprPalette.teal900 : WisprPalette.teal500))
                    Text("\(dictations) \(category.rawValue.uppercased())")
                        .font(WisprFonts.figtree(12, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(WisprPalette.foreground)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 28)
        }
    }
}

// MARK: - Streak heatmap

private struct StreakCard: View {
    @ObservedObject var stats: DictationStatsStore

    private static let weeks = 17
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private struct Cell: Identifiable {
        let id = UUID()
        let words: Int?   // nil = día futuro
        let date: Date
    }

    private var columns: [[Cell]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) - 1 // 0 = domingo
        let totalDays = (Self.weeks - 1) * 7 + weekday + 1
        let data = stats.wordsByDay(days: totalDays)
        var columns: [[Cell]] = []
        var index = 0
        for week in 0..<Self.weeks {
            var column: [Cell] = []
            for day in 0..<7 {
                let isFuture = week == Self.weeks - 1 && day > weekday
                if isFuture, let date = calendar.date(byAdding: .day, value: day - weekday, to: today) {
                    column.append(Cell(words: nil, date: date))
                } else if index < data.count {
                    column.append(Cell(words: data[index].words, date: data[index].day))
                    index += 1
                }
            }
            columns.append(column)
        }
        return columns
    }

    private func color(for words: Int?, maxWords: Int) -> Color {
        guard let words else { return Color.clear }
        guard words > 0 else { return WisprPalette.backgroundTertiary.opacity(0.7) }
        let ratio = Double(words) / Double(max(maxWords, 1))
        switch ratio {
        case ..<0.25: return WisprPalette.teal200
        case ..<0.5: return WisprPalette.teal500
        case ..<0.75: return WisprPalette.teal700
        default: return WisprPalette.teal900
        }
    }

    var body: some View {
        let columns = self.columns
        let maxWords = columns.flatMap { $0 }.compactMap(\.words).max() ?? 0
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(stats.currentStreak()) day streak")
                    .font(WisprFonts.figtree(28, weight: .medium))
                    .foregroundStyle(WisprPalette.foreground)
                Spacer()
                Text("LONGEST STREAK | \(stats.longestStreak()) \(stats.longestStreak() == 1 ? "DAY" : "DAYS")")
                    .font(WisprFonts.figtree(11, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(WisprPalette.mutedForeground)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Color.clear.frame(width: 34, height: 20)
                    ForEach(Self.weekdays, id: \.self) { day in
                        Text(day)
                            .font(WisprFonts.figtree(12))
                            .foregroundStyle(WisprPalette.mutedForeground)
                            .fixedSize()
                            .frame(width: 34, height: 16, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                            Text(monthLabel(column: column, index: index, columns: columns))
                                .font(WisprFonts.figtree(12))
                                .foregroundStyle(WisprPalette.mutedForeground)
                                .fixedSize()
                                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                        }
                    }
                    HStack(spacing: 5) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                            VStack(spacing: 5) {
                                ForEach(column) { cell in
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(color(for: cell.words, maxWords: maxWords))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 16)
                                        .help(cell.words.map { "\($0) words" } ?? "")
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Text("More")
                    .font(WisprFonts.figtree(13))
                    .foregroundStyle(WisprPalette.mutedForeground)
                ForEach([WisprPalette.teal900, WisprPalette.teal700, WisprPalette.teal500, WisprPalette.teal200], id: \.self) { shade in
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(shade).frame(width: 18, height: 18)
                }
                Text("Less")
                    .font(WisprFonts.figtree(13))
                    .foregroundStyle(WisprPalette.mutedForeground)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .insightsCardBackground()
    }

    /// El mes se escribe sobre la primera semana en la que cambia.
    private func monthLabel(column: [Cell], index: Int, columns: [[Cell]]) -> String {
        guard let first = column.first else { return "" }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: first.date)
        if index == 0 { return Self.monthFormatter.string(from: first.date) }
        guard let previous = columns[index - 1].first else { return "" }
        return calendar.component(.month, from: previous.date) == month ? "" : Self.monthFormatter.string(from: first.date)
    }
}

// MARK: - Your voice: palabras más usadas

private struct TopWordsCard: View {
    let history: [PipelineHistoryItem]

    private var topWords: [(word: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in history {
            let text = item.postProcessedTranscript.isEmpty ? item.rawTranscript : item.postProcessedTranscript
            for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) where word.count >= 5 {
                counts[String(word), default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(8)
            .map { (word: $0.key, count: $0.value) }
    }

    var body: some View {
        let words = topWords
        let maxCount = max(words.first?.count ?? 1, 1)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Most used words")
                    .font(WisprFonts.figtree(28, weight: .medium))
                    .foregroundStyle(WisprPalette.foreground)
                Spacer()
                Text("FROM YOUR RECENT DICTATIONS")
                    .font(WisprFonts.figtree(11, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(WisprPalette.mutedForeground)
            }
            if words.isEmpty {
                Text("Dictate a few times and your most used words will show up here.")
                    .font(WisprFonts.figtree(14))
                    .foregroundStyle(WisprPalette.mutedForeground)
            } else {
                VStack(spacing: 12) {
                    ForEach(words, id: \.word) { entry in
                        HStack(spacing: 12) {
                            Text(entry.word)
                                .font(WisprFonts.figtree(14))
                                .foregroundStyle(WisprPalette.foreground)
                                .frame(width: 130, alignment: .leading)
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(WisprPalette.teal700)
                                    .frame(width: max(8, geometry.size.width * CGFloat(entry.count) / CGFloat(maxCount)))
                            }
                            .frame(height: 20)
                            Text("\(entry.count)")
                                .font(WisprFonts.figtree(12, weight: .medium))
                                .foregroundStyle(WisprPalette.mutedForeground)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(22)
        .insightsCardBackground()
    }
}
