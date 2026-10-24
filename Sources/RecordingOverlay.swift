import SwiftUI
import AppKit

// MARK: - State

final class RecordingOverlayState: ObservableObject {
    @Published var phase: OverlayPhase = .idle
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
    @Published var idleHover = false
    @Published var isDragging = false
    @Published var anchor: IslandAnchor = .bottom
    /// Tamaño de la forma negra/gris dentro del panel; el panel se anima hacia el mismo tamaño.
    @Published var shapeSize = CGSize(width: 38, height: 6)
    @Published var shortcutLabel = "fn"
}

enum OverlayPhase {
    /// Barrita en reposo (sin dictado en curso).
    case idle
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

// MARK: - Manager

/// Un único panel persistente: la barrita en reposo es el mismo elemento que se expande
/// a botón de dictado al pasar el ratón y a chip con la onda cuando hablas.
final class RecordingOverlayManager {
    private var panel: NSPanel?
    private let overlayState = RecordingOverlayState()
    private var lockedOverlayWidth: CGFloat?
    private var dropTargetsPanel: NSPanel?
    private var dropHighlight: IslandAnchor?
    private var screenObserver: NSObjectProtocol?

    var onStopButtonPressed: (() -> Void)?
    var onCancelButtonPressed: (() -> Void)?
    var onUpdateOverlayPressed: (() -> Void)?
    var onIdleDictatePressed: (() -> Void)?
    var idleShortcutLabel: () -> String = { "fn" } {
        didSet { overlayState.shortcutLabel = idleShortcutLabel() }
    }

    /// The screen the island should appear on. The user picks one of
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

    private var isActive: Bool { overlayState.phase != .idle }

    /// El panel solo captura el ratón cuando hay algo que pulsar; mientras dictas en modo
    /// "mantener" deja pasar los clics.
    private var panelAcceptsMouse: Bool {
        switch overlayState.phase {
        case .idle, .updateAvailable: return true
        case .recording: return overlayState.recordingTriggerMode == .toggle
        default: return false
        }
    }

    // MARK: Public API

