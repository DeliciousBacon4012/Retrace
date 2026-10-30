import SwiftUI

/// A floating, capsule-shaped tab bar with a selector that glides between tabs.
///
/// On macOS 26 and later the bar is Liquid Glass, so it follows the person's glass
/// appearance (Clear or Tinted) and Reduce Transparency automatically. Earlier versions
/// use the system's regular material instead.
struct GlassTabBar: View {
    @Binding var selection: AppTab

    @Namespace private var selector
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        tabs
            .padding(5)
            .glassCapsuleBackground()
            .fixedSize()
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                TabButton(
                    tab: tab,
                    isSelected: tab == selection,
                    selector: selector,
                    shortcut: KeyEquivalent(Character(String(index + 1)))
                ) {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = tab
                    }
                }
            }
        }
    }
}

private struct TabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let selector: Namespace.ID
    let shortcut: KeyEquivalent
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(height: 20)
                Text(tab.title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: 76, height: 48)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.primary.opacity(0.1))
                        .matchedGeometryEffect(id: "selector", in: selector)
                } else if isHovering {
                    Capsule()
                        .fill(.primary.opacity(0.04))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .onHover { isHovering = $0 }
        .help(Text("\(tab.title) (⌘\(String(shortcut.character)))"))
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    /// Liquid Glass on macOS 26 and later, the regular material before that.
    @ViewBuilder
    func glassCapsuleBackground() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
    }
}

#Preview {
    @Previewable @State var selection = AppTab.home
    GlassTabBar(selection: $selection)
        .padding(40)
}
