import Foundation

/// Tipos de app en los que se elige un estilo de escritura distinto.
enum StyleGroup: String, CaseIterable, Identifiable {
    case personal
    case work
    case email
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "Personal messages"
        case .work: return "Work messages"
        case .email: return "Email"
        case .other: return "Other"
        }
    }

    var bannerTitle: String {
        switch self {
        case .personal: return "This style applies in personal messengers"
        case .work: return "This style applies in workplace messengers"
        case .email: return "This style applies in email"
        case .other: return "This style applies in all other apps"
        }
    }

    /// Estilos que se ofrecen en cada tipo de app, en el orden de las tarjetas.
    var availableStyles: [WritingStyle] {
        switch self {
        case .personal: return [.formal, .casual, .veryCasual]
        case .work, .email, .other: return [.formal, .casual, .excited]
        }
    }

    /// Apps que se reconocen sin que el usuario haga nada (identificador de bundle).
    var builtInBundleIdentifiers: [String] {
        switch self {
        case .personal:
            return [
                "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.hnc.Discord",
                "com.apple.MobileSMS", "org.whispersystems.signal-desktop", "com.facebook.archon",
            ]
        case .work:
            return [
                "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams",
                "us.zoom.xos", "com.linear", "com.google.Chrome.app.chat",
            ]
        case .email:
            return [
                "com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac",
                "com.superhuman.electron", "it.bloop.airmail3", "com.freron.MailMate",
            ]
        case .other:
            return []
        }
    }
}

/// Un estilo de escritura: qué hace con mayúsculas, puntuación y tono.
enum WritingStyle: String, CaseIterable, Identifiable {
    case formal
    case casual
    case veryCasual
    case excited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formal: return "Formal."
        case .casual: return "Casual"
        case .veryCasual: return "very casual"
        case .excited: return "Excited!"
        }
    }

    var summary: String {
        switch self {
        case .formal: return "Caps + Punctuation"
        case .casual: return "Caps + Less punctuation"
        case .veryCasual: return "No Caps + Less punctuation"
        case .excited: return "More exclamations"
        }
    }

    /// Instrucción que se añade al prompt de limpieza. Formal es el comportamiento base y no añade nada.
    /// Lleva ejemplos porque los modelos siguen los ejemplos antes que las reglas sueltas.
    var promptInstruction: String? {
        switch self {
        case .formal:
            return nil
        case .casual:
            return """
- Capitalize the first word of each sentence and proper nouns as usual.
- Do not put a period at the end of the message, nor at the end of a line or list item.
- Keep commas exactly where normal writing would put them.
- Always keep accents and diacritics (á, é, í, ó, ú, ñ, ü), including on question words like "qué", "cómo" and "cuándo".
- Keep question marks and exclamation marks at the end of a sentence, but never write the opening Spanish marks ¿ and ¡.
- These rules apply to every line, including list items.
Examples:
"Hey, are you free for lunch tomorrow? Let's do 12 if that works for you." -> "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you"
"Hola, ¿qué tal? Te escribo luego." -> "Hola, qué tal? Te escribo luego"
"""
        case .veryCasual:
            return """
- Write everything in lowercase: the first word of every sentence, of every line and of every list item, and the pronoun "I". Keep capitals only in vocabulary terms, acronyms and brand names.
- Do not put a period at the end of the message, nor at the end of a line or list item.
- Keep commas exactly where normal writing would put them.
- Always keep accents and diacritics (á, é, í, ó, ú, ñ, ü), including on question words like "qué", "cómo" and "cuándo".
- Keep question marks and exclamation marks at the end of a sentence, but never write the opening Spanish marks ¿ and ¡.
- These rules apply to every line, including list items and the line that introduces a list.
Examples:
"Hey, are you free for lunch tomorrow? Let's do 12 if that works for you." -> "hey, are you free for lunch tomorrow? let's do 12 if that works for you"
"Hola, ¿qué tal? Te escribo luego." -> "hola, qué tal? te escribo luego"
"¿Cómo estás? Estoy en casa, ¿vienes?" -> "cómo estás? estoy en casa, vienes?"
"Lista de la compra: plátanos, aceite, agua." -> "lista de la compra: plátanos, aceite, agua"
"""
        case .excited:
            return """
- Keep normal capitalization and punctuation.
- End sentences that express enthusiasm, thanks, congratulations or good news with an exclamation mark instead of a period.
- Use exclamation marks naturally, not on every sentence, and never add emoji.
Examples:
"Hey, if you're free, let's chat about the great results." -> "Hey, if you're free, let's chat about the great results!"
"Gracias por la ayuda, me ha encantado." -> "¡Gracias por la ayuda, me ha encantado!"
"""
        }
    }
}