    func showInitializing(mode: RecordingTriggerMode = .hold, isCommandMode: Bool = false) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.overlayState.recordingStartedAt = nil
            self.overlayState.phase = .initializing
            self.resetLevels()
            self.showOverlayPanel(animated: true)
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
            self.showOverlayPanel(animated: true)
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
            self.applyLayout(animated: true)
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
            self.applyLayout(animated: animated)
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
            self.lockedOverlayWidth = self.panel?.frame.width ?? self.overlayWidth
            self.overlayState.phase = .transcribing
            self.showOverlayPanel(animated: true)
        }
    }

    func showFailureIndicator() {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.phase = .feedback
            self.showOverlayPanel(animated: true)
        }
    }

    /// Maximum length of an in-pill error message. Anything longer is
    /// truncated with an ellipsis to keep the pill from stretching across
    /// the screen; the full text remains available in `os_log` for
    /// forensic review.
    private static let maxToastMessageLength = 90

    /// Surface a transient error in the island. The pill resizes to
    /// fit the message (subject to the truncation cap), holds for a few
    /// seconds, then goes back to the idle bar.
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
            self.showOverlayPanel(animated: true)
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
            self.showOverlayPanel(animated: true)
        }
    }

    func dismiss() {
        DispatchQueue.main.async {
            self.dismissAll()
        }
    }

    /// Muestra u oculta la barrita en reposo según el ajuste. No toca un dictado en curso.
    func refreshIdleIsland() {
        DispatchQueue.main.async {
            guard !self.isActive else { return }
            if IdleIslandPreference.isEnabled {
                self.showOverlayPanel(animated: false)
            } else {
                self.closePanel(animated: false)
            }
        }
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 52, height: 20),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        overlayState.shortcutLabel = idleShortcutLabel()
        let root = WisprIslandView(
            state: overlayState,
            onStopButtonPressed: { [weak self] in self?.onStopButtonPressed?() },
            onCancelButtonPressed: { [weak self] in self?.onCancelButtonPressed?() },
            onUpdateOverlayPressed: { [weak self] in self?.onUpdateOverlayPressed?() },
            onIdlePress: { [weak self] in self?.onIdleDictatePressed?() },
            onHoverChange: { [weak self] hovering in self?.setIdleHover(hovering) },
            onDragChanged: { [weak self] in self?.idleDragChanged() },
            onDragEnded: { [weak self] in self?.idleDragEnded() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.applyLayout(animated: false) }
        }
        return panel
    }

    private func showOverlayPanel(animated: Bool) {
        if panel == nil {
            let created = makePanel()
            panel = created
            applyLayout(animated: false)
            created.alphaValue = 0
            created.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                created.animator().alphaValue = 1
            }
        } else {
            applyLayout(animated: animated)
            panel?.alphaValue = 1
            panel?.orderFrontRegardless()
        }
    }

    private func closePanel(animated: Bool) {
        hideDropTargets()
        guard let closing = panel else { return }
        panel = nil
        overlayState.idleHover = false
        overlayState.isDragging = false
        let finish = {
            // orderOut alone leaves the panel retained in NSApp.windows with its
            // SwiftUI hierarchy mounted — repeatForever animations keep flushing
            // Core Animation forever. Unmount and close so the panel deallocates.
            closing.orderOut(nil)
            closing.contentView = nil
            closing.close()
        }
        guard animated else { finish(); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            closing.animator().alphaValue = 0
        }, completionHandler: finish)
    }

    private func dismissAll() {
        lockedOverlayWidth = nil
        overlayState.recordingStartedAt = nil
        overlayState.isCommandMode = false
        overlayState.updateVersion = ""
        overlayState.phase = .idle
        overlayState.idleHover = false
        if IdleIslandPreference.isEnabled {
            applyLayout(animated: true)
        } else {
            closePanel(animated: true)
        }
    }

    // MARK: Layout

    private struct Layout {
        let frame: NSRect
        let shape: CGSize
    }

    private func layout(on screen: NSScreen) -> Layout {
        let anchor = IslandAnchor.current
        let visible = screen.visibleFrame
        let size: CGSize
        let shape: CGSize
        var edgeInset: CGFloat = 3

        switch overlayState.phase {
        case .idle:
            if overlayState.isDragging {
                size = CGSize(width: 56, height: 40)
                shape = CGSize(width: 44, height: 28)
            } else if overlayState.idleHover {
                size = CGSize(width: 150, height: 90)
                shape = CGSize(width: 48, height: 28)
            } else if anchor.isVertical {
                size = CGSize(width: 20, height: 52)
                shape = CGSize(width: 6, height: 38)
            } else {
                size = CGSize(width: 52, height: 20)
                shape = CGSize(width: 38, height: 6)
            }
        default:
            size = CGSize(width: overlayWidth, height: overlayHeight)
            shape = size
            edgeInset = WisprIsland.bottomMargin
        }

        if overlayState.phase == .idle && overlayState.isDragging {
            let mouse = NSEvent.mouseLocation
            return Layout(frame: NSRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height), shape: shape)
        }

        let origin: NSPoint
        switch anchor {
        case .bottom:
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: visible.minY + edgeInset)
        case .left:
            origin = NSPoint(x: visible.minX + edgeInset, y: visible.midY - size.height / 2)
        case .right:
            origin = NSPoint(x: visible.maxX - size.width - edgeInset, y: visible.midY - size.height / 2)
        }
        return Layout(frame: NSRect(origin: origin, size: size), shape: shape)
    }

    private func applyLayout(animated: Bool) {
        guard let panel, let screen = targetScreen else { return }
        let target = layout(on: screen)
        overlayState.anchor = IslandAnchor.current
        overlayState.shapeSize = target.shape
        panel.ignoresMouseEvents = !panelAcceptsMouse

        guard animated, !overlayState.isDragging else {
            panel.setFrame(target.frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            panel.animator().setFrame(target.frame, display: true)
        }
    }

    private var overlayHeight: CGFloat {
        let showsButtons = overlayState.phase == .recording && overlayState.recordingTriggerMode == .toggle
        return showsButtons ? 40 : 34
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
        case .idle, .initializing, .recording, .transcribing:
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

    // MARK: Hover and drag (idle bar)

    private func setIdleHover(_ hovering: Bool) {
        guard overlayState.phase == .idle, !overlayState.isDragging, overlayState.idleHover != hovering else { return }
        overlayState.idleHover = hovering
        applyLayout(animated: true)
    }

    private func nearestAnchor(to point: NSPoint, on screen: NSScreen) -> IslandAnchor {
        let visible = screen.visibleFrame
        let targets: [(IslandAnchor, NSPoint)] = [
            (.bottom, NSPoint(x: screen.frame.midX, y: visible.minY + 30)),
            (.left, NSPoint(x: visible.minX + 30, y: visible.midY)),
            (.right, NSPoint(x: visible.maxX - 30, y: visible.midY)),
        ]
        return targets.min { hypot($0.1.x - point.x, $0.1.y - point.y) < hypot($1.1.x - point.x, $1.1.y - point.y) }?.0 ?? .bottom
    }

    private func idleDragChanged() {
        guard overlayState.phase == .idle, let screen = targetScreen else { return }
        if !overlayState.isDragging {
            overlayState.isDragging = true
            overlayState.idleHover = false
            showDropTargets(on: screen)
        }
        applyLayout(animated: false)
        let highlight = nearestAnchor(to: NSEvent.mouseLocation, on: screen)
        if highlight != dropHighlight {
            dropHighlight = highlight
            updateDropTargets(on: screen)
        }
    }

    private func idleDragEnded() {
        guard overlayState.isDragging, let screen = targetScreen else { return }
        IslandAnchor.current = nearestAnchor(to: NSEvent.mouseLocation, on: screen)
        overlayState.isDragging = false
        hideDropTargets()
        applyLayout(animated: true)
    }

    private func showDropTargets(on screen: NSScreen) {
        let created = dropTargetsPanel ?? NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.backgroundColor = .clear
        created.isOpaque = false
        created.hasShadow = false
        created.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        created.ignoresMouseEvents = true
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.isReleasedWhenClosed = false
        created.setFrame(screen.frame, display: true)
        dropTargetsPanel = created
        updateDropTargets(on: screen)
        created.alphaValue = 0
        created.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            created.animator().alphaValue = 1
        }
    }

    private func updateDropTargets(on screen: NSScreen) {
        guard let dropTargetsPanel else { return }
        let view = IslandDropTargetsView(screenSize: screen.frame.size, highlighted: dropHighlight)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
        dropTargetsPanel.contentView = hosting
    }

    private func hideDropTargets() {
        dropHighlight = nil
        guard let closing = dropTargetsPanel else { return }
        dropTargetsPanel = nil
        closing.orderOut(nil)
        closing.contentView = nil
        closing.close()
    }
}

