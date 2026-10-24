import Foundation

enum WritingStyleTests {
    static func run() {
        let suite = "WritingStyleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WritingStyleStore(defaults: defaults)

        // Clasificación por identificador de bundle
        TestSupport.expectEqual(store.group(appName: "WhatsApp", bundleIdentifier: "net.whatsapp.WhatsApp"), .personal)
        TestSupport.expectEqual(store.group(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap"), .work)
        TestSupport.expectEqual(store.group(appName: "Mail", bundleIdentifier: "com.apple.mail"), .email)
        TestSupport.expectEqual(store.group(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"), .other)

        // En un navegador manda el título de la pestaña
        TestSupport.expectEqual(
            store.group(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", windowTitle: "Inbox (3) - Gmail"),
            .email
        )
        TestSupport.expectEqual(
            store.group(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitle: "WhatsApp Web"),
            .personal
        )
        TestSupport.expectEqual(
            store.group(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitle: "Apple"),
            .other
        )

        // Formal no cambia nada; los demás añaden instrucción
        TestSupport.expect(store.instruction(appName: "Mail", bundleIdentifier: "com.apple.mail", windowTitle: nil) == nil,
                           "Formal no debe añadir instrucción")
        store.setStyle(.veryCasual, for: .personal)
        let personal = store.instruction(appName: "WhatsApp", bundleIdentifier: "net.whatsapp.WhatsApp", windowTitle: nil)
        TestSupport.expect(personal?.contains("lowercase") == true, "very casual debe pedir minúsculas")
        TestSupport.expectEqual(store.style(for: .personal), .veryCasual)

        // Un estilo que el grupo no ofrece cae a Formal
        store.setStyle(.excited, for: .personal)
        TestSupport.expectEqual(store.style(for: .personal), .formal)

        // Apps añadidas a mano se mueven de un grupo a otro
        store.add(bundleIdentifier: "com.example.chat", to: .work)
        TestSupport.expectEqual(store.group(appName: "Chat", bundleIdentifier: "com.example.chat"), .work)
        store.add(bundleIdentifier: "com.example.chat", to: .personal)
        TestSupport.expectEqual(store.group(appName: "Chat", bundleIdentifier: "com.example.chat"), .personal)
        TestSupport.expect(!store.bundleIdentifiers(for: .work).contains("com.example.chat"), "Debe salir del grupo anterior")

        // Quitar una app de serie la manda a Other
        store.remove(bundleIdentifier: "net.whatsapp.WhatsApp", from: .personal)
        TestSupport.expectEqual(store.group(appName: "WhatsApp", bundleIdentifier: "net.whatsapp.WhatsApp"), .other)
    
        // El prompt de estilo se declara como prioritario y trae ejemplos
        let veryCasual = WritingStylePrompt.instruction(for: .veryCasual, group: .personal) ?? ""
        TestSupport.expect(veryCasual.hasPrefix("STYLE OVERRIDE"), "El estilo debe presentarse como prioritario")
        TestSupport.expect(veryCasual.contains("Examples:") && veryCasual.contains("never write the opening Spanish marks"),
                           "Very casual debe traer ejemplos y quitar ¿ ¡")
        TestSupport.expect(WritingStylePrompt.instruction(for: .formal, group: .email) == nil, "Formal no añade nada")
    
        // Instrucción editable
        store.setStyle(.casual, for: .work)
        store.setCustomInstruction("Siempre termina con 'jeje'.", for: .casual)
        let custom = store.instruction(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", windowTitle: nil)
        TestSupport.expect(custom?.contains("jeje") == true, "Debe usar el texto propio")
        store.setCustomInstruction("", for: .casual)
        let restored = store.instruction(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", windowTitle: nil)
        TestSupport.expect(restored?.contains("jeje") == false, "Vacío vuelve al texto de serie")
        store.setCustomInstruction(WritingStyle.casual.promptInstruction ?? "", for: .casual)
        TestSupport.expectEqual(store.customInstruction(for: .casual), "")
    }
}
