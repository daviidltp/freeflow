import SwiftUI
import AppKit

// MARK: - State

final class RecordingOverlayState: ObservableObject {
    @Published var phase: OverlayPhase = .recording
    @Published var recordingStartedAt: ContinuousClock.Instant?
    @Published var showsRecordingTimer = RecordingTimerPreference.defaultEnabled
    @Published var audioLevel: Float = 0.0
    /// Últimos niveles de audio, para dibujar la onda desplazándose como en Wispr.
    @Published var levelHistory: [Float] = Array(repeating: 0, count: WisprIsland.barCount)
    @Published var recordingTriggerMode: RecordingTriggerMode = .hold
    @Published var isCommandMode = false
    @Published var updateVersion: String = ""
    @Published var errorMessage: String?
    @Published var toastID: UUID?
}

enum OverlayPhase {
    case initializing
    case recording
    case transcribing
    case feedback
    case updateAvailable
}

// MARK: - NSScreen Helpers

extension NSScreen {
    /// CoreGraphics display identifier for this screen, or nil if the
    /// device description is missing the key (vanishingly rare). Stable
    /// across screen-arrangement changes for as long as the display is
    /// connected, which is what the overlay picker stores in UserDefaults.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

// MARK: - Island metrics

/// Medidas de la isla flotante: pill negro, borde fino gris oscuro, barras blancas de 2 pt.
enum WisprIsland {
    static let barCount = 22
    static let barWidth: CGFloat = 2
    static let barSpacing: CGFloat = 2
    static let maxBarHeight: CGFloat = 20
    static let minBarHeight: CGFloat = 2
    static let bottomMargin: CGFloat = 10
    static let buttonSize: CGFloat = 30
    static let border = WisprPalette.vast900
}

// MARK: - Panel Helpers

private func makeOverlayPanel(width: CGFloat, height: CGFloat) -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.level = .screenSaver
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    return panel
}

// MARK: - Manager

final class RecordingOverlayManager {
    private var overlayWindow: NSPanel?
    private let overlayState = RecordingOverlayState()
    private var lockedOverlayWidth: CGFloat?

    var onStopButtonPressed: (() -> Void)?
    var onCancelButtonPressed: (() -> Void)?
    var onUpdateOverlayPressed: (() -> Void)?

    /// The screen the overlay should appear on. The user picks one of
    /// three modes in Settings, stored in UserDefaults under
    /// `overlay_display_id`:
    ///
    /// - `0` (default) — Active window: follows focus across monitors via
    ///   NSScreen.main.
    /// - `-1` — Primary display: always NSScreen.screens.first.
    /// - any positive integer — specific NSScreen displayID. Falls back to
    ///   primary if that display is unplugged.
    private var targetScreen: NSScreen? {
        let savedID = UserDefaults.standard.integer(forKey: "overlay_display_id")
        switch savedID {
        case 0:
            return NSScreen.main ?? NSScreen.screens.first
        case -1:
            return NSScreen.screens.first ?? NSScreen.main
        default:
            if let match = NSScreen.screens.first(where: { Int($0.displayID ?? 0) == savedID }) {
                return match
            }
            return NSScreen.screens.first ?? NSScreen.main
        }
    }

    private var overlayAcceptsMouseEvents: Bool {
        (overlayState.phase == .recording && overlayState.recordingTriggerMode == .toggle)
            || overlayState.phase == .updateAvailable
    }

