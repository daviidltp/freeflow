import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

/// Una entrada del diccionario: una palabra a respetar o una corrección fija ("mal => bien").
private struct DictionaryEntry: Identifiable, Equatable {
    enum Kind { case word, replacement }

    let kind: Kind
    let text: String
    let replacement: String?

    var id: String { "\(kind)-\(text)-\(replacement ?? "")" }
}

/// Lee y escribe las dos fuentes que ya usa la app: el vocabulario (`custom_vocabulary`)
/// y las correcciones fijas (`vocabulary_replacements`), sin cambiar su formato.
private enum DictionaryStorage {
    static func words(from vocabulary: String) -> [String] {
        vocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func replacements(from rules: String) -> [(wrong: String, right: String)] {
        rules.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { return nil }
            let wrong = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wrong.isEmpty, !right.isEmpty else { return nil }
            return (wrong, right)
        }
    }

    static func serialize(replacements: [(wrong: String, right: String)]) -> String {
        replacements.map { "\($0.wrong) => \($0.right)" }.joined(separator: "\n")
    }
}

// MARK: - View

struct DictionaryView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case words = "Words"
        case replacements = "Replacements"
        var id: String { rawValue }
    }

    @EnvironmentObject var appState: AppState
    @AppStorage(VocabularyReplacements.storageKey) private var replacementRules = ""
    @State private var filter: Filter = .all
    @State private var showingAddSheet = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var sortsAlphabetically = false
    @AppStorage("dictionary_banner_dismissed") private var bannerDismissed = false

    private var entries: [DictionaryEntry] {
        let words = DictionaryStorage.words(from: appState.customVocabulary).map {
            DictionaryEntry(kind: .word, text: $0, replacement: nil)
        }
        let replacements = DictionaryStorage.replacements(from: replacementRules).map {
            DictionaryEntry(kind: .replacement, text: $0.wrong, replacement: $0.right)
        }
        var result: [DictionaryEntry]
        switch filter {
        case .all: result = words + replacements
        case .words: result = words
        case .replacements: result = replacements
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter {
                $0.text.localizedCaseInsensitiveContains(query) || ($0.replacement?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        if sortsAlphabetically {
            result.sort { $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending }
        }
        return result
    }

    private var suggestionWords: [String] {
        Array(DictionaryStorage.words(from: appState.customVocabulary).prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader("Dictionary") {
                    HStack(spacing: 10) {
                        Button("Import") { importEntries() }
                            .buttonStyle(WisprPrimaryButtonStyle())
                        Button("Add new") { showingAddSheet = true }
                            .buttonStyle(WisprPrimaryButtonStyle())
                    }
                }

                tabBar

                if !bannerDismissed {
                    banner
                }

                if isSearching {
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }

                if entries.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            DictionaryRow(entry: entry) { remove(entry) }
                            if index < entries.count - 1 {
                                Rectangle().fill(WisprPalette.border).frame(height: 1)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(WisprPalette.card))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(WisprPalette.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddDictionaryEntrySheet(isPresented: $showingAddSheet) { word, replacement in
                add(word: word, replacement: replacement)
            }
        }
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 26) {
                ForEach(Filter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        VStack(spacing: 10) {
                            Text(option.rawValue)
                                .font(WisprFonts.figtree(15, weight: filter == option ? .semibold : .medium))
                                .foregroundStyle(filter == option ? WisprPalette.foreground : WisprPalette.mutedForeground)
                            Rectangle()
                                .fill(filter == option ? WisprPalette.foreground : Color.clear)
                                .frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                toolbarIcon("magnifyingglass", active: isSearching) {
                    isSearching.toggle()
                    if !isSearching { searchText = "" }
                }
                toolbarIcon("arrow.up.arrow.down", active: sortsAlphabetically) { sortsAlphabetically.toggle() }
            }
            Rectangle().fill(WisprPalette.border).frame(height: 1)
        }
    }

    private func toolbarIcon(_ name: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 15))
                .foregroundStyle(active ? WisprPalette.foreground : WisprPalette.mutedForeground)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    /// Banner cálido con las primeras palabras del diccionario como atajos.
    private var banner: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 14) {
                (Text("\(AppName.displayName) spells the way ") + Text("you").italic() + Text(" do."))
                    .font(WisprFonts.serif(40, weight: .regular))
                    .foregroundStyle(.white)
                Text("Correct a spelling once or add it here manually, so your **personal terms, company jargon, or uncommon names** are spelled right in every dictation.")
                    .font(WisprFonts.figtree(15))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button { showingAddSheet = true } label: {
                        Text("Add new word")
                            .font(WisprFonts.figtree(15, weight: .medium))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                    ForEach(suggestionWords, id: \.self) { word in
                        Text(word)
                            .font(WisprFonts.figtree(15, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.22)))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { bannerDismissed = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: 0x2B1D18), Color(hex: 0x5C3F2A), Color(hex: 0x9A6C3D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No entries yet")
                .font(WisprFonts.figtree(16, weight: .semibold))
                .foregroundStyle(WisprPalette.foreground)
            Text("Add names, brands or technical terms, or set a fixed correction for something that keeps getting misheard.")
                .font(WisprFonts.figtree(14))
                .foregroundStyle(WisprPalette.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WisprPalette.backgroundSecondary))
    }

    /// Importa un archivo de texto: una entrada por línea, o `mal => bien` para correcciones.
    private func importEntries() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "=>")
            if parts.count == 2 {
                add(word: parts[0], replacement: parts[1])
            } else {
                for word in DictionaryStorage.words(from: String(line)) { add(word: word, replacement: nil) }
            }
        }
    }

    private func add(word: String, replacement: String?) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }
        if let replacement = replacement?.trimmingCharacters(in: .whitespacesAndNewlines), !replacement.isEmpty {
            var rules = DictionaryStorage.replacements(from: replacementRules)
            rules.removeAll { $0.wrong.caseInsensitiveCompare(trimmedWord) == .orderedSame }
            rules.append((trimmedWord, replacement))
            replacementRules = DictionaryStorage.serialize(replacements: rules)
        } else {
            var words = DictionaryStorage.words(from: appState.customVocabulary)
            guard !words.contains(where: { $0.caseInsensitiveCompare(trimmedWord) == .orderedSame }) else { return }
            words.append(trimmedWord)
            appState.customVocabulary = words.joined(separator: "\n")
        }
    }

    private func remove(_ entry: DictionaryEntry) {
        switch entry.kind {
        case .word:
            let words = DictionaryStorage.words(from: appState.customVocabulary).filter { $0 != entry.text }
            appState.customVocabulary = words.joined(separator: "\n")
        case .replacement:
            let rules = DictionaryStorage.replacements(from: replacementRules)
                .filter { !($0.wrong == entry.text && $0.right == entry.replacement) }
            replacementRules = DictionaryStorage.serialize(replacements: rules)
        }
    }
}

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            if let replacement = entry.replacement {
                Text(entry.text)
                    .foregroundStyle(WisprPalette.mutedForeground)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WisprPalette.mutedForeground)
                Text(replacement)
                    .foregroundStyle(WisprPalette.foreground)
            } else {
                Text(entry.text)
                    .foregroundStyle(WisprPalette.foreground)
            }
            Spacer(minLength: 8)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WisprPalette.mutedForeground)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help("Remove")
        }
        .font(WisprFonts.figtree(14))
        .padding(.horizontal, 20)
        .frame(height: 54)
        .background(isHovering ? WisprPalette.backgroundSecondary.opacity(0.6) : Color.clear)
        .onHover { isHovering = $0 }
    }
}

