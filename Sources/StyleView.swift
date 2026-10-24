import SwiftUI
import AppKit

/// Pantalla Style: un estilo de escritura por tipo de app, más los prompts avanzados.
struct StyleView: View {
    private enum Page: Hashable {
        case group(StyleGroup)
        case advanced
    }

    @StateObject private var store = WritingStyleStore.shared
    @State private var page: Page = .group(.personal)

    private var pages: [Page] { StyleGroup.allCases.map { .group($0) } + [.advanced] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader("Style")
                tabBar
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)

            switch page {
            case .group(let group):
                ScrollView {
                    StyleGroupPage(group: group, store: store)
                        .padding(.horizontal, 40)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                }
            case .advanced:
                PromptsSettingsView(showsHeader: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func title(for page: Page) -> String {
        switch page {
        case .group(let group): return group.title
        case .advanced: return "Advanced"
        }
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 26) {
                ForEach(pages, id: \.self) { option in
                    Button {
                        page = option
                    } label: {
                        VStack(spacing: 10) {
                            Text(title(for: option))
                                .font(WisprFonts.figtree(15, weight: page == option ? .semibold : .medium))
                                .foregroundStyle(page == option ? WisprPalette.foreground : WisprPalette.mutedForeground)
                            Rectangle()
                                .fill(page == option ? WisprPalette.foreground : Color.clear)
                                .frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Rectangle().fill(WisprPalette.border).frame(height: 1)
        }
    }
}

// MARK: - Page for one group

private struct StyleGroupPage: View {
    let group: StyleGroup
    @ObservedObject var store: WritingStyleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StyleBanner(group: group, store: store)
            HStack(alignment: .top, spacing: 20) {
                ForEach(group.availableStyles) { style in
                    StyleCard(
                        group: group,
                        style: style,
                        isSelected: store.style(for: group) == style
                    ) {
                        store.setStyle(style, for: group)
                    }
                }
            }
        }
    }
}

// MARK: - Banner

private struct StyleBanner: View {
    let group: StyleGroup
    @ObservedObject var store: WritingStyleStore

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(group.bannerTitle)
                    .font(WisprFonts.serif(30))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The style is applied to the app you are dictating into. Apps are recognized by their identifier, not by a screenshot.")
                    .font(WisprFonts.figtree(14))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            AppIconsRow(group: group, store: store)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
        .background(banner)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var banner: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x3E4A56), Color(hex: 0x15110F), Color(hex: 0x4A3A2D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(hex: 0x4A6E8C).opacity(0.75), .clear],
                center: .init(x: 0.18, y: 0.1),
                startRadius: 0,
                endRadius: 300
            )
            RadialGradient(
                colors: [Color(hex: 0xA39A8A).opacity(0.55), .clear],
                center: .init(x: 0.62, y: 0.95),
                startRadius: 0,
                endRadius: 240
            )
            RadialGradient(
                colors: [Color(hex: 0x6B7A63).opacity(0.65), .clear],
                center: .init(x: 1, y: 0.1),
                startRadius: 0,
                endRadius: 260
            )
        }
    }
}

/// Iconos reales de las apps del grupo, solapados, con un "+" para añadir otra.
private struct AppIconsRow: View {
    let group: StyleGroup
    @ObservedObject var store: WritingStyleStore

    private var icons: [(bundleIdentifier: String, image: NSImage)] {
        store.bundleIdentifiers(for: group).compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return (id, NSWorkspace.shared.icon(forFile: url.path))
        }
    }

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(icons.prefix(5)), id: \.bundleIdentifier) { item in
                Image(nsImage: item.image)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(.white.opacity(0.14)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    .help("Click to remove from \(group.title)")
                    .onTapGesture { store.remove(bundleIdentifier: item.bundleIdentifier, from: group) }
            }
            Button(action: addApp) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(.white.opacity(0.18)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Add an app to \(group.title)")
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        store.add(bundleIdentifier: id, to: group)
    }
}

// MARK: - Style card

