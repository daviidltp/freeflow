import SwiftUI

/// Estadísticas de uso: totales, palabras por día y apps donde más dictas.
struct InsightsView: View {
    @EnvironmentObject var appState: AppState

    private static let typingWPM = 40.0

    var body: some View {
        InsightsContent(stats: appState.dictationStats, history: appState.pipelineHistory)
    }
}

private struct InsightsContent: View {
    @ObservedObject var stats: DictationStatsStore
    let history: [PipelineHistoryItem]

    private var topApps: [(name: String, count: Int)] {
        let counts = history.reduce(into: [String: Int]()) { result, item in
            guard let name = item.contextAppName, !name.isEmpty else { return }
            result[name, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map { (name: $0.key, count: $0.value) }
    }

    /// Minutos que habrías tardado tecleando a 40 WPM menos lo que has tardado hablando.
    private var minutesSaved: Int {
        let timed = stats.entries.filter { ($0.seconds ?? 0) >= 1 }
        let words = Double(timed.reduce(0) { $0 + $1.words })
        let spoken = timed.reduce(0.0) { $0 + ($1.seconds ?? 0) } / 60
        return max(0, Int((words / 40 - spoken).rounded()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader("Insights", subtitle: "How you use your voice.")

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    tile("Total words", stats.totalWords.formatted())
                    tile("Words per minute", stats.wordsPerMinute.map(String.init) ?? "–")
                    tile("Daily streak", "\(stats.currentStreak())")
                    tile("Dictations", stats.dictationCount.formatted())
                    tile("Time saved", "\(minutesSaved) min")
                    tile("Avg. words / dictation", stats.dictationCount == 0 ? "–" : "\(stats.totalWords / stats.dictationCount)")
                }

                SettingsCard("Last 14 days", icon: "chart.bar") {
                    WordsChart(days: stats.wordsByDay(days: 14))
                }

                SettingsCard("Top apps", icon: "app") {
                    if topApps.isEmpty {
                        Text("Dictate in a few apps and they'll show up here.")
                            .font(WisprFonts.figtree(14))
                            .foregroundStyle(WisprPalette.mutedForeground)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(topApps, id: \.name) { app in
                                HStack {
                                    Text(app.name)
                                        .foregroundStyle(WisprPalette.foreground)
                                    Spacer()
                                    Text("\(app.count)")
                                        .foregroundStyle(WisprPalette.mutedForeground)
                                }
                                .font(WisprFonts.figtree(14))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(WisprFonts.serif(30, weight: .medium))
                .foregroundStyle(WisprPalette.foreground)
            Text(title)
                .font(WisprFonts.figtree(13))
                .foregroundStyle(WisprPalette.mutedForeground)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WisprPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WisprPalette.border, lineWidth: 1))
    }
}

private struct WordsChart: View {
    let days: [(day: Date, words: Int)]

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    var body: some View {
        let maxWords = max(days.map(\.words).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days, id: \.day) { entry in
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(WisprPalette.backgroundTertiary)
                            .frame(height: 120)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(WisprPalette.foreground)
                            .frame(height: entry.words == 0 ? 0 : max(4, 120 * CGFloat(entry.words) / CGFloat(maxWords)))
                    }
                    .help("\(entry.words) words")
                    Text(Self.formatter.string(from: entry.day))
                        .font(WisprFonts.figtree(11))
                        .foregroundStyle(WisprPalette.mutedForeground)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
