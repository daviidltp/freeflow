import SwiftUI
import AppKit
import CoreText

// MARK: - Palette

/// Paleta de la interfaz (tonos "sand" para claro y "vast" para oscuro) y de la isla flotante.
enum WisprPalette {
    static let sand50 = Color(hex: 0xFCFCFB)
    static let sand100 = Color(hex: 0xFAF9F7)
    static let sand300 = Color(hex: 0xF7F6F2)
    static let sand500 = Color(hex: 0xF5F4F0)
    static let sand600 = Color(hex: 0xEEEBE3)
    static let sand700 = Color(hex: 0xC5C0B3)
    static let sand800 = Color(hex: 0xA39D8E)
    static let sand900 = Color(hex: 0x736E62)
    static let sand950 = Color(hex: 0x4D4A42)

    static let vast50 = Color(hex: 0xE9E8E1)
    static let vast300 = Color(hex: 0xB3B2AD)
    static let vast500 = Color(hex: 0x878683)
    static let vast700 = Color(hex: 0x5B5B59)
    static let vast900 = Color(hex: 0x30302F)
    static let vast910 = Color(hex: 0x2A2A29)
    static let vast925 = Color(hex: 0x202020)
    static let vast950 = Color(hex: 0x1A1A1A)

    static let lumen = Color(hex: 0xFFFFEB)
    static let red = Color(hex: 0xFF5757)
    static let green = Color(hex: 0x10B981)
    static let yellow = Color(hex: 0xEAB308)

    /// Fondo general de la ventana.
    static let background = dynamic(light: 0xFCFCFB, dark: 0x1A1A1A)
    /// Fondo de la barra lateral y de las tarjetas secundarias.
    static let backgroundSecondary = dynamic(light: 0xF5F4F0, dark: 0x202020)
    /// Fondo de controles y filas con relieve.
    static let backgroundTertiary = dynamic(light: 0xEEEBE3, dark: 0x2A2A29)
    static let foreground = dynamic(light: 0x1A1A1A, dark: 0xE9E8E1)
    static let mutedForeground = dynamic(light: 0x736E62, dark: 0x9D9C98)
    static let border = dynamic(light: 0xEEEBE3, dark: 0x30302F)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x202020)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Fonts

enum WisprFonts {
    private static var registered = false

    /// Registra Figtree y EB Garamond (incluidas en Resources/Fonts) para usarlas por nombre.
    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func figtree(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Figtree", size: size).weight(weight)
    }

    /// Serif de los títulos grandes ("Welcome back", etc.).
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("EB Garamond", size: size).weight(weight)
    }
}

// MARK: - Sounds

/// Sonidos de dictado empaquetados en Resources/Sounds (inicio, fin y pegado).
enum WisprSound {
    case start
    case stop
    case paste

    private var fileName: String {
        switch self {
        case .start: return "dictation-start"
        case .stop: return "dictation-stop"
        case .paste: return "paste"
        }
    }

    private static var cache: [String: NSSound] = [:]

    func play(volume: Float) {
        let key = fileName
        let sound: NSSound?
        if let cached = Self.cache[key] {
            sound = cached
        } else if let url = Bundle.main.url(forResource: key, withExtension: "wav", subdirectory: "Sounds") {
            sound = NSSound(contentsOf: url, byReference: true)
            Self.cache[key] = sound
        } else {
            sound = nil
        }
        guard let sound else { return }
        sound.stop()
        sound.volume = volume
        sound.play()
    }

    /// Los nombres de sistema que usaba la app antes se redirigen a los sonidos propios.
    static func replacement(forLegacyName name: String) -> WisprSound? {
        switch name {
        case "Tink": return .start
        case "Pop": return .stop
        default: return nil
        }
    }
}
