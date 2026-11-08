import SwiftUI
import AVFoundation
import ServiceManagement

// MARK: - Shared Helpers

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WisprPalette.mutedForeground)
                    .frame(width: 16)
                Text(title)
                    .font(WisprFonts.figtree(15, weight: .semibold))
                    .foregroundStyle(WisprPalette.foreground)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(WisprPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WisprPalette.border, lineWidth: 1)
        )
    }
}

// MARK: - Filas al estilo de Hex

/// Grupo de filas dentro de una tarjeta con borde fino, como en los ajustes de Hex.
struct SettingsGroup<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(WisprFonts.figtree(13, weight: .semibold))
                    .foregroundStyle(WisprPalette.mutedForeground)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(WisprPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(WisprPalette.border, lineWidth: 1)
            )
        }
    }
}

/// Separador entre filas, alineado con el texto (después del icono).
struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(WisprPalette.border)
            .frame(height: 1)
            .padding(.leading, 34)
    }
}

/// Fila: icono, título y explicación opcional a la izquierda; valor o control a la derecha.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String?
    let trailing: Trailing

    init(_ title: String, icon: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.icon = icon
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(WisprPalette.foreground.opacity(0.75))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(WisprFonts.figtree(14, weight: .medium))
                    .foregroundStyle(WisprPalette.foreground)
                if let detail {
                    Text(detail)
                        .font(WisprFonts.figtree(12))
                        .foregroundStyle(WisprPalette.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, detail == nil ? 14 : 12)
        .frame(minHeight: 52)
    }
}

/// Valor de la derecha que abre un menú: texto en negrita y una flecha, sin borde.
struct SettingsMenu<Content: View>: View {
    let value: String
    let content: Content

