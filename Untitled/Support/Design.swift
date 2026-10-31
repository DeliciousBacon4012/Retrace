import SwiftUI

/// Shared spacing, corner radii, and motion, so every screen lines up and moves the same way.
enum Design {
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 14
    static let radiusL: CGFloat = 20
}

extension Animation {
    /// Direct feedback such as selection and toggles: quick and settled, no overshoot.
    static let response = Animation.snappy(duration: 0.28)
    /// Panels and cards arriving: a soft spring with a little give.
    static let panel = Animation.smooth(duration: 0.42, extraBounce: 0.08)
    /// Something the user just made, like a new mark: a lively pop.
    static let pop = Animation.bouncy(duration: 0.38, extraBounce: 0.12)
}

/// Small uppercase labels that head each group, for a quiet technical look.
struct SectionLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A keyboard shortcut drawn as a small monospaced key cap.
struct ShortcutChip: View {
    let shortcut: Shortcut

    var body: some View {
        Text(shortcut.displayString)
            .font(.system(.caption, design: .monospaced).weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 5))
            .accessibilityLabel(Text("Shortcut \(shortcut.displayString)"))
    }
}

/// A faint wash of the accent color behind content, so glass in front of it has
/// something to refract. It stays dim in both light and dark mode.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 0.22 : 0.12
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.6, 0.4], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                .accentColor.opacity(strength), .clear, .purple.opacity(strength * 0.6),
                .clear, .clear, .clear,
                .cyan.opacity(strength * 0.5), .clear, .accentColor.opacity(strength * 0.5),
            ]
        )
        .background(.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
