import SwiftUI

/// A floating capsule tab bar with a Liquid Glass selector you can click or drag.
///
/// The selector follows the pointer while dragging, stretches with speed, rubber-bands
/// past the ends, and on release is thrown toward the tab its velocity points at, settling
/// with a spring. On macOS 26 and later both the bar and the selector are interactive
/// Liquid Glass inside one `GlassEffectContainer`, so they follow the system glass
/// appearance and Reduce Transparency. With Reduce Motion on, the selector moves without
/// bounce or stretch. Earlier macOS versions use the regular material.
struct GlassTabBar: View {
    @Binding var selection: AppTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    /// The selector's center while dragging, in the bar's coordinate space; `nil` when at rest.
    @State private var dragX: CGFloat?
    /// Horizontal drag speed in points per second, used for the stretch.
    @State private var dragVelocity: CGFloat = 0

    private let tabs = AppTab.allCases
    private let itemSize = CGSize(width: 76, height: 50)
    private let spacing: CGFloat = 2
    private let inset: CGFloat = 5

    var body: some View {
        bar
            .background(shortcutButtons)
    }

    // MARK: Layout

    private var step: CGFloat { itemSize.width + spacing }
    private var barWidth: CGFloat { CGFloat(tabs.count) * itemSize.width + CGFloat(tabs.count - 1) * spacing }

    private func center(of index: Int) -> CGFloat {
        CGFloat(index) * step + itemSize.width / 2
    }

    private var selectedIndex: Int {
        tabs.firstIndex(of: selection) ?? 0
    }

    /// The selector's current center: following the drag, or resting on the selected tab.
    private var selectorX: CGFloat {
        dragX ?? center(of: selectedIndex)
    }

    /// The tab nearest the selector right now, so labels light up while dragging.
    private var highlightedIndex: Int {
        nearestIndex(to: selectorX)
    }

    private func nearestIndex(to x: CGFloat) -> Int {
        let raw = ((x - itemSize.width / 2) / step).rounded()
        return min(max(Int(raw), 0), tabs.count - 1)
    }

    // MARK: Views

    @ViewBuilder
    private var bar: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                content
                    .padding(inset)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("bar", in: glassNamespace)
            }
        } else {
            content
                .padding(inset)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
    }

    private var content: some View {
        ZStack(alignment: .leading) {
            selector
            HStack(spacing: spacing) {
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    TabItem(tab: tab, isHighlighted: index == highlightedIndex, size: itemSize)
                        .onTapGesture { select(index, velocity: 0) }
                        .accessibilityAction { select(index, velocity: 0) }
                        .accessibilityAddTraits(index == selectedIndex ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .frame(width: barWidth, height: itemSize.height)
        .contentShape(Capsule())
        .simultaneousGesture(dragGesture)
    }

    @ViewBuilder
    private var selector: some View {
        let shape = Capsule()
        let stretch = reduceMotion ? 0 : min(abs(dragVelocity) / 4000, 0.22)
        let lift: CGFloat = (dragX != nil && !reduceMotion) ? 1.06 : 1

        Group {
            if #available(macOS 26.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.22)).interactive(), in: shape)
                    .glassEffectID("selector", in: glassNamespace)
            } else {
                shape.fill(Color.accentColor.opacity(0.18))
            }
        }
        .frame(width: itemSize.width, height: itemSize.height)
        .scaleEffect(x: lift * (1 + stretch), y: lift * (1 - stretch * 0.4))
        .offset(x: selectorX - itemSize.width / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Invisible buttons that give Command-1 to Command-5 to the tabs.
    private var shortcutButtons: some View {
        ZStack {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { select(index, velocity: 0) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Physics

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let raw = center(of: selectedIndex) + value.translation.width
                let lower = center(of: 0)
                let upper = center(of: tabs.count - 1)
                // Rubber-band past either end: the further you pull, the less it follows.
                let banded: CGFloat = if raw < lower {
                    lower - rubberBand(lower - raw)
                } else if raw > upper {
                    upper + rubberBand(raw - upper)
                } else {
                    raw
                }
                if reduceMotion {
                    dragX = banded
                    dragVelocity = 0
                } else {
                    withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
                        dragX = banded
                        dragVelocity = value.velocity.width
                    }
                }
            }
            .onEnded { value in
                let current = dragX ?? center(of: selectedIndex)
                // Project where a flick would carry the selector, then snap to that tab.
                let projected = current + value.velocity.width * 0.12
                select(nearestIndex(to: projected), velocity: value.velocity.width)
            }
    }

    private func rubberBand(_ distance: CGFloat) -> CGFloat {
        let limit: CGFloat = 40
        return limit * (1 - 1 / (distance / limit * 0.55 + 1))
    }

    /// Moves the selector to a tab with a spring that carries the release velocity.
    private func select(_ index: Int, velocity: CGFloat) {
        let target = tabs[index]
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = target
                dragX = nil
                dragVelocity = 0
            }
            return
        }

        let from = dragX ?? center(of: selectedIndex)
        let distance = center(of: index) - from
        // SwiftUI expects initial velocity relative to the distance still to travel.
        let relativeVelocity = abs(distance) > 1 ? velocity / distance : 0
        let spring = Animation.interpolatingSpring(
            mass: 1,
            stiffness: 260,
            damping: 20,
            initialVelocity: min(max(relativeVelocity, -20), 20)
        )
        withAnimation(spring) {
            selection = target
            dragX = nil
            dragVelocity = 0
        }
    }
}

/// One tab's icon and title.
private struct TabItem: View {
    let tab: AppTab
    let isHighlighted: Bool
    let size: CGSize

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 17, weight: .medium))
                .symbolVariant(isHighlighted ? .fill : .none)
                .frame(height: 20)
            Text(tab.title)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(isHovering ? .primary : .secondary))
        .frame(width: size.width, height: size.height)
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
        .help(Text(tab.title))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tab.title))
    }
}

#Preview {
    @Previewable @State var selection = AppTab.home
    GlassTabBar(selection: $selection)
        .padding(40)
}