    init(_ value: String, @ViewBuilder content: () -> Content) {
        self.value = value
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            // Un solo Text: el menú de macOS coloca las imágenes sueltas delante del texto.
            (Text(value).font(WisprFonts.figtree(14, weight: .semibold))
                + Text("  ")
                + Text(Image(systemName: "chevron.up.chevron.down"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(WisprPalette.mutedForeground))
                .foregroundColor(WisprPalette.foreground)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private let iso8601DayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

struct ProviderSettingsFields: View {
    @EnvironmentObject var appState: AppState
    @Binding var apiBaseURLInput: String
    @Binding var transcriptionAPIURLInput: String
    @Binding var transcriptionAPIKeyInput: String
    @FocusState private var isEditingAPIBaseURL: Bool
    @FocusState private var isEditingTranscriptionModel: Bool
    @FocusState private var isEditingRealtimeStreamingModel: Bool
    @FocusState private var isEditingPostProcessingModel: Bool
    @FocusState private var isEditingPostProcessingFallbackModel: Bool
    @FocusState private var isEditingContextModel: Bool
    @FocusState private var transcriptionAPIURLFocused: Bool
    @FocusState private var transcriptionAPIKeyFocused: Bool
    @State private var transcriptionModelDraft: String = ""
    @State private var realtimeStreamingModelDraft: String = ""
    @State private var postProcessingModelDraft: String = ""
    @State private var postProcessingFallbackModelDraft: String = ""
    @State private var contextModelDraft: String = ""
    /// Updated by the cooldown timer so warning labels clear at expiry without user interaction.
    @State private var now: Date = Date()
    /// Tracks whether the Settings window is the frontmost active window.
    @Environment(\.controlActiveState) private var controlActiveState

    let showsModelDescription: Bool

    private func commitAPIBaseURL() {
        let trimmed = apiBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        apiBaseURLInput = trimmed.isEmpty ? AppState.defaultAPIBaseURL : trimmed
    }

    private func commitTranscriptionModel() {
        let trimmed = transcriptionModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriptionModelDraft = trimmed
        guard appState.transcriptionModel != trimmed else { return }
        appState.transcriptionModel = trimmed
    }

    private func commitRealtimeStreamingModel() {
        let trimmed = realtimeStreamingModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        realtimeStreamingModelDraft = trimmed
        guard appState.realtimeStreamingModel != trimmed else { return }
        appState.realtimeStreamingModel = trimmed
    }

    private func commitPostProcessingModel() {
        let trimmed = postProcessingModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        postProcessingModelDraft = trimmed
        guard appState.postProcessingModel != trimmed else { return }
        appState.postProcessingModel = trimmed
    }

    private func commitPostProcessingFallbackModel() {
        let trimmed = postProcessingFallbackModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        postProcessingFallbackModelDraft = trimmed
        guard appState.postProcessingFallbackModel != trimmed else { return }
        appState.postProcessingFallbackModel = trimmed
    }

    /// True when this view's hosting window is the frontmost key window. While true a 5s timer
    /// advances `now`, so a daily-limit warning appears within ~5s of being written and clears
    /// within ~5s of expiry. SwiftUI removes the timer when this view leaves the hierarchy
    /// (switching tabs or dismissing the Setup sheet). The timer must NOT be gated on a warning
    /// already being visible: nothing else observes the UserDefaults cooldown keys, so a freshly
    /// written cooldown would otherwise never trigger a re-render. Cost is negligible.
    private var shouldRunCooldownTimer: Bool {
        controlActiveState == .key
    }

    /// Reads the persisted daily-limit expiry date for a model directly from UserDefaults.
    /// Uses the shared key from LLMCooldownManager to avoid duplicating the storage contract.
    /// Returns nil if no daily limit is active or if the entry has already expired.
    private func dailyCooldownExpiry(for model: String) -> Date? {
        let key = LLMCooldownManager.udKey(for: model)
        let timestamp = UserDefaults.standard.double(forKey: key)
        guard timestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: timestamp)
        return date > now ? date : nil
    }

    /// Formats a cooldown reset time, including the date only when the reset falls on a later day,
    /// so a daily limit that resets after midnight is not shown as an ambiguous bare time.
    private func formattedCooldownReset(_ expiry: Date) -> String {
        // Calendar.isDate(_:inSameDayAs:) is a macOS-native calendar-aware same-day comparison.
        if Calendar.current.isDate(expiry, inSameDayAs: now) {
            return expiry.formatted(date: .omitted, time: .shortened)
        }
        return expiry.formatted(date: .abbreviated, time: .shortened)
    }

    private func commitContextModel() {
        let trimmed = contextModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        contextModelDraft = trimmed
        guard appState.contextModel != trimmed else { return }
        appState.contextModel = trimmed
    }

    private func commitTranscriptionAPIURL() {
        transcriptionAPIURLInput = transcriptionAPIURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitTranscriptionAPIKey() {
        transcriptionAPIKeyInput = transcriptionAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Base URL")
                .font(.caption.weight(.semibold))

            Text("Change this to use a different OpenAI-compatible API provider.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(AppState.defaultAPIBaseURL, text: $apiBaseURLInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($isEditingAPIBaseURL)
                    .onSubmit {
                        commitAPIBaseURL()
                    }
                    .onChange(of: isEditingAPIBaseURL) { isEditing in
                        if !isEditing {
                            commitAPIBaseURL()
                        }
                    }

                Button("Reset to Default") {
                    apiBaseURLInput = AppState.defaultAPIBaseURL
                }
                .font(.caption)
            }

            if showsModelDescription {
                Text("If you use another provider, enter that provider's model IDs here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ModelDropdownView(
                title: "Post-Processing Model",
                subtitle: "Used for transcript cleanup and Edit Mode transforms.",
                predefinedModels: ModelConfiguration.llmModels,
                defaultModel: AppState.defaultPostProcessingModel,
                textDraft: $postProcessingModelDraft,
                onCommit: commitPostProcessingModel,
                onReset: {
                    postProcessingModelDraft = AppState.defaultPostProcessingModel
                    appState.postProcessingModel = AppState.defaultPostProcessingModel
                }
            )

            // Shows when this model has hit its daily Groq rate limit.
            // Disappears automatically once the limit window resets.
            if let expiry = dailyCooldownExpiry(for: appState.postProcessingModel) {
                Label {
                    Text("Daily limit reached — resets at \(formattedCooldownReset(expiry))")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            ModelDropdownView(
                title: "Post-Processing Fallback Model",
                subtitle: "Used as the explicit retry model for transcript cleanup and Edit Mode transforms.",
                predefinedModels: ModelConfiguration.llmModels,
                defaultModel: AppState.defaultPostProcessingFallbackModel,
                textDraft: $postProcessingFallbackModelDraft,
                onCommit: commitPostProcessingFallbackModel,
                onReset: {
                    postProcessingFallbackModelDraft = AppState.defaultPostProcessingFallbackModel
                    appState.postProcessingFallbackModel = AppState.defaultPostProcessingFallbackModel
                }
            )

            // Shows when the fallback model has also hit its daily limit.
            // In this state, both models are unavailable until their limits reset.
            if let expiry = dailyCooldownExpiry(for: appState.postProcessingFallbackModel) {
                Label {
                    Text("Fallback daily limit reached — resets at \(formattedCooldownReset(expiry))")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            ModelDropdownView(
                title: "Context Model",
                subtitle: "Used for context inference, with a text-only retry when screenshot analysis fails. Screenshot analysis requires a model that accepts image input.",
                predefinedModels: ModelConfiguration.visionModels,
                defaultModel: AppState.defaultContextModel,
                textDraft: $contextModelDraft,
                onCommit: commitContextModel,
                onReset: {
                    contextModelDraft = AppState.defaultContextModel
                    appState.contextModel = AppState.defaultContextModel
                }
            )

            ModelDropdownView(
                title: "Transcription Model",
                subtitle: "Used for speech-to-text transcription.",
                predefinedModels: ModelConfiguration.transcriptionModels,
                defaultModel: AppState.defaultTranscriptionModel,
                textDraft: $transcriptionModelDraft,
                onCommit: commitTranscriptionModel,
                onReset: {
                    transcriptionModelDraft = AppState.defaultTranscriptionModel
                    appState.transcriptionModel = AppState.defaultTranscriptionModel
                }
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription Language")
                    .font(.caption.weight(.semibold))
                Picker("", selection: $appState.transcriptionLanguage) {
                    ForEach(AppState.transcriptionLanguageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .accessibilityLabel("Transcription Language")
                .labelsHidden()
                Text("Hint to the transcription model. Auto-detect works for most users. Pick a specific language if you see wrong-script characters (for example Chinese) appear in your output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription API URL")
                    .font(.caption.weight(.semibold))
                HStack(spacing: 8) {
                    TextField("Uses API Base URL when empty", text: $transcriptionAPIURLInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($transcriptionAPIURLFocused)
                        .onSubmit {
                            commitTranscriptionAPIURL()
                        }
                        .onChange(of: transcriptionAPIURLFocused) { isFocused in
                            if !isFocused {
                                commitTranscriptionAPIURL()
                            }
                        }
                    if !transcriptionAPIURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Clear") {
                            transcriptionAPIURLInput = ""
                        }
                        .font(.caption)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription API Key")
                    .font(.caption.weight(.semibold))
                HStack(spacing: 8) {
                    SecureField("Uses API Key when empty", text: $transcriptionAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($transcriptionAPIKeyFocused)
                        .onSubmit {
                            commitTranscriptionAPIKey()
                        }
                        .onChange(of: transcriptionAPIKeyFocused) { isFocused in
                            if !isFocused {
                                commitTranscriptionAPIKey()
                            }
                        }
                    if !transcriptionAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Clear") {
                            transcriptionAPIKeyInput = ""
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()

            Toggle(
                "Stream audio while recording (realtime)",
                isOn: $appState.realtimeStreamingEnabled
            )
            Text("Streams audio through the provider's OpenAI-compatible /v1/realtime WebSocket so transcription runs while you speak.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Realtime Transcription Model")
                    .font(.caption.weight(.semibold))
                HStack(spacing: 8) {
                    TextField("Required by some providers, e.g. gpt-4o-transcribe", text: $realtimeStreamingModelDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingRealtimeStreamingModel)
                        .onSubmit {
                            commitRealtimeStreamingModel()
                        }
                        .onChange(of: isEditingRealtimeStreamingModel) { isEditing in
                            if !isEditing {
                                commitRealtimeStreamingModel()
                            }
                        }
                    if !realtimeStreamingModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Reset") {
                            realtimeStreamingModelDraft = ""
                            appState.realtimeStreamingModel = ""
                        }
                        .font(.caption)
                    }
                }
                Text("Used only for realtime streaming. Leave empty for providers that supply a server default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            transcriptionModelDraft = appState.transcriptionModel
            realtimeStreamingModelDraft = appState.realtimeStreamingModel
            postProcessingModelDraft = appState.postProcessingModel
            postProcessingFallbackModelDraft = appState.postProcessingFallbackModel
            contextModelDraft = appState.contextModel
        }
        .onChange(of: appState.transcriptionModel) { value in
            if !isEditingTranscriptionModel {
                transcriptionModelDraft = value
            }
        }
        .onChange(of: appState.realtimeStreamingModel) { value in
            if !isEditingRealtimeStreamingModel {
                realtimeStreamingModelDraft = value
            }
        }
        .onChange(of: appState.postProcessingModel) { value in
            if !isEditingPostProcessingModel {
                postProcessingModelDraft = value
            }
        }
        .onChange(of: appState.postProcessingFallbackModel) { value in
            if !isEditingPostProcessingFallbackModel {
                postProcessingFallbackModelDraft = value
            }
        }
        .onChange(of: appState.contextModel) { value in
            if !isEditingContextModel {
                contextModelDraft = value
            }
        }
        // Tick every 5s while this view's window is key so a daily-limit warning can appear and
        // auto-clear without any external state change. SwiftUI removes this timer when the
        // window is backgrounded or this view leaves the hierarchy (tab switch or sheet dismissal).
        if shouldRunCooldownTimer {
            Color.clear.frame(width: 0, height: 0)
                .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { value in
                    now = value
                }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            MainSidebar()
                .frame(width: 196)

            Group {
                switch appState.selectedSettingsTab {
                case .home, .none:
                    HomeView()
                case .dictionary:
                    DictionaryView()
                case .snippets:
                    VoiceMacrosSettingsView()
                case .style:
                    StyleView()
                case .insights:
                    InsightsView()
                case .settings:
                    GeneralSettingsView()
                case .debug:
                    DebugSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WisprPalette.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(WisprPalette.border, lineWidth: 1)
            )
            .padding(.top, 8)
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        }
        .background(WisprPalette.backgroundSecondary)
        .overlay(alignment: .top) {
            // Solo la franja superior arrastra la ventana, como en el resto de apps.
            WindowDragArea()
                .frame(height: 36)
        }
        .font(WisprFonts.figtree(13))
        .tint(WisprPalette.foreground)
    }
}

/// Vista transparente que mueve la ventana al arrastrar sobre ella.
private struct WindowDragArea: NSViewRepresentable {
    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Barra lateral: logo de la app, secciones principales y Settings abajo.
private struct MainSidebar: View {
    @EnvironmentObject var appState: AppState

    private let mainTabs: [SettingsTab] = [.home, .insights, .dictionary, .snippets, .style]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                Text(AppName.displayName)
                    .font(WisprFonts.figtree(17, weight: .semibold))
                    .foregroundStyle(WisprPalette.foreground)
            }
            .padding(.leading, 12)
            .padding(.top, 38)
            .padding(.bottom, 22)

            ForEach(mainTabs) { tab in
                row(tab)
            }

            Spacer()

            if AppBuild.isDevBundle {
                row(.debug)
            }
            row(.settings)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ tab: SettingsTab) -> some View {
        let isSelected = (appState.selectedSettingsTab ?? .home) == tab
        return Button {
            appState.selectedSettingsTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18, height: 18)
                Text(tab.title)
                    .font(WisprFonts.figtree(14, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? WisprPalette.foreground : WisprPalette.mutedForeground)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? WisprPalette.backgroundTertiary : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Cabecera de página con título en serif y acción opcional a la derecha.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(WisprFonts.figtree(24, weight: .medium))
                    .foregroundStyle(WisprPalette.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(WisprFonts.figtree(14))
                        .foregroundStyle(WisprPalette.mutedForeground)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

/// Botón principal: pill negro con texto claro (invertido en modo oscuro).
struct WisprPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WisprFonts.figtree(13, weight: .semibold))
            .foregroundStyle(WisprPalette.background)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(WisprPalette.foreground))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Debug Settings

struct DebugSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader("Debug")

                SettingsCard("Overlay", icon: "wrench.and.screwdriver") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Show the recording overlay with simulated audio levels.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(appState.isDebugOverlayActive ? "Stop Debug Overlay" : "Debug Overlay") {
                            appState.toggleDebugOverlay()
                        }
                    }
                }

                SettingsCard("Update Overlay", icon: "arrow.down.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Display the update available overlay after dictation finishes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle("Show after dictation", isOn: $appState.debugShowsUpdateReminderAfterDictation)

                        Button("Show Update Overlay Now") {
                            appState.showDebugUpdateAvailableOverlay()
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    @AppStorage("show_menu_bar_icon") private var showMenuBarIcon = true
    @AppStorage("overlay_display_id") private var overlayDisplayID = 0
    @AppStorage(IdleIslandPreference.storageKey) private var showIdleIsland = true
    @AppStorage(RecordingTimerPreference.storageKey) private var showRecordingTimer = RecordingTimerPreference.defaultEnabled
    @AppStorage(IslandThemePreference.storageKey) private var islandTheme = IslandThemePreference.system.rawValue
    @AppStorage(IslandAnchor.storageKey) private var islandAnchor = IslandAnchor.bottom.rawValue
    @AppStorage(IslandChipStyle.storageKey) private var chipStyle = IslandChipStyle.classic.rawValue
    @State private var showsShortcutEditor = false
    @State private var showsAdvanced = false
    @ObservedObject private var parakeet = LocalParakeetEngine.shared
    @State private var screensVersion = 0
    @State private var apiDraft = APIConfigurationDraft()
    @State private var advancedProviderSettingsExpanded = false
    @State private var isValidatingKey = false
    @State private var keyValidationError: String?
    @State private var successfulAPIConfiguration: ValidatedAPIConfiguration?
    @State private var micPermissionGranted = false
    @State private var showMutedHint = false
    @State private var copiedBuildInfo = false
    @State private var copiedBuildInfoResetWorkItem: DispatchWorkItem?
    @ObservedObject private var updateManager = UpdateManager.shared

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "\(AppName.displayName)"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var appBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "FreeFlowBuildTag") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "unknown"
    }

    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var appArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private var buildDiagnosticsText: String {
        "\(appDisplayName) \(appVersion) (\(appBuildNumber))\nmacOS \(macOSVersion) (\(appArchitecture))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("General")
                    .font(WisprFonts.figtree(20, weight: .semibold))
                    .foregroundStyle(WisprPalette.foreground)
                    .padding(.leading, 4)

                generalGroup
                islandGroup
                textGroup
                advancedSection
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .onAppear {
            apiDraft.present(appState.committedAPIConfiguration)
            isValidatingKey = false
            keyValidationError = nil
            successfulAPIConfiguration = nil
            checkMicPermission()
            appState.refreshLaunchAtLoginStatus()
        }
        .onDisappear {
            apiDraft.dismiss()
        }
        .onChange(of: appState.committedAPIConfiguration) { saved in
            apiDraft.reconcile(saved)
            keyValidationError = nil
            if successfulAPIConfiguration != saved {
                successfulAPIConfiguration = nil
            }
        }
        .onChange(of: apiDraft.configuration) { value in
            keyValidationError = nil
            if successfulAPIConfiguration != value {
                successfulAPIConfiguration = nil
            }
        }
    }

    // MARK: General

    private var shortcutSummary: String {
        let hold = appState.holdShortcut
        let toggle = appState.toggleShortcut
        switch (hold.isDisabled, toggle.isDisabled) {
        case (false, false): return "Mantén \(hold.displayName) · pulsa \(toggle.displayName)"
        case (false, true): return "Mantén \(hold.displayName)"
        case (true, false): return "Pulsa \(toggle.displayName)"
        case (true, true): return "Desactivado"
        }
    }

    private var engineValue: String {
        switch appState.transcriptionEngine {
        case .parakeet: return "Parakeet v3"
        case .cloud: return Self.modelLabel(appState.transcriptionModel)
        }
    }

    /// Nombre corto de un modelo: sin el proveedor delante y con el estilo de Hex.
    private static func modelLabel(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Whisper large-v3" }
        if trimmed.hasPrefix("whisper-") {
            return "Whisper " + trimmed.dropFirst("whisper-".count)
        }
        return String(trimmed.split(separator: "/").last ?? Substring(trimmed))
    }

    private var engineDetail: String {
        switch appState.transcriptionEngine {
        case .cloud:
            return "En la nube, con tu proveedor."
        case .parakeet:
            switch parakeet.status {
            case .ready: return "En tu Mac, sin internet. Listo."
            case .loading: return "En tu Mac. Cargando el modelo…"
            case .stopped: return "En tu Mac. Se carga al dictar."
            case let .failed(message): return "No se pudo cargar: \(message)"
            }
        }
    }

    private var microphoneValue: String {
        let id = appState.selectedMicrophoneID
        if id.isEmpty || id == "default" { return "El del sistema" }
        return appState.availableMicrophones.first { $0.uid == id }?.name ?? "El del sistema"
    }

    private var generalGroup: some View {
        SettingsGroup {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsShortcutEditor.toggle() }
            } label: {
                SettingsRow("Atajo", icon: "keyboard") {
                    HStack(spacing: 6) {
                        Text(shortcutSummary)
                            .font(WisprFonts.figtree(14, weight: .semibold))
                            .foregroundStyle(WisprPalette.foreground)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WisprPalette.mutedForeground)
                            .rotationEffect(.degrees(showsShortcutEditor ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsShortcutEditor {
                VStack(alignment: .leading, spacing: 14) {
                    DictationShortcutEditor(showsIntroText: false) { isCapturing in
                        if isCapturing {
                            appState.suspendHotkeyMonitoringForShortcutCapture()
                        } else {
                            appState.resumeHotkeyMonitoringAfterShortcutCapture()
                        }
                    }
                }
                .padding(.leading, 34)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
            SettingsRowDivider()
            SettingsRow("Modelo de voz", icon: "waveform", detail: engineDetail) {
                SettingsMenu(engineValue) {
                    Section("En tu Mac") {
                        Button("Parakeet v3") { appState.transcriptionEngine = .parakeet }
                    }
                    Section("En la nube") {
                        ForEach(ModelConfiguration.transcriptionModels, id: \.self) { model in
                            Button(Self.modelLabel(model)) {
                                appState.transcriptionModel = model
                                appState.transcriptionEngine = .cloud
                            }
                        }
                    }
                }
            }
            SettingsRowDivider()
            SettingsRow("Modelo de limpieza", icon: "wand.and.stars", detail: "La IA que limpia el texto. Otros modelos, en Avanzado.") {
                SettingsMenu(Self.modelLabel(appState.postProcessingModel)) {
                    ForEach(ModelConfiguration.llmModels, id: \.self) { model in
                        Button(Self.modelLabel(model)) { appState.postProcessingModel = model }
                    }
                }
                .disabled(appState.preserveExactWording)
            }
            SettingsRowDivider()
            SettingsRow("Idioma de salida", icon: "character.bubble") {
                SettingsMenu(appState.outputLanguage.isEmpty ? "El que hablas" : appState.outputLanguage) {
                    Button("El que hablas") { appState.outputLanguage = "" }
                    ForEach(Self.outputLanguageOptions.dropFirst(), id: \.self) { lang in
                        Button(lang) { appState.outputLanguage = lang }
                    }
                }
            }
            SettingsRowDivider()
            SettingsRow("Micrófono", icon: "mic") {
                SettingsMenu(microphoneValue) {
                    Button("El del sistema") { appState.selectedMicrophoneID = "default" }
                    ForEach(appState.availableMicrophones) { device in
                        Button(device.name) { appState.selectedMicrophoneID = device.uid }
                    }
                }
            }
            SettingsRowDivider()
            SettingsRow("Limpieza con IA", icon: "sparkles", detail: "Quita muletillas y deja solo lo que corriges.") {
                Toggle("", isOn: Binding(
                    get: { !appState.preserveExactWording },
                    set: { appState.preserveExactWording = !$0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            SettingsRowDivider()
            SettingsRow("Iniciar al iniciar sesión", icon: "power") {
                Toggle("", isOn: $appState.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .onAppear { appState.refreshAvailableMicrophones() }
    }

    // MARK: Island

    private var anchorValue: String {
        switch IslandAnchor(rawValue: islandAnchor) ?? .bottom {
        case .top: return "Arriba"
        case .bottom: return "Abajo"
        case .left: return "Izquierda"
        case .right: return "Derecha"
        }
    }

    private var displayValue: String {
        switch overlayDisplayID {
        case 0: return "La de la ventana activa"
        case -1: return "La principal"
        default: return connectedScreenEntries.first { $0.tag == overlayDisplayID }?.name ?? "La de la ventana activa"
        }
    }

    private var islandGroup: some View {
        SettingsGroup("Isla") {
            SettingsRow("Estilo", icon: "waveform.path", detail: "Cómo se ve la isla mientras grabas y procesas.") {
                SettingsMenu((IslandChipStyle(rawValue: chipStyle) ?? .classic).label) {
                    ForEach(IslandChipStyle.allCases) { style in
                        Button(style.label) { chipStyle = style.rawValue }
                    }
                }
            }
            SettingsRowDivider()
            SettingsRow("Tema", icon: "circle.lefthalf.filled", detail: "Para el estilo de puntos.") {
                SettingsMenu((IslandThemePreference(rawValue: islandTheme) ?? .system).label) {
                    ForEach(IslandThemePreference.allCases) { theme in
                        Button(theme.label) { islandTheme = theme.rawValue }
                    }
                }
            }
            SettingsRowDivider()
            SettingsRow("Posición", icon: "rectangle.center.inset.filled", detail: "También puedes arrastrar la barrita en reposo.") {
                SettingsMenu(anchorValue) {
                    Button("Arriba") { setAnchor(.top) }
                    Button("Abajo") { setAnchor(.bottom) }
                    Button("Izquierda") { setAnchor(.left) }
                    Button("Derecha") { setAnchor(.right) }
                }
            }
            SettingsRowDivider()
            SettingsRow("Pantalla", icon: "display") {
                SettingsMenu(displayValue) {
                    Button("La de la ventana activa") { overlayDisplayID = 0 }
                    Button("La principal") { overlayDisplayID = -1 }
                    ForEach(connectedScreenEntries, id: \.tag) { entry in
                        Button(entry.name) { overlayDisplayID = entry.tag }
                    }
                }
            }
            SettingsRowDivider()
            SettingsRow("Barrita en reposo", icon: "capsule", detail: "Al pasar el ratón se convierte en un botón para dictar.") {
                Toggle("", isOn: $showIdleIsland)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: showIdleIsland) { _ in appState.overlayManager.refreshIdleIsland() }
            }
            SettingsRowDivider()
            SettingsRow("Cronómetro", icon: "timer") {
                Toggle("", isOn: $showRecordingTimer)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screensVersion &+= 1
        }
    }

    private func setAnchor(_ anchor: IslandAnchor) {
        islandAnchor = anchor.rawValue
        appState.overlayManager.applyAnchorChange()
    }

    // MARK: Text

    private func switchRow(_ title: String, icon: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        SettingsRow(title, icon: icon, detail: detail) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var textGroup: some View {
        SettingsGroup("Texto y audio") {
            switchRow("Pegar donde empezaste", icon: "text.cursor", detail: "Aunque cambies de app mientras hablas.", isOn: $appState.originalFieldInsertionEnabled)
            SettingsRowDivider()
            switchRow("Decir \"press enter\" para enviar", icon: "return", isOn: $appState.isPressEnterVoiceCommandEnabled)
            SettingsRowDivider()
            switchRow("Recuperar el portapapeles", icon: "doc.on.clipboard", detail: "Después de pegar, vuelve lo que tenías copiado.", isOn: $appState.preserveClipboard)
            SettingsRowDivider()
            switchRow("Guardar en el historial del portapapeles", icon: "clock.arrow.circlepath", isOn: $appState.keepDictationInClipboardHistory)
            SettingsRowDivider()
            switchRow("Silenciar el audio al dictar", icon: "speaker.slash", isOn: $appState.dictationAudioInterruptionEnabled)
            SettingsRowDivider()
            switchRow("Sonidos de aviso", icon: "bell", isOn: $appState.alertSoundsEnabled)
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsAdvanced.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Avanzado")
                        .font(WisprFonts.figtree(14, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showsAdvanced ? 90 : 0))
                }
                .foregroundStyle(WisprPalette.mutedForeground)
                .padding(.leading, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsAdvanced {
                VStack(spacing: 16) {
                    SettingsCard("Clave de API", icon: "key.fill") { apiKeySection }
                    SettingsCard("Modo edición", icon: "pencil") { commandModeSection }
                    SettingsCard("Retraso al empezar", icon: "timer") { startDelaySection }
                    SettingsCard("Volumen de los sonidos", icon: "speaker.wave.2.fill") { soundVolumeSection }
                    SettingsCard("Permisos", icon: "lock.shield.fill") { permissionsSection }
                    SettingsCard("App", icon: "menubar.rectangle") { startupSection }
                    SettingsCard("Actualizaciones", icon: "arrow.triangle.2.circlepath") { updatesSection }
                    SettingsCard("Versión", icon: "info.circle.fill") { buildInfoSection }
                }
                .transition(.opacity)
            }
        }
    }

    private var startDelaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Espera antes de grabar")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(appState.shortcutStartDelayMilliseconds) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $appState.shortcutStartDelay, in: 0...0.5, step: 0.025)
            Text("Parar siempre es inmediato.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Startup

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Icono en la barra de menús", isOn: $showMenuBarIcon)

            if SMAppService.mainApp.status == .requiresApproval {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Tienes que aprobarlo en Ajustes del Sistema.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Abrir ajustes") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Buscar actualizaciones automáticamente", isOn: Binding(
                get: { updateManager.autoCheckEnabled },
                set: { updateManager.autoCheckEnabled = $0 }
            ))

            HStack(spacing: 10) {
                Button {
                    Task {
                        await updateManager.checkForUpdates(userInitiated: true)
                    }
                } label: {
                    if updateManager.isChecking {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Buscando…")
                        }
                    } else {
                        Text("Buscar ahora")
                    }
                }
                .disabled(updateManager.isChecking || updateManager.updateStatus != .idle)

                if let lastCheck = updateManager.lastCheckDate {
                    Text("Última vez: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if updateManager.updateAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    switch updateManager.updateStatus {
                    case .downloading:
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Descargando actualización…")
                                    .font(.caption.weight(.semibold))
                                ProgressView(value: updateManager.downloadProgress ?? 0)
                                    .progressViewStyle(.linear)
                                if let progress = updateManager.downloadProgress {
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Cancelar") {
                                updateManager.cancelDownload()
                            }
                            .font(.caption)
                        }

                    case .installing:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Instalando actualización…")
                                .font(.caption.weight(.semibold))
                        }

                    case .readyToRelaunch:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Reiniciando…")
                                .font(.caption.weight(.semibold))
                        }

                    case .error(let message):
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                            Button("Reintentar") {
                                updateManager.updateStatus = .idle
                                if let release = updateManager.latestRelease {
                                    updateManager.downloadAndInstall(release: release)
                                }
                            }
                            .font(.caption)
                        }

                    case .idle:
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                            Text(updateManager.latestReleaseVersion.isEmpty
                                ? "Hay una versión nueva de \(AppName.displayName)"
                                : "\(AppName.displayName) v\(updateManager.latestReleaseVersion) disponible")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Novedades") {
                                updateManager.showReleaseNotes()
                            }
                            .font(.caption)
                            Button("Actualizar") {
                                if let release = updateManager.latestRelease {
                                    updateManager.downloadAndInstall(release: release)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }

    // MARK: Build

    private var buildInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Compilación")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(appBuildNumber)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 12) {
                Text(buildDiagnosticsText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer()

                Button {
                    copyBuildDiagnostics()
                } label: {
                    Label(copiedBuildInfo ? "Copiado" : "Copiar", systemImage: copiedBuildInfo ? "checkmark" : "doc.on.doc")
                }
                .font(.caption)
            }
        }
    }

    private func copyBuildDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(buildDiagnosticsText, forType: .string)
        copiedBuildInfo = true

        copiedBuildInfoResetWorkItem?.cancel()

        let resetWorkItem = DispatchWorkItem {
            copiedBuildInfo = false
            copiedBuildInfoResetWorkItem = nil
        }
        copiedBuildInfoResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }

    // MARK: API Key

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Se usa para limpiar el texto con IA y, si transcribes en la nube, también para transcribir.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                SecureField("Tu clave de API de Groq", text: $apiDraft.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isValidatingKey)

                Button(isValidatingKey ? "Comprobando…" : "Guardar") {
                    validateAndSaveKey()
                }
                .disabled(apiDraft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingKey)
            }

            if let error = keyValidationError {
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if apiDraft.showsSavedSuccess(successfulAPIConfiguration, committed: appState.committedAPIConfiguration) {
                Label("Clave guardada", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            DisclosureGroup(isExpanded: $advancedProviderSettingsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    ProviderSettingsFields(
                        apiBaseURLInput: $apiDraft.baseURL,
                        transcriptionAPIURLInput: $apiDraft.transcriptionAPIURL,
                        transcriptionAPIKeyInput: $apiDraft.transcriptionAPIKey,
                        showsModelDescription: false
                    )
                }
            } label: {
                HStack {
                    Text("Proveedor avanzado")
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    advancedProviderSettingsExpanded.toggle()
                }
            }
            .padding(.top, 4)
        }
    }

    private func validateAndSaveKey() {
        guard !isValidatingKey else { return }
        let submission = apiDraft.submission
        isValidatingKey = true
        keyValidationError = nil
        successfulAPIConfiguration = nil

        Task { @MainActor in
            var accepted: ValidatedAPIConfiguration?
            let valid = await APIConfigurationSaveFlow.validateAndApply(
                apiKey: submission.configuration.apiKey,
                baseURL: submission.configuration.baseURL,
                transcriptionAPIURL: submission.configuration.transcriptionAPIURL,
                transcriptionAPIKey: submission.configuration.transcriptionAPIKey
            ) { configuration in
                if apiDraft.accept(configuration, for: submission) {
                    accepted = configuration
                }
                appState.updateAPIConfiguration(
                    apiKey: configuration.apiKey,
                    baseURL: configuration.baseURL,
                    transcriptionAPIURL: configuration.transcriptionAPIURL,
                    transcriptionAPIKey: configuration.transcriptionAPIKey
                )
            }
            guard apiDraft.isCurrent(submission) else { return }
            isValidatingKey = false
            if valid, let accepted, apiDraft.configuration == accepted,
               appState.committedAPIConfiguration == accepted {
                successfulAPIConfiguration = accepted
            } else if !valid && apiDraft.matches(submission) {
                keyValidationError = "No se ha podido validar. Revisa la clave y el proveedor."
            }
        }
    }

    // MARK: Output Language

    private static let outputLanguageOptions = [
        "",
        "English",
        "Chinese (Simplified)",
        "Chinese (Traditional)",
        "Spanish",
        "French",
        "Japanese",
        "Korean",
        "German",
        "Portuguese",
    ]

    private var connectedScreenEntries: [(name: String, tag: Int)] {
        _ = screensVersion
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            return (name: screen.localizedName, tag: Int(id))
        }
    }

    private var commandModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Activar modo edición", isOn: Binding(
                get: { appState.isCommandModeEnabled },
                set: { newValue in
                    _ = appState.setCommandModeEnabled(newValue)
                }
            ))

            Text("Selecciona texto y dicta una instrucción para transformarlo.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Cómo se activa", selection: Binding(
                get: { appState.commandModeStyle },
                set: { newValue in
                    _ = appState.setCommandModeStyle(newValue)
                }
            )) {
                ForEach(CommandModeStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!appState.isCommandModeEnabled)

            Group {
                switch appState.commandModeStyle {
                case .automatic:
                    Text("Si hay texto seleccionado, tu atajo normal lo transforma en vez de dictar encima.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .manual:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mantén la tecla extra junto con tu atajo para transformar la selección.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Tecla extra", selection: Binding(
                            get: { appState.commandModeManualModifier },
                            set: { newValue in
                                _ = appState.setCommandModeManualModifier(newValue)
                            }
                        )) {
                            ForEach(CommandModeManualModifier.allCases) { modifier in
                                Text(modifier.title).tag(modifier)
                            }
                        }
                        .disabled(!appState.isCommandModeEnabled || appState.commandModeStyle != .manual)
                    }
                }
            }
            .opacity(appState.isCommandModeEnabled ? 1 : 0.5)

            if let validationMessage = appState.commandModeManualModifierValidationMessage {
                Label(validationMessage, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: Sound Volume

    private var soundVolumeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Slider(value: $appState.soundVolume, in: 0...1, step: 0.1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("\(Int(appState.soundVolume * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .disabled(!appState.alertSoundsEnabled)
            .opacity(appState.alertSoundsEnabled ? 1 : 0.5)

            HStack(spacing: 8) {
                Button("Probar") {
                    let muted = SystemAudioStatus.isDefaultOutputMuted()
                    let volume = SystemAudioStatus.defaultOutputVolume()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMutedHint = muted || (volume ?? 1) < 0.10
                    }
                    appState.playAlertSound(named: "Tink")
                }
                .font(.caption)
                .disabled(!appState.alertSoundsEnabled)

                if showMutedHint {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.slash.fill")
                            .foregroundStyle(.orange)
                        Text("El volumen del sistema está silenciado o muy bajo.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .transition(.opacity)
                }
            }
        }
        .onChange(of: appState.alertSoundsEnabled) { enabled in
            if !enabled { showMutedHint = false }
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            permissionRow(
                title: "Micrófono",
                icon: "mic.fill",
                granted: micPermissionGranted,
                action: {
                    appState.requestMicrophoneAccess { granted in
                        micPermissionGranted = granted
                    }
                }
            )

            permissionRow(
                title: "Accesibilidad",
                icon: "hand.raised.fill",
                granted: appState.hasAccessibility,
                action: {
                    appState.openAccessibilitySettings()
                }
            )

            permissionRow(
                title: "Grabación de pantalla",
                icon: "camera.viewfinder",
                granted: appState.hasScreenRecordingPermission,
                action: {
                    appState.requestScreenCapturePermission()
                }
            )
        }
    }

    private func permissionRow(title: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.blue)
            Text(title)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Concedido")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Dar acceso") {
                    action()
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func checkMicPermission() {
        micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

}

// MARK: - Microphone Option Row

struct MicrophoneOptionRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prompts Settings

struct PromptsSettingsView: View {
    @EnvironmentObject var appState: AppState
    var showsHeader = true
    @State private var customSystemPromptInput: String = ""
    @State private var customContextPromptInput: String = ""
    @FocusState private var customSystemPromptFocused: Bool
    @FocusState private var customContextPromptFocused: Bool
    @State private var showDefaultSystemPrompt = false
    @State private var showDefaultContextPrompt = false

    // System prompt test state
    @State private var systemTestInput: String = "Um, so I was like, thinking we should uh, refactor the authentication module, you know?"
    @State private var systemTestRunning = false
    @State private var systemTestOutput: String? = nil
    @State private var systemTestError: String? = nil
    @State private var systemTestPrompt: String? = nil

    // Context prompt test state
    @State private var contextTestRunning = false
    @State private var contextTestOutput: String? = nil
    @State private var contextTestError: String? = nil
    @State private var contextTestPrompt: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if showsHeader {
                    PageHeader("Style", subtitle: "Control how your dictation is cleaned up and formatted.")
                }

                SettingsCard("Style Prompts", icon: "textformat") {
                    StylePromptsEditor()
                }
                SettingsCard("System Prompt", icon: "text.bubble.fill") {
                    systemPromptSection
                }
                SettingsCard("Instruction Guard", icon: "shield.lefthalf.filled") {
                    instructionGuardSection
                }
                SettingsCard("Screen Analysis", icon: "eye.fill") {
                    ScreenAnalysisToggle()
                }
                SettingsCard("Context Prompt", icon: "eye.fill") {
                    contextPromptSection
                }
            }
            .padding(24)
        }
        .onAppear {
            customSystemPromptInput = appState.customSystemPrompt.isEmpty
                ? PostProcessingService.defaultSystemPrompt
                : appState.customSystemPrompt
            customContextPromptInput = appState.customContextPrompt.isEmpty
                ? AppContextService.defaultContextPrompt
                : appState.customContextPrompt
        }
        .onDisappear {
            commitCustomSystemPrompt()
            commitCustomContextPrompt()
        }
    }

    private func commitCustomSystemPrompt() {
        let trimmed = customSystemPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTrimmed = PostProcessingService.defaultSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == defaultTrimmed || trimmed.isEmpty {
            if !appState.customSystemPrompt.isEmpty {
                appState.customSystemPrompt = ""
                appState.customSystemPromptLastModified = ""
            }
        } else if appState.customSystemPrompt != trimmed {
            appState.customSystemPrompt = trimmed
            appState.customSystemPromptLastModified = iso8601DayFormatter.string(from: Date())
        }
    }

    private func commitCustomContextPrompt() {
        let trimmed = customContextPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTrimmed = AppContextService.defaultContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == defaultTrimmed || trimmed.isEmpty {
            if !appState.customContextPrompt.isEmpty {
                appState.customContextPrompt = ""
                appState.customContextPromptLastModified = ""
            }
        } else if appState.customContextPrompt != trimmed {
            appState.customContextPrompt = trimmed
            appState.customContextPromptLastModified = iso8601DayFormatter.string(from: Date())
        }
    }

    // MARK: System Prompt

    private var systemPromptSection: some View {
        let isCustom = !appState.customSystemPrompt.isEmpty
        let hasNewerDefault = isCustom
            && !appState.customSystemPromptLastModified.isEmpty
            && appState.customSystemPromptLastModified < PostProcessingService.defaultSystemPromptDate

        return VStack(alignment: .leading, spacing: 10) {
            Text("Controls how raw transcriptions are cleaned up.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if hasNewerDefault {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                    Text("A newer default prompt is available.")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("View Default") {
                        showDefaultSystemPrompt.toggle()
                    }
                    .font(.caption)
                    Button("Switch to Default") {
                        customSystemPromptInput = PostProcessingService.defaultSystemPrompt
                        appState.customSystemPrompt = ""
                        appState.customSystemPromptLastModified = ""
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }

            if showDefaultSystemPrompt {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Default System Prompt")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("Hide") {
                            showDefaultSystemPrompt = false
                        }
                        .font(.caption)
                    }
                    Text(PostProcessingService.defaultSystemPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }

            TextEditor(text: $customSystemPromptInput)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 200)
                .focused($customSystemPromptFocused)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: customSystemPromptFocused) { focused in
                    if !focused { commitCustomSystemPrompt() }
                }

            HStack {
                if isCustom {
                    Label("Using custom prompt", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else {
                    Label("Using default", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCustom {
                    Button("Reset to Default") {
                        customSystemPromptInput = PostProcessingService.defaultSystemPrompt
                        appState.customSystemPrompt = ""
                        appState.customSystemPromptLastModified = ""
                    }
                    .font(.caption)
                }
            }

            Divider()

            // Test section
            VStack(alignment: .leading, spacing: 8) {
                Text("Test System Prompt")
                    .font(.caption.weight(.semibold))
                Text("Enter sample text to see how the current prompt cleans it up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $systemTestInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                Button {
                    runSystemPromptTest()
                } label: {
                    HStack(spacing: 6) {
                        if systemTestRunning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Running...")
                        } else {
                            Image(systemName: "play.fill")
                            Text("Test System Prompt")
                        }
                    }
                }
                .disabled(systemTestRunning || appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || systemTestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("API key required to test", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = systemTestError {
                    Label(error, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let output = systemTestOutput {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Result:")
                            .font(.caption.weight(.semibold))
                        Text(output.isEmpty ? "(empty — no output)" : output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.08))
                            .cornerRadius(6)
                    }
                }

                if let prompt = systemTestPrompt {
                    DisclosureGroup("Full prompt sent") {
                        Text(prompt)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var instructionGuardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Prevent dictated prompts from being executed",
                isOn: $appState.instructionExecutionGuardEnabled
            )
            .toggleStyle(.switch)

            Text("When enabled, FreeFlow retries or falls back to the literal transcript if post-processing looks like it answered the dictated text instead of cleaning it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func runSystemPromptTest() {
        commitCustomSystemPrompt()
        systemTestRunning = true
        systemTestOutput = nil
        systemTestError = nil
        systemTestPrompt = nil

        let service = PostProcessingService(
            apiKey: appState.apiKey,
            baseURL: appState.apiBaseURL,
            preferredModel: appState.postProcessingModel,
            preferredFallbackModel: appState.postProcessingFallbackModel,
            instructionExecutionGuardEnabled: appState.instructionExecutionGuardEnabled
        )
        let input = systemTestInput
        let customPrompt = appState.customSystemPrompt
        let vocabulary = appState.customVocabulary

        let context = AppContext(
            appName: "\(AppName.displayName) Settings",
            bundleIdentifier: "com.zachlatta.freeflow",
            windowTitle: "System Prompt Test",
            selectedText: nil,
            currentActivity: "User is testing the system prompt in \(AppName.displayName) settings.",
            contextSystemPrompt: nil,
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: nil
        )

        Task {
            do {
                let result = try await service.postProcess(
                    transcript: input,
                    context: context,
                    customVocabulary: vocabulary,
                    customSystemPrompt: customPrompt
                )
                await MainActor.run {
                    systemTestOutput = result.transcript
                    systemTestPrompt = result.prompt
                    systemTestRunning = false
                }
            } catch {
                await MainActor.run {
                    systemTestError = error.localizedDescription
                    systemTestRunning = false
                }
            }
        }
    }

    // MARK: Context Prompt

    private var contextPromptSection: some View {
        let isCustom = !appState.customContextPrompt.isEmpty
        let hasNewerDefault = isCustom
            && !appState.customContextPromptLastModified.isEmpty
            && appState.customContextPromptLastModified < AppContextService.defaultContextPromptDate

        return VStack(alignment: .leading, spacing: 10) {
            Text("Controls how \(AppName.displayName) infers your current activity from app metadata and screenshots.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if hasNewerDefault {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                    Text("A newer default prompt is available.")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("View Default") {
                        showDefaultContextPrompt.toggle()
                    }
                    .font(.caption)
                    Button("Switch to Default") {
                        customContextPromptInput = AppContextService.defaultContextPrompt
                        appState.customContextPrompt = ""
                        appState.customContextPromptLastModified = ""
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }

            if showDefaultContextPrompt {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Default Context Prompt")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("Hide") {
                            showDefaultContextPrompt = false
                        }
                        .font(.caption)
                    }
                    Text(AppContextService.defaultContextPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }

            TextEditor(text: $customContextPromptInput)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 200)
                .focused($customContextPromptFocused)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: customContextPromptFocused) { focused in
                    if !focused { commitCustomContextPrompt() }
                }

            HStack {
                if isCustom {
                    Label("Using custom prompt", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else {
                    Label("Using default", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCustom {
                    Button("Reset to Default") {
                        customContextPromptInput = AppContextService.defaultContextPrompt
                        appState.customContextPrompt = ""
                        appState.customContextPromptLastModified = ""
                    }
                    .font(.caption)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Screenshot Resolution")
                    .font(.caption.weight(.semibold))

                Text("Controls the maximum image dimension sent for context inference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $appState.contextScreenshotMaxDimension) {
                    ForEach(AppState.contextScreenshotDimensionOptions, id: \.self) { dimension in
                        Text("\(dimension) px").tag(dimension)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Screenshot Resolution")

                HStack {
                    if appState.contextScreenshotMaxDimension == AppState.defaultContextScreenshotMaxDimension {
                        Label("Using default", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Using custom value", systemImage: "pencil")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    if appState.contextScreenshotMaxDimension != AppState.defaultContextScreenshotMaxDimension {
                        Button("Reset to Default") {
                            appState.contextScreenshotMaxDimension = AppState.defaultContextScreenshotMaxDimension
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Allow full-desktop screenshot fallback", isOn: $appState.desktopScreenshotFallbackEnabled)
                Text("When active-window capture fails, FreeFlow can capture the full desktop, including other apps, and send it to your configured context provider. Turn this off to continue without a screenshot when active-window capture fails. Applies to new context captures.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Test section
            VStack(alignment: .leading, spacing: 8) {
                Text("Test Context Prompt")
                    .font(.caption.weight(.semibold))
                Text("Captures a screenshot and metadata from the frontmost app, then runs the context prompt to infer activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    runContextPromptTest()
                } label: {
                    HStack(spacing: 6) {
                        if contextTestRunning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Running...")
                        } else {
                            Image(systemName: "play.fill")
                            Text("Test Context Prompt")
                        }
                    }
                }
                .disabled(contextTestRunning || appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("API key required to test", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = contextTestError {
                    Label(error, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let output = contextTestOutput {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Result:")
                            .font(.caption.weight(.semibold))
                        Text(output.isEmpty ? "(empty — no output)" : output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.08))
                            .cornerRadius(6)
                    }
                }

                if let prompt = contextTestPrompt {
                    DisclosureGroup("Full prompt sent") {
                        Text(prompt)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func runContextPromptTest() {
        commitCustomContextPrompt()
        contextTestRunning = true
        contextTestOutput = nil
        contextTestError = nil
        contextTestPrompt = nil

        let service = appState.makeAppContextService()

        Task {
            let context = await service.collectContext()
            await MainActor.run {
                if let prompt = context.contextPrompt {
                    contextTestOutput = context.contextSummary
                    contextTestPrompt = prompt
                } else {
                    contextTestError = context.contextSummary
                    contextTestOutput = context.contextSummary
                }
                contextTestRunning = false
            }
        }
    }

}

// MARK: - Run Log Entry

struct RunLogEntryView: View {
    private let actionIconSize: CGFloat = 28
    let item: PipelineHistoryItem
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false
    @State private var isRetrying = false
    @State private var showContextPrompt = false
    @State private var showPostProcessingPrompt = false
    @State private var copiedTranscript = false
    @State private var copiedTranscriptResetWorkItem: DispatchWorkItem?
    @State private var copiedRawTranscript = false
    @State private var copiedRawTranscriptResetWorkItem: DispatchWorkItem?
    @State private var copiedCleanedTranscript = false
    @State private var copiedCleanedTranscriptResetWorkItem: DispatchWorkItem?

    private var isError: Bool {
        item.postProcessingStatus.hasPrefix("Error:")
    }

    private var copyableTranscript: String {
        if !item.postProcessedTranscript.isEmpty {
            return item.postProcessedTranscript
        }
        return item.rawTranscript
    }

    @ViewBuilder
    private func actionIconButton(
        systemName: String,
        color: Color = .secondary,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: actionIconSize, height: actionIconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: actionIconSize, height: actionIconSize)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        if isError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.timestamp.formatted(date: .numeric, time: .standard))
                                .font(.subheadline.weight(.semibold))
                            Text(item.postProcessedTranscript.isEmpty ? "(no transcript)" : item.postProcessedTranscript)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    if isError && item.audioFileName != nil {
                        Button {
                            appState.retryTranscription(item: item)
                        } label: {
                            if isRetrying {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: actionIconSize, height: actionIconSize)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .frame(width: actionIconSize, height: actionIconSize)
                                    .contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isRetrying)
                        .help("Retry transcription")
                    } else {
                        Color.clear
                            .frame(width: actionIconSize, height: actionIconSize)
                    }

                    actionIconButton(systemName: "square.and.arrow.up", help: "Export run log") {
                        TestCaseExporter.exportWithSavePanel(
                            item: item,
                            audioDirURL: AppState.audioStorageDirectory()
                        )
                    }

                    actionIconButton(
                        systemName: copiedTranscript ? "checkmark" : "doc.on.doc",
                        color: copiedTranscript ? .green : .secondary,
                        help: copiedTranscript ? "Copied transcript" : "Copy transcript",
                        disabled: copyableTranscript.isEmpty
                    ) {
                        copyTranscriptToPasteboard()
                    }

                    actionIconButton(systemName: "trash", help: "Delete this run") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.deleteHistoryEntry(id: item.id)
                        }
                    }
                }
            }
            .padding(12)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 16) {
                    // Audio player
                    if let audioFileName = item.audioFileName {
                        let audioURL = AppState.audioStorageDirectory().appendingPathComponent(audioFileName)
                        AudioPlayerView(audioURL: audioURL)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("No audio recorded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Custom vocabulary
                    if !item.customVocabulary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom Vocabulary")
                                .font(.caption.weight(.semibold))
                            FlowLayout(spacing: 4) {
                                ForEach(parseVocabulary(item.customVocabulary), id: \.self) { word in
                                    Text(word)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    // Pipeline steps
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pipeline")
                            .font(.caption.weight(.semibold))

                        // Step 1: Context Capture
                        PipelineStepView(
                            number: 1,
                            title: "Capture Context",
                            content: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let dataURL = item.contextScreenshotDataURL,
                                       let image = imageFromDataURL(dataURL) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxHeight: 120)
                                            .cornerRadius(4)
                                    }

                                    if let prompt = item.contextPrompt, !prompt.isEmpty {
                                        Button {
                                            showContextPrompt.toggle()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(showContextPrompt ? "Hide Prompt" : "Show Prompt")
                                                    .font(.caption)
                                                Image(systemName: showContextPrompt ? "chevron.up" : "chevron.down")
                                                    .font(.caption2)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Color.accentColor)

                                        if showContextPrompt {
                                            Text(prompt)
                                                .font(.system(.caption2, design: .monospaced))
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .cornerRadius(4)
                                        }
                                    }

                                    if !item.contextSummary.isEmpty {
                                        if ContextInferenceFailure.isFailureSummary(item.contextSummary) {
                                            Label("Context summary failed", systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.orange)
                                            Text(item.contextSummary)
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                                .textSelection(.enabled)
                                            Text("No usable activity summary. Dictation can continue.")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text(item.contextSummary)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                    } else {
                                        Text("No context captured")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        )

                        // Step 2: Transcribe Audio
                        PipelineStepView(
                            number: 2,
                            title: "Transcribe Audio",
                            content: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sent audio to the configured transcription model")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    if !item.rawTranscript.isEmpty {
                                        Text(item.rawTranscript)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .padding(8)
                                            .padding(.trailing, 24)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(nsColor: .controlBackgroundColor))
                                            .cornerRadius(4)
                                            .overlay(alignment: .topTrailing) {
                                                Button {
                                                    copyRawTranscriptToPasteboard()
                                                } label: {
                                                    Image(systemName: copiedRawTranscript ? "checkmark" : "doc.on.doc")
                                                        .font(.caption)
                                                        .foregroundStyle(copiedRawTranscript ? .green : .secondary)
                                                        .padding(6)
                                                        .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .help(copiedRawTranscript ? "Copied literal transcript" : "Copy literal transcript")
                                            }
                                    } else {
                                        Text("(empty transcript)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        )

                        // Step 3: Post-Process
                        PipelineStepView(
                            number: 3,
                            title: "Post-Process",
                            content: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.postProcessingStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)

                                    if let prompt = item.postProcessingPrompt, !prompt.isEmpty {
                                        Button {
                                            showPostProcessingPrompt.toggle()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(showPostProcessingPrompt ? "Hide Prompt" : "Show Prompt")
                                                    .font(.caption)
                                                Image(systemName: showPostProcessingPrompt ? "chevron.up" : "chevron.down")
                                                    .font(.caption2)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Color.accentColor)

                                        if showPostProcessingPrompt {
                                            Text(prompt)
                                                .font(.system(.caption2, design: .monospaced))
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .cornerRadius(4)
                                        }
                                    }

                                    if !item.postProcessedTranscript.isEmpty {
                                        Text(item.postProcessedTranscript)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .padding(8)
                                            .padding(.trailing, 24)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(nsColor: .controlBackgroundColor))
                                            .cornerRadius(4)
                                            .overlay(alignment: .topTrailing) {
                                                Button {
                                                    copyCleanedTranscriptToPasteboard()
                                                } label: {
                                                    Image(systemName: copiedCleanedTranscript ? "checkmark" : "doc.on.doc")
                                                        .font(.caption)
                                                        .foregroundStyle(copiedCleanedTranscript ? .green : .secondary)
                                                        .padding(6)
                                                        .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .help(copiedCleanedTranscript ? "Copied cleaned transcript" : "Copy cleaned transcript")
                                            }
                                    }
                                }
                            }
                        )
                    }

                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isError ? Color.red.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onReceive(appState.$retryingItemIDs) { ids in
            isRetrying = ids.contains(item.id)
        }
    }

    private func parseVocabulary(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func copyTranscriptToPasteboard() {
        guard !copyableTranscript.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyableTranscript, forType: .string)
        copiedTranscript = true

        copiedTranscriptResetWorkItem?.cancel()
        let resetWorkItem = DispatchWorkItem {
            copiedTranscript = false
            copiedTranscriptResetWorkItem = nil
        }
        copiedTranscriptResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }

    private func copyRawTranscriptToPasteboard() {
        guard !item.rawTranscript.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.rawTranscript, forType: .string)
        copiedRawTranscript = true

        copiedRawTranscriptResetWorkItem?.cancel()
        let resetWorkItem = DispatchWorkItem {
            copiedRawTranscript = false
            copiedRawTranscriptResetWorkItem = nil
        }
        copiedRawTranscriptResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }

    private func copyCleanedTranscriptToPasteboard() {
        guard !item.postProcessedTranscript.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.postProcessedTranscript, forType: .string)
        copiedCleanedTranscript = true

        copiedCleanedTranscriptResetWorkItem?.cancel()
        let resetWorkItem = DispatchWorkItem {
            copiedCleanedTranscript = false
            copiedCleanedTranscriptResetWorkItem = nil
        }
        copiedCleanedTranscriptResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }
}

// MARK: - Pipeline Step View

struct PipelineStepView<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Audio Player

class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.onFinish?()
        }
    }
}

struct AudioPlayerView: View {
    let audioURL: URL
    @State private var player: AVAudioPlayer?
    @State private var delegate = AudioPlayerDelegate()
    @State private var isPlaying = false
    @State private var duration: TimeInterval = 0
    @State private var elapsed: TimeInterval = 0
    @State private var progressTimer: Timer?

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(elapsed / duration, 1.0)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, geo.size.width * progress), height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 28)

            Text("\(formatDuration(elapsed)) / \(formatDuration(duration))")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .onAppear {
            loadDuration()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func loadDuration() {
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
        if let p = try? AVAudioPlayer(contentsOf: audioURL) {
            duration = p.duration
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
            do {
                let p = try AVAudioPlayer(contentsOf: audioURL)
                delegate.onFinish = {
                    self.stopPlayback()
                }
                p.delegate = delegate
                p.play()
                player = p
                isPlaying = true
                elapsed = 0
                startProgressTimer()
            } catch {}
        }
    }

    private func stopPlayback() {
        progressTimer?.invalidate()
        progressTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
        elapsed = 0
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if let p = player, p.isPlaying {
                elapsed = p.currentTime
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let pos = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Voice Macros Settings

struct VoiceMacrosSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddMacro = false
    @State private var editingMacro: VoiceMacro?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PageHeader(
                    "Snippets",
                    subtitle: "Say a short phrase and paste a predefined text instantly, skipping cleanup."
                ) {
                    Button("Add snippet") { showingAddMacro = true }
                        .buttonStyle(WisprPrimaryButtonStyle())
                }

                SettingsCard("Snippets", icon: "music.mic") {
                    macrosSection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingAddMacro, onDismiss: { editingMacro = nil }) {
            VoiceMacroEditorView(isPresented: $showingAddMacro, macro: $editingMacro)
        }
    }

    private var macrosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.voiceMacros.isEmpty {
                VStack {
                    Image(systemName: "music.mic")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 4)
                    Text("No snippets yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Click 'Add snippet' to create your first one.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(appState.voiceMacros.enumerated()), id: \.element.id) { index, macro in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(macro.command)
                                    .font(.headline)
                                Spacer()
                                Button("Edit") {
                                    editingMacro = macro
                                    showingAddMacro = true
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                
                                Button("Delete") {
                                    appState.voiceMacros.removeAll { $0.id == macro.id }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                            Text(macro.payload)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    }
                }
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            }
        }
    }
}

struct VoiceMacroEditorView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @Binding var macro: VoiceMacro?

    @State private var command: String = ""
    @State private var payload: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(macro == nil ? "Add Macro" : "Edit Macro")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Voice Command (What you say)")
                    .font(.caption.weight(.semibold))
                TextField("e.g. debugging prompt", text: $command)
                    .textFieldStyle(.roundedBorder)

                Text("Text (What gets pasted)")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 8)
                TextEditor(text: $payload)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                    macro = nil
                }
                Spacer()
                Button("Save") {
                    let newMacro = VoiceMacro(
                        id: macro?.id ?? UUID(),
                        command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                        payload: payload
                    )
                    
                    if let existingIndex = appState.voiceMacros.firstIndex(where: { $0.id == newMacro.id }) {
                        appState.voiceMacros[existingIndex] = newMacro
                    } else {
                        appState.voiceMacros.append(newMacro)
                    }
                    isPresented = false
                    macro = nil
                }
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || payload.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let m = macro {
                command = m.command
                payload = m.payload
            }
        }
    }
}


// MARK: - Style prompts and screen analysis

/// Un campo por estilo para cambiar la instrucción que se añade al prompt, con botón para restaurarla.
private struct StylePromptsEditor: View {
    @StateObject private var store = WritingStyleStore.shared
    @State private var drafts: [WritingStyle: String] = [:]

    private let editable: [WritingStyle] = [.casual, .veryCasual, .excited]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Instructions added to the cleanup prompt when a style other than Formal is selected. Formal adds nothing.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(editable) { style in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(style.title.trimmingCharacters(in: CharacterSet(charactersIn: ".!")).capitalized)
                            .font(.caption.weight(.semibold))
                        if !store.customInstruction(for: style).isEmpty {
                            Text("Customized").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore default") {
                            store.setCustomInstruction("", for: style)
                            drafts[style] = style.promptInstruction ?? ""
                        }
                        .font(.caption)
                        .disabled(store.customInstruction(for: style).isEmpty)
                    }
                    TextEditor(text: binding(for: style))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 110, maxHeight: 190)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }
            }
        }
        .onAppear {
            for style in editable {
                let custom = store.customInstruction(for: style)
                drafts[style] = custom.isEmpty ? (style.promptInstruction ?? "") : custom
            }
        }
    }

    private func binding(for style: WritingStyle) -> Binding<String> {
        Binding(
            get: { drafts[style] ?? "" },
            set: {
                drafts[style] = $0
                store.setCustomInstruction($0, for: style)
            }
        )
    }
}

private struct ScreenAnalysisToggle: View {
    @AppStorage(ScreenAnalysisPreference.storageKey) private var enabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Analyze the screen with AI on every dictation", isOn: $enabled)
            Text("Off by default: FreeFlow uses the app name and window title, which is instant and uses no tokens. On, it also sends a screenshot to the vision model to read names and context on screen. It costs time and Groq quota on every dictation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
