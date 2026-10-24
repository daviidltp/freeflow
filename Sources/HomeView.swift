import SwiftUI
import AppKit

// MARK: - Home

/// Pantalla de inicio: saludo, estadísticas (racha, palabras, palabras por minuto) y dictados recientes por día.
struct HomeView: View {
    @EnvironmentObject var appState: AppState

    private var firstName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    }

    private var greeting: String {
        firstName.isEmpty ? "Welcome back" : "Welcome back, \(firstName)"
    }

    private var groupedHistory: [(day: Date, items: [PipelineHistoryItem])] {
        let calendar = Calendar.current
        let sorted = appState.pipelineHistory
            .filter { !displayText(for: $0).isEmpty }
            .sorted { $0.timestamp > $1.timestamp }
        let grouped = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { (day: $0, items: grouped[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    Text(greeting)
                        .font(WisprFonts.serif(34, weight: .medium))
                        .foregroundStyle(WisprPalette.foreground)
                    Spacer(minLength: 12)
                    HomeStatsRow(stats: appState.dictationStats)
                }

                if groupedHistory.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedHistory, id: \.day) { group in
                        HomeDaySection(day: group.day, items: group.items)
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your dictations will show up here")
                .font(WisprFonts.figtree(16, weight: .semibold))
                .foregroundStyle(WisprPalette.foreground)
            Text("Hold \(appState.holdShortcut.displayName) and start talking. Release to paste the text wherever your cursor is.")
                .font(WisprFonts.figtree(14))
                .foregroundStyle(WisprPalette.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WisprPalette.backgroundSecondary))
    }
}

private func displayText(for item: PipelineHistoryItem) -> String {
    let text = item.postProcessedTranscript.isEmpty ? item.rawTranscript : item.postProcessedTranscript
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Stats

private struct HomeStatsRow: View {
    @ObservedObject var stats: DictationStatsStore

    var body: some View {
        HStack(spacing: 8) {
            chip(emoji: "🔥", value: "\(stats.currentStreak())", unit: stats.currentStreak() == 1 ? "day" : "days")
            chip(emoji: "🚀", value: Self.compact(stats.totalWords), unit: "words")
            chip(emoji: "👍", value: stats.wordsPerMinute.map(String.init) ?? "–", unit: "WPM")
        }
    }

    private func chip(emoji: String, value: String, unit: String) -> some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 13))
            Text(value)
                .font(WisprFonts.figtree(14, weight: .semibold))
                .foregroundStyle(WisprPalette.foreground)
            Text(unit)
                .font(WisprFonts.figtree(13))
                .foregroundStyle(WisprPalette.mutedForeground)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(WisprPalette.backgroundSecondary))
        .overlay(Capsule().strokeBorder(WisprPalette.border, lineWidth: 1))
    }

    private static func compact(_ number: Int) -> String {
        guard number >= 10_000 else { return number.formatted() }
        let thousands = Double(number) / 1000
        return String(format: "%.1fk", thousands)
    }
}

// MARK: - Day section

private struct HomeDaySection: View {
    let day: Date
    let items: [PipelineHistoryItem]

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInYesterday(day) { return "YESTERDAY" }
        return Self.weekdayFormatter.string(from: day).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(WisprFonts.figtree(12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(WisprPalette.mutedForeground)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HomeHistoryRow(item: item)
                    if index < items.count - 1 {
                        Rectangle()
                            .fill(WisprPalette.border)
                            .frame(height: 1)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WisprPalette.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WisprPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct HomeHistoryRow: View {
    @EnvironmentObject var appState: AppState
    let item: PipelineHistoryItem
    @State private var isHovering = false
    @State private var copied = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(Self.timeFormatter.string(from: item.timestamp))
                .font(WisprFonts.figtree(13))
                .foregroundStyle(WisprPalette.mutedForeground)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 1)

            Text(displayText(for: item))
                .font(WisprFonts.figtree(14))
                .foregroundStyle(WisprPalette.foreground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copy") { copy() }
                iconButton("trash", help: "Delete") { appState.deleteHistoryEntry(id: item.id) }
            }
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(isHovering ? WisprPalette.backgroundSecondary.opacity(0.6) : Color.clear)
        .onHover { isHovering = $0 }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(WisprPalette.mutedForeground)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayText(for: item), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