/// Bloque del prompt con el estilo elegido. Se añade al final del prompt de limpieza.
enum WritingStylePrompt {
    static func instruction(for style: WritingStyle, group: StyleGroup, body customBody: String? = nil) -> String? {
        guard let defaultBody = style.promptInstruction else { return nil }
        let trimmed = customBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = trimmed.isEmpty ? defaultBody : trimmed
        let name = style.title.trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        return """
STYLE OVERRIDE (highest priority). The user chose the "\(name)" writing style for this destination (\(group.title)). It replaces every earlier rule about capitalization, sentence punctuation and final periods, including "fix punctuation, capitalization" and "use normal sentence punctuation". Follow it exactly:
\(body)
The style changes only capitalization, the final period and the opening ¿ ¡ marks. Never add, remove or reword content, never change accents, and keep the spelling of vocabulary terms, commands and file paths.
"""
    }
}

/// Clasifica la app donde se dicta y guarda la elección del usuario.
final class WritingStyleStore: ObservableObject {
    static let shared = WritingStyleStore()

    private let defaults: UserDefaults
    private static let styleKeyPrefix = "writing_style_"
    private static let extraAppsKeyPrefix = "writing_style_apps_"
    private static let removedAppsKeyPrefix = "writing_style_removed_apps_"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Estilo por tipo de app

    func style(for group: StyleGroup) -> WritingStyle {
        guard let raw = defaults.string(forKey: Self.styleKeyPrefix + group.rawValue),
              let style = WritingStyle(rawValue: raw),
              group.availableStyles.contains(style) else {
            return .formal
        }
        return style
    }

    func setStyle(_ style: WritingStyle, for group: StyleGroup) {
        objectWillChange.send()
        defaults.set(style.rawValue, forKey: Self.styleKeyPrefix + group.rawValue)
    }

    // MARK: Instrucciones editables

    private static let promptKeyPrefix = "writing_style_prompt_"

    /// Texto propio del usuario para este estilo; vacío si usa el de serie.
    func customInstruction(for style: WritingStyle) -> String {
        defaults.string(forKey: Self.promptKeyPrefix + style.rawValue) ?? ""
    }