private struct StyleCard: View {
    let group: StyleGroup
    let style: WritingStyle
    let isSelected: Bool
    let onSelect: () -> Void

    private static let accent = Color(hex: 0x9B6BB5)
    /// Fondo de la burbuja de ejemplo: lavanda clara en modo claro, gris oscuro en modo oscuro.
    private static let bubbleColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0x2A2A29) : NSColor(hex: 0xF8F4FD)
    })

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                Text(style.title)
                    .font(WisprFonts.figtree(16, weight: .medium))
                    .foregroundStyle(WisprPalette.foreground)
                Text(style.summary)
                    .font(WisprFonts.figtree(16))
                    .foregroundStyle(WisprPalette.foreground)
                    .padding(.top, 6)
                preview
                    .padding(.top, 28)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(WisprPalette.background))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Self.accent : WisprPalette.border, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var avatarColor: Color {
        switch style {
        case .formal: return Color(hex: 0xEBD8FB)
        case .casual: return Color(hex: 0xF5BDEB)
        case .veryCasual: return Color(hex: 0x7A2038)
        case .excited: return Color(hex: 0x6B37A0)
        }
    }

    @ViewBuilder
    private var preview: some View {
        let text = Self.sample(group: group, style: style)
        switch group {
        case .personal:
            ZStack(alignment: .bottomTrailing) {
                Text(text)
                    .font(WisprFonts.figtree(15))
                    .foregroundStyle(WisprPalette.foreground)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.bubbleColor))
                avatar(circle: true)
                    .offset(y: 38)
            }
            .padding(.bottom, 38)
        case .work:
            VStack(alignment: .leading, spacing: 10) {
                avatar(circle: false)
                HStack(spacing: 6) {
                    Text("John Doe").font(WisprFonts.figtree(14, weight: .medium))
                    Text("9:45am").font(WisprFonts.figtree(14)).foregroundStyle(WisprPalette.mutedForeground)
                }
                Text(text)
                    .font(WisprFonts.figtree(15))
                    .foregroundStyle(WisprPalette.foreground)
            }
        case .email, .other:
            VStack(alignment: .leading, spacing: 18) {
                Rectangle().fill(WisprPalette.border).frame(height: 1)
                Text(text)
                    .font(WisprFonts.figtree(15))
                    .foregroundStyle(WisprPalette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func avatar(circle: Bool) -> some View {
        Text("J")
            .font(WisprFonts.figtree(20, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: circle ? 22 : 4, style: .continuous).fill(avatarColor)
            )
    }

    /// Texto de muestra que enseña qué cambia cada estilo.
    static func sample(group: StyleGroup, style: WritingStyle) -> String {
        switch group {
        case .personal:
            switch style {
            case .formal: return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
            case .casual: return "Hey are you free for lunch tomorrow? Let's do 12 if that works for you"
            default: return "hey are you free for lunch tomorrow? let's do 12 if that works for you"
            }
        case .work:
            switch style {
            case .formal: return "Hey, if you're free, let's chat about the great results."
            case .casual: return "Hey, if you're free let's chat about the great results"
            default: return "Hey, if you're free, let's chat about the great results!"
            }
        case .email:
            switch style {
            case .formal: return "Hi Alex,\n\nThanks for the update. I will review the proposal and send my comments tomorrow.\n\nBest regards."
            case .casual: return "Hi Alex,\n\nThanks for the update. I will review the proposal and send my comments tomorrow\n\nBest"
            default: return "Hi Alex,\n\nThanks for the update! I will review the proposal and send my comments tomorrow!\n\nBest"
            }
        case .other:
            switch style {
            case .formal: return "So far, I am enjoying the new workout routine.\n\nI am excited for tomorrow's workout, especially after a full night of rest."
            case .casual: return "So far I am enjoying the new workout routine.\n\nI am excited for tomorrow's workout especially after a full night of rest."
            default: return "So far, I am enjoying the new workout routine.\n\nI am excited for tomorrow's workout, especially after a full night of rest!"
            }
        }
    }
}