    func showInitializing(mode: RecordingTriggerMode = .hold, isCommandMode: Bool = false) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.overlayState.recordingStartedAt = nil
            self.overlayState.phase = .initializing
            self.resetLevels()
            self.showOverlayPanel(animatedResize: false)
        }
    }

    func showRecording(
        mode: RecordingTriggerMode = .hold,
        isCommandMode: Bool = false,
        startedAt: ContinuousClock.Instant = .now,
        showsRecordingTimer: Bool
    ) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.beginRecordingTimer(startedAt: startedAt, showsRecordingTimer: showsRecordingTimer)
            self.overlayState.phase = .recording
            self.resetLevels()
            self.showOverlayPanel(animatedResize: true)
        }
    }

    func transitionToRecording(
        mode: RecordingTriggerMode = .hold,
        isCommandMode: Bool = false,
        startedAt: ContinuousClock.Instant = .now,
        showsRecordingTimer: Bool
    ) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.beginRecordingTimer(startedAt: startedAt, showsRecordingTimer: showsRecordingTimer)
            self.overlayState.phase = .recording
            self.updateOverlayLayout(animated: true)
        }
    }

    private func beginRecordingTimer(startedAt: ContinuousClock.Instant, showsRecordingTimer: Bool) {
        overlayState.showsRecordingTimer = showsRecordingTimer
        overlayState.recordingStartedAt = startedAt
    }

    private func resetLevels() {
        overlayState.audioLevel = 0
        overlayState.levelHistory = Array(repeating: 0, count: WisprIsland.barCount)
    }

    func setRecordingTriggerMode(_ mode: RecordingTriggerMode, animated: Bool) {
        DispatchQueue.main.async {
            self.overlayState.recordingTriggerMode = mode
            self.updateOverlayLayout(animated: animated)
        }
    }

    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.overlayState.audioLevel = level
            var history = self.overlayState.levelHistory
            history.append(level)
            if history.count > WisprIsland.barCount {
                history.removeFirst(history.count - WisprIsland.barCount)
            }
            self.overlayState.levelHistory = history
        }
    }

    func showTranscribing() {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = self.overlayWindow?.frame.width ?? self.overlayWidth
            self.overlayState.phase = .transcribing
            self.showOverlayPanel(animatedResize: true)
        }
    }

    func showFailureIndicator() {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.phase = .feedback
            self.showOverlayPanel(animatedResize: true)
        }
    }

    /// Maximum length of an in-pill error message. Anything longer is
    /// truncated with an ellipsis to keep the pill from stretching across
    /// the screen; the full text remains available in `os_log` for
    /// forensic review.
    private static let maxToastMessageLength = 90

    /// Surface a transient error in the island. The pill resizes to
    /// fit the message (subject to the truncation cap), holds for a few
    /// seconds, then dismisses.
    func showError(_ message: String) {
        let truncated: String = {
            if message.count <= Self.maxToastMessageLength { return message }
            let cutoff = message.index(message.startIndex, offsetBy: Self.maxToastMessageLength - 1)
            return String(message[..<cutoff]) + "…"
        }()
        DispatchQueue.main.async { [self] in
            let toastID = UUID()
            self.overlayState.errorMessage = truncated
            self.overlayState.toastID = toastID
            self.lockedOverlayWidth = nil
            self.overlayState.phase = .feedback
            self.showOverlayPanel(animatedResize: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                guard let self else { return }
                guard self.overlayState.phase == .feedback,
                      self.overlayState.errorMessage == truncated,
                      self.overlayState.toastID == toastID else {
                    return
                }
                self.overlayState.errorMessage = nil
                self.overlayState.toastID = nil
                self.dismissAll()
            }
        }
    }

    func showUpdateAvailable(version: String) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.isCommandMode = false
            self.overlayState.updateVersion = version
            self.overlayState.phase = .updateAvailable
            self.showOverlayPanel(animatedResize: true)
        }
    }

    func dismiss() {
        DispatchQueue.main.async {
            self.dismissAll()
        }
    }

    private func showOverlayPanel(animatedResize: Bool) {
        let frame = overlayFrame

        if let panel = overlayWindow {
            panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
            panel.contentView = makeOverlayContent(frame: frame)
            resize(panel: panel, to: frame, animated: animatedResize)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        let panel = makeOverlayPanel(width: frame.width, height: frame.height)
        panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
        panel.contentView = makeOverlayContent(frame: frame)

        // Aparece desde unos puntos más abajo, con fundido.
        var startFrame = frame
        startFrame.origin.y -= 8
        panel.setFrame(startFrame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }

        overlayWindow = panel
    }

    private func updateOverlayLayout(animated: Bool) {
        guard let panel = overlayWindow else { return }
        let frame = overlayFrame
        panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
        panel.contentView = makeOverlayContent(frame: frame)
        resize(panel: panel, to: frame, animated: animated)
    }

    private func makeOverlayContent(frame: NSRect) -> NSView {
        let root = WisprIslandView(
            state: overlayState,
            onStopButtonPressed: { [weak self] in self?.onStopButtonPressed?() },
            onCancelButtonPressed: { [weak self] in self?.onCancelButtonPressed?() },
            onUpdateOverlayPressed: { [weak self] in self?.onUpdateOverlayPressed?() }
        )
        .frame(width: frame.width, height: frame.height)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        hosting.autoresizingMask = [.width, .height]
        return hosting
    }

    private func resize(panel: NSPanel, to frame: NSRect, animated: Bool) {
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private var overlayHeight: CGFloat {
        let showsButtons = overlayState.phase == .recording && overlayState.recordingTriggerMode == .toggle
        return showsButtons ? 40 : 34
    }

    private var overlayFrame: NSRect {
        guard let screen = targetScreen else { return .zero }
        let width = overlayWidth
        let height = overlayHeight
        let x = screen.frame.midX - width / 2
        let y = screen.visibleFrame.minY + WisprIsland.bottomMargin
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private var overlayWidth: CGFloat {
        if let lockedOverlayWidth, overlayState.phase == .transcribing {
            return lockedOverlayWidth
        }

        switch overlayState.phase {
        case .feedback:
            guard let msg = overlayState.errorMessage, !msg.isEmpty else { return 64 }
            // ~6.8 pt por carácter más 56 pt de icono y márgenes, entre 180 y 460 pt.
            return min(460, max(180, CGFloat(msg.count) * 6.8 + 56))
        case .updateAvailable:
            return 168
        case .initializing, .recording, .transcribing:
            var width: CGFloat = 20 * 2 + CGFloat(WisprIsland.barCount) * (WisprIsland.barWidth + WisprIsland.barSpacing) - WisprIsland.barSpacing
            if overlayState.phase == .recording {
                if overlayState.recordingTriggerMode == .toggle {
                    width += (WisprIsland.buttonSize + 8) * 2 - 16
                }
                if overlayState.showsRecordingTimer { width += 40 }
                if overlayState.isCommandMode { width += 22 }
            }
            return width
        }
    }

    private func dismissAll() {
        lockedOverlayWidth = nil
        overlayState.recordingStartedAt = nil
        overlayState.isCommandMode = false
        overlayState.updateVersion = ""
        guard let panel = overlayWindow else { return }
        overlayWindow = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: {
            // orderOut alone leaves the panel retained in NSApp.windows with its
            // SwiftUI hierarchy mounted — repeatForever animations keep flushing
            // Core Animation forever. Unmount and close so the panel deallocates.
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        })
    }
}

// MARK: - Island View

struct WisprIslandView: View {
    @ObservedObject var state: RecordingOverlayState
    let onStopButtonPressed: () -> Void
    let onCancelButtonPressed: () -> Void
    let onUpdateOverlayPressed: () -> Void

    private var showsButtons: Bool {
        state.phase == .recording && state.recordingTriggerMode == .toggle
    }

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.black)
            Capsule(style: .continuous)
                .strokeBorder(WisprIsland.border, lineWidth: 1)

            content
                .padding(.horizontal, showsButtons ? 5 : 20)
        }
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.phase)
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.recordingTriggerMode)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .feedback:
            if let message = state.errorMessage {
                IslandErrorView(message: message)
            } else {
                IslandFailureIcon()
            }
        case .updateAvailable:
            IslandUpdateView(onPress: onUpdateOverlayPressed)
        case .initializing:
            IslandDotsView()
        case .transcribing:
            IslandProcessingView()
        case .recording:
            HStack(spacing: 8) {
                if showsButtons {
                    IslandCircleButton(systemName: "xmark", action: onCancelButtonPressed)
                        .accessibilityLabel("Cancel dictation")
                }
                if state.isCommandMode {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                if state.showsRecordingTimer, let start = state.recordingStartedAt {
                    IslandElapsedTimeView(start: start)
                }
                IslandWaveformView(levels: state.levelHistory)
                    .frame(maxWidth: .infinity)
                if showsButtons {
                    IslandCircleButton(systemName: "stop.fill", action: onStopButtonPressed)
                        .accessibilityLabel("Stop dictation")
                }
            }
        }
    }
}