private struct AddDictionaryEntrySheet: View {
    @Binding var isPresented: Bool
    let onAdd: (String, String?) -> Void

    @State private var isCorrection = false
    @State private var word = ""
    @State private var replacement = ""

    private var canAdd: Bool {
        let hasWord = !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasReplacement = !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasWord && (!isCorrection || hasReplacement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add to dictionary")
                .font(WisprFonts.figtree(26, weight: .medium))
                .foregroundStyle(WisprPalette.foreground)

            Toggle("Correct a misspelling", isOn: $isCorrection)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                Text(isCorrection ? "Misspelling" : "Word or phrase")
                    .font(WisprFonts.figtree(12, weight: .semibold))
                    .foregroundStyle(WisprPalette.mutedForeground)
                TextField(isCorrection ? "e.g. cut max" : "e.g. Cutmax", text: $word)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
            }

            if isCorrection {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Correct spelling")
                        .font(WisprFonts.figtree(12, weight: .semibold))
                        .foregroundStyle(WisprPalette.mutedForeground)
                    TextField("e.g. Cutmax", text: $replacement)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add word", action: submit)
                    .buttonStyle(WisprPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : 0.4)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(WisprPalette.background)
        .font(WisprFonts.figtree(13))
    }

    private func submit() {
        guard canAdd else { return }
        onAdd(word, isCorrection ? replacement : nil)
        isPresented = false
    }
}
