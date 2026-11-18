import Foundation

/// Decide si FreeFlow se queda en el Dock cuando no hay ninguna ventana abierta.
enum DockIconPreference {
    static let storageKey = "hide_dock_icon_when_closed"
    /// Por defecto se oculta, como hasta ahora: FreeFlow vive en la barra de menús.
    static let defaultHidden = true

    static func load(from defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: storageKey) as? Bool) ?? defaultHidden
    }

    /// Con alguna ventana abierta siempre se ve en el Dock; sin ventanas, según el ajuste.
    static func showsInDock(hasOpenWindow: Bool, hideWhenClosed: Bool) -> Bool {
        hasOpenWindow || !hideWhenClosed
    }
}
