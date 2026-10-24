import SwiftUI
import AppKit

/// Mini-isla en reposo: una barrita abajo en el centro que, al pasar el ratón, se
/// convierte en un botón de micrófono con la etiqueta "Dictate <atajo>".
enum IdleIslandPreference {
    static let storageKey = "show_idle_island"

    static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: storageKey) as? Bool) ?? true
    }
}

struct IdleIslandView: View {
    let shortcutLabel: String
    let isHovering: Bool
    let onHoverChange: (Bool) -> Void
    let onPress: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if isHovering {
                HStack(spacing: 4) {
                    Text("Dictate")
                    Text(shortcutLabel).fontWeight(.bold)
                }
                .font(WisprFonts.figtree(13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(Color.black))
                .overlay(Capsule().strokeBorder(WisprIsland.border, lineWidth: 1))
                .transition(.opacity)
            }
            Button(action: onPress) {
                ZStack {
                    Capsule().fill(isHovering ? WisprPalette.vast925 : WisprPalette.vast910)
                    Capsule().strokeBorder(WisprPalette.vast700.opacity(0.7), lineWidth: 1)
                    if isHovering {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: isHovering ? 48 : 38, height: isHovering ? 28 : 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start dictation")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { onHoverChange($0) }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isHovering)
    }
}