/// Botón circular de 30 pt con borde gris oscuro de la isla en modo manos libres.
private struct IslandCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: systemName == "stop.fill" ? 9 : 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: WisprIsland.buttonSize, height: WisprIsland.buttonSize)
                .background(Circle().fill(Color.black))
                .overlay(Circle().strokeBorder(WisprIsland.border, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Waveform

/// Barras blancas de 2 pt que se desplazan con el historial reciente del micrófono.
struct IslandWaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: WisprIsland.barSpacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.white.opacity(0.4 + 0.6 * edgeFade(index)))
                    .frame(width: WisprIsland.barWidth, height: height(for: level))
            }
        }
        .frame(height: WisprIsland.maxBarHeight)
        .animation(.easeOut(duration: 0.09), value: levels)
    }

    private func height(for level: Float) -> CGFloat {
        let amplitude = CGFloat(min(max(level, 0), 1))
        return WisprIsland.minBarHeight + (WisprIsland.maxBarHeight - WisprIsland.minBarHeight) * amplitude
    }

    /// Las barras de los extremos se atenúan un poco.
    private func edgeFade(_ index: Int) -> Double {
        let center = Double(levels.count - 1) / 2
        guard center > 0 else { return 1 }
        return 1 - pow(abs(Double(index) - center) / center, 2) * 0.8
    }
}