// MARK: - Island View

struct WisprIslandView: View {
    @ObservedObject var state: RecordingOverlayState
    let onStopButtonPressed: () -> Void
    let onCancelButtonPressed: () -> Void
    let onUpdateOverlayPressed: () -> Void
    let onIdlePress: () -> Void
    let onHoverChange: (Bool) -> Void
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void

    private let spring = Animation.spring(response: 0.3, dampingFraction: 0.82)

    private var isIdle: Bool { state.phase == .idle }

    private var showsButtons: Bool {
        state.phase == .recording && state.recordingTriggerMode == .toggle
    }

    /// Dónde se ancla la forma dentro del panel: pegada al borde en hover, centrada en el resto.
    private var containerAlignment: Alignment {
        guard isIdle, state.idleHover else { return .center }
        switch state.anchor {
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private var isCollapsedBar: Bool { isIdle && !state.idleHover && !state.isDragging }

    var body: some View {
        ZStack(alignment: containerAlignment) {
            Color.clear
            shape
                .frame(width: state.shapeSize.width, height: state.shapeSize.height)
                .overlay(alignment: .top) {
                    if isIdle && state.idleHover && !state.isDragging {
                        tooltip
                            .offset(y: -38)
                            .transition(.opacity)
                    }
                }
        }
        .contentShape(Rectangle())
        .onHover { onHoverChange($0) }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in if isIdle { onDragChanged() } }
                .onEnded { _ in if isIdle { onDragEnded() } }
        )
        .animation(spring, value: state.shapeSize)
        .animation(.easeInOut(duration: 0.2), value: state.phase)
        .animation(.easeInOut(duration: 0.2), value: state.idleHover)
    }

    private var shape: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(isCollapsedBar ? WisprPalette.vast910 : (isIdle && state.idleHover ? WisprPalette.vast925 : Color.black))
            Capsule(style: .continuous)
                .strokeBorder(isCollapsedBar || (isIdle && state.idleHover) ? WisprPalette.vast700.opacity(0.7) : WisprIsland.border, lineWidth: 1)
            content
                .padding(.horizontal, showsButtons ? 5 : (isIdle ? 0 : 20))
                .transition(.opacity)
        }
    }

    private var tooltip: some View {
        HStack(spacing: 4) {
            Text("Dictate")
            Text(state.shortcutLabel).fontWeight(.bold)
        }
        .font(WisprFonts.figtree(13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .fixedSize()
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(WisprIsland.border, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            if state.isDragging {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else if state.idleHover {
                Button(action: onIdlePress) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start dictation")
            } else {
                Color.clear
            }
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

