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

/// A soft purple and blue glow that drifts slowly behind content, like lava-lamp bubbles,
/// so glass in front of it has something to refract. It holds still when Reduce Motion is on
/// and stays dim enough to read text over in light and dark mode.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// About 30 frames a second is plenty for something this slow, and saves power.
    private static let frameInterval = 1.0 / 30

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 4, height: 4, points: points(at: time), colors: colors(at: time), smoothsColors: true)
        }
        .background(.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Edge points stay on the edges so the gradient always fills the view; the four inner
    /// points wander on slow, out-of-step loops.
    private func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func wobble(_ base: Float, _ speed: Double, _ phase: Double, _ amount: Float) -> Float {
            base + Float(sin(time * speed + phase)) * amount
        }
        return [
            [0, 0], [wobble(0.33, 0.11, 0, 0.08), 0], [wobble(0.66, 0.09, 1, 0.08), 0], [1, 0],
            [0, wobble(0.33, 0.1, 2, 0.08)], [wobble(0.33, 0.13, 0.5, 0.14), wobble(0.33, 0.17, 1.4, 0.12)],
            [wobble(0.66, 0.15, 2.2, 0.13), wobble(0.36, 0.12, 0.3, 0.14)], [1, wobble(0.33, 0.08, 3, 0.08)],
            [0, wobble(0.66, 0.12, 4, 0.08)], [wobble(0.36, 0.14, 3.1, 0.13), wobble(0.66, 0.11, 2.6, 0.12)],
            [wobble(0.66, 0.1, 1.8, 0.14), wobble(0.66, 0.16, 4.2, 0.13)], [1, wobble(0.66, 0.1, 5, 0.08)],
            [0, 1], [wobble(0.33, 0.12, 5.5, 0.08), 1], [wobble(0.66, 0.1, 0.7, 0.08), 1], [1, 1],
        ]
    }

    private func colors(at time: TimeInterval) -> [Color] {
        let dark = colorScheme == .dark
        let strength = dark ? 0.42 : 0.24
        // Each bubble's glow gently breathes so the colors seem to move, not just the shapes.
        func glow(_ color: Color, _ speed: Double, _ phase: Double) -> Color {
            color.opacity(strength * (0.7 + 0.3 * sin(time * speed + phase)))
        }
        let violet = Color(red: 0.55, green: 0.32, blue: 0.98)
        let blue = Color(red: 0.22, green: 0.45, blue: 1)
        let indigo = Color(red: 0.36, green: 0.3, blue: 0.9)
        let pink = Color(red: 0.82, green: 0.38, blue: 0.95)
        let cyan = Color(red: 0.25, green: 0.7, blue: 1)
        let base = Color.clear
        return [
            glow(violet, 0.2, 0), base, glow(blue, 0.17, 1), base,
            base, glow(indigo, 0.23, 2), glow(pink, 0.19, 0.4), glow(blue, 0.21, 3),
            glow(cyan, 0.18, 1.7), glow(violet, 0.16, 2.9), glow(blue, 0.22, 0.9), base,
            base, glow(blue, 0.2, 4.1), base, glow(violet, 0.15, 5),
        ]
    }
}