/// Tres puntos de carga mientras arranca el micrófono.
struct IslandDotsView: View {
    @State private var activeDot = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(activeDot == index ? 0.95 : 0.3))
                    .frame(width: 4, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: activeDot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                DispatchQueue.main.async { activeDot = (activeDot + 1) % 3 }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

/// Mientras se transcribe: barras bajas con una ola de brillo que las recorre.
struct IslandProcessingView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: WisprIsland.barSpacing) {
                ForEach(0..<WisprIsland.barCount, id: \.self) { index in
                    let wave = 0.5 + 0.5 * sin(time * 5.0 - Double(index) * 0.45)
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.white.opacity(0.25 + 0.65 * wave))
                        .frame(width: WisprIsland.barWidth, height: 3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct IslandElapsedTimeView: View {
    let start: ContinuousClock.Instant

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let seconds = max(0, start.duration(to: .now).components.seconds)
            Text(String(format: "%lld:%02lld", seconds / 60, seconds % 60))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize()
                .accessibilityLabel("Recording duration")
                .accessibilityValue("\(seconds / 60) minutes, \(seconds % 60) seconds")
        }
    }
}

private struct IslandFailureIcon: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(WisprPalette.red))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Aviso de error dentro de la isla: icono rojo y mensaje.
private struct IslandErrorView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WisprPalette.red)
            Text(message)
                .font(WisprFonts.figtree(12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct IslandUpdateView: View {
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Update Available")
                    .font(WisprFonts.figtree(12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Waveform (prueba de micrófono en Setup)

struct WaveformBar: View {
    let amplitude: CGFloat

    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 22

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 3, height: minHeight + (maxHeight - minHeight) * amplitude)
    }
}

struct WaveformView: View {
    let audioLevel: Float
    var showsActivityPulse = false

    private static let barCount = 9
    private static let multipliers: [CGFloat] = [0.35, 0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.35]
    private static let centerIndex = CGFloat((barCount - 1) / 2)

    var body: some View {
        Group {
            if showsActivityPulse {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    waveformBars(pulseTime: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                waveformBars(pulseTime: nil)
            }
        }
        .frame(height: 24)
    }

    private func waveformBars(pulseTime: TimeInterval?) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                WaveformBar(amplitude: barAmplitude(for: index, pulseTime: pulseTime))
                    .animation(
                        .spring(
                            response: barResponse(for: index),
                            dampingFraction: 0.88
                        )
                        .delay(barDelay(for: index)),
                        value: audioLevel
                    )
            }
        }
    }

    private func barAmplitude(for index: Int, pulseTime: TimeInterval?) -> CGFloat {
        let level = CGFloat(max(audioLevel, 0))
        let baseAmplitude = min(level * Self.multipliers[index], 1.0)

        guard let pulseTime else { return baseAmplitude }

        let travelingWave = CGFloat(0.5 + 0.5 * sin((pulseTime * 6.2) - Double(index) * 0.78))
        let shimmer = CGFloat(0.5 + 0.5 * sin((pulseTime * 3.1) + Double(index) * 0.5))
        let pulse = travelingWave * 0.22 + shimmer * 0.06

        let saturationRelief = baseAmplitude * (0.74 + pulse)
        let quietPulse = (1.0 - baseAmplitude) * (0.04 + pulse * 0.28)
        return min(saturationRelief + quietPulse, 1.0)
    }

    private func barResponse(for index: Int) -> Double {
        let distance = abs(CGFloat(index) - Self.centerIndex)
        let normalizedDistance = distance / Self.centerIndex
        return 0.18 + Double(normalizedDistance) * 0.06
    }

    private func barDelay(for index: Int) -> Double {
        let distance = abs(CGFloat(index) - Self.centerIndex)
        return Double(distance) * 0.01
    }
}