    func setCustomInstruction(_ text: String, for style: WritingStyle) {
        objectWillChange.send()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == style.promptInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) {
            defaults.removeObject(forKey: Self.promptKeyPrefix + style.rawValue)
        } else {
            defaults.set(trimmed, forKey: Self.promptKeyPrefix + style.rawValue)
        }
    }

    // MARK: Apps de cada tipo

    /// Apps añadidas a mano a este tipo.
    func extraBundleIdentifiers(for group: StyleGroup) -> [String] {
        defaults.stringArray(forKey: Self.extraAppsKeyPrefix + group.rawValue) ?? []
    }

    private func removedBundleIdentifiers(for group: StyleGroup) -> Set<String> {
        Set(defaults.stringArray(forKey: Self.removedAppsKeyPrefix + group.rawValue) ?? [])
    }

    /// Apps que se muestran en el banner: las reconocidas de serie (menos las quitadas) y las añadidas.
    func bundleIdentifiers(for group: StyleGroup) -> [String] {
        let removed = removedBundleIdentifiers(for: group)
        let builtIn = group.builtInBundleIdentifiers.filter { !removed.contains($0) }
        return builtIn + extraBundleIdentifiers(for: group).filter { !builtIn.contains($0) }
    }

    /// Mueve una app a este tipo (y la quita de los demás).
    func add(bundleIdentifier: String, to group: StyleGroup) {
        objectWillChange.send()
        for other in StyleGroup.allCases where other != group {
            remove(bundleIdentifier: bundleIdentifier, from: other, notify: false)
        }
        var removed = removedBundleIdentifiers(for: group)
        removed.remove(bundleIdentifier)
        defaults.set(Array(removed), forKey: Self.removedAppsKeyPrefix + group.rawValue)
        var extras = extraBundleIdentifiers(for: group)
        if !extras.contains(bundleIdentifier) && !group.builtInBundleIdentifiers.contains(bundleIdentifier) {
            extras.append(bundleIdentifier)
        }
        defaults.set(extras, forKey: Self.extraAppsKeyPrefix + group.rawValue)
    }

    func remove(bundleIdentifier: String, from group: StyleGroup) {
        remove(bundleIdentifier: bundleIdentifier, from: group, notify: true)
    }

    private func remove(bundleIdentifier: String, from group: StyleGroup, notify: Bool) {
        if notify { objectWillChange.send() }
        var extras = extraBundleIdentifiers(for: group)
        extras.removeAll { $0 == bundleIdentifier }
        defaults.set(extras, forKey: Self.extraAppsKeyPrefix + group.rawValue)
        if group.builtInBundleIdentifiers.contains(bundleIdentifier) {
            var removed = removedBundleIdentifiers(for: group)
            removed.insert(bundleIdentifier)
            defaults.set(Array(removed), forKey: Self.removedAppsKeyPrefix + group.rawValue)
        }
    }

    // MARK: Clasificación

    private static let browserBundleKeys = [
        "safari", "chrome", "firefox", "arc", "brave", "edge", "opera", "vivaldi", "company.thebrowser.dia", "comet",
    ]

    /// En un navegador la app no dice nada, pero el título de la pestaña sí.
    private static let webTitleRules: [(group: StyleGroup, keys: [String])] = [
        (.email, ["gmail", "outlook", "proton mail", "yahoo mail", "icloud mail", "fastmail", "hey.com"]),
        (.work, ["slack", "microsoft teams", "linkedin", "google chat", "linear"]),
        (.personal, ["whatsapp", "telegram", "discord", "messenger", "instagram", "signal", "imessage"]),
    ]

    func group(appName: String?, bundleIdentifier: String?, windowTitle: String? = nil) -> StyleGroup {
        if let bundleIdentifier {
            // Lo que el usuario ha elegido a mano manda sobre todo lo demás.
            for group in StyleGroup.allCases where extraBundleIdentifiers(for: group).contains(bundleIdentifier) {
                return group
            }
            for group in StyleGroup.allCases
            where group.builtInBundleIdentifiers.contains(bundleIdentifier)
                && !removedBundleIdentifiers(for: group).contains(bundleIdentifier) {
                return group
            }
            // Una app que el usuario ha quitado de su grupo no vuelve por el respaldo por nombre.
            if StyleGroup.allCases.contains(where: { removedBundleIdentifiers(for: $0).contains(bundleIdentifier) }) {
                return .other
            }
        }

        let lowerBundle = (bundleIdentifier ?? "").lowercased()
        let lowerName = (appName ?? "").lowercased()
        let isBrowser = Self.browserBundleKeys.contains { lowerBundle.contains($0) || lowerName.contains($0) }
        if isBrowser, let title = windowTitle?.lowercased() {
            for rule in Self.webTitleRules where rule.keys.contains(where: { title.contains($0) }) {
                return rule.group
            }
        }

        // Respaldo por nombre para apps que no están en la lista de identificadores.
        let haystack = lowerBundle + " " + lowerName
        func matches(_ keys: [String]) -> Bool { keys.contains { haystack.contains($0) } }
        if matches(["whatsapp", "telegram", "discord", "imessage", "mobilesms", "signal"]) { return .personal }
        if matches(["slack", "teams", "zoom"]) { return .work }
        if matches(["outlook", "airmail", "superhuman", "mimestream", "spark", "mailmate", "com.apple.mail"]) { return .email }
        return .other
    }

    /// Instrucción de estilo para el dictado en esta app, o `nil` si no cambia nada (estilo Formal).
    func instruction(appName: String?, bundleIdentifier: String?, windowTitle: String?) -> String? {
        let group = group(appName: appName, bundleIdentifier: bundleIdentifier, windowTitle: windowTitle)
        let chosen = style(for: group)
        return WritingStylePrompt.instruction(for: chosen, group: group, body: customInstruction(for: chosen))
    }
}
