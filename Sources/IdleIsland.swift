import SwiftUI
import AppKit

/// Mini-isla en reposo: una barrita en el borde de la pantalla que, al pasar el ratón, se
/// convierte en un botón de micrófono con la etiqueta "Dictate <atajo>". Se puede arrastrar
/// a uno de tres sitios: abajo en el centro, o a media altura en el borde izquierdo o derecho.
enum IdleIslandPreference {
    static let storageKey = "show_idle_island"

    static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: storageKey) as? Bool) ?? true
    }
}

enum IslandAnchor: String, CaseIterable {
    case bottom
    case left
    case right

    static let storageKey = "island_anchor"

    static var current: IslandAnchor {
        get { IslandAnchor(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .bottom }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    var isVertical: Bool { self != .bottom }
}

/// Capa que oscurece la pantalla mientras se arrastra la isla y marca los tres huecos donde encaja.
struct IslandDropTargetsView: View {
    let screenSize: CGSize
    let highlighted: IslandAnchor?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            slot(.bottom)
                .frame(width: 90, height: 62)
                .position(x: screenSize.width / 2, y: screenSize.height - 40)
            slot(.left)
                .frame(width: 58, height: 84)
                .position(x: 36, y: screenSize.height / 2)
            slot(.right)
                .frame(width: 58, height: 84)
                .position(x: screenSize.width - 36, y: screenSize.height / 2)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.12), value: highlighted)
    }

    private func slot(_ anchor: IslandAnchor) -> some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(highlighted == anchor ? 0.95 : 0.75))
            .scaleEffect(highlighted == anchor ? 1.06 : 1)
    }
}
