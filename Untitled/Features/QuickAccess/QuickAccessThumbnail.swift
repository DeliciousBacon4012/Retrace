import AppKit
import Observation
import SwiftUI

/// Everything the Quick Access stack shows, newest thumbnail first.
@Observable
final class QuickAccessStackModel {
    struct Card: Identifiable {
        let id: UUID
        var capture: CapturedImage
        /// A small copy for display, so a stack of 5K captures stays light.
        let thumbnail: NSImage
    }

    var cards: [Card] = []
    var isExpanded = false
    var hoveredID: UUID?
    /// Sideways movement of a thumbnail being flicked away.
    var swipeOffsets: [UUID: CGFloat] = [:]
    var corner: OverlayCorner = .bottomLeft
    var geometry = StackGeometry(cardSize: QuickAccessSize.medium.cardSize)
    var speed: Double = 1

    /// The thumbnail under a point in the stack's window (top-left origin), front-most first.
    func cardID(at point: CGPoint, in size: CGSize) -> UUID? {
        for (index, card) in cards.enumerated() {
            let place = geometry.placement(at: index, count: cards.count, expanded: isExpanded)
            guard place.opacity > 0 else { continue }
            if geometry.frame(at: index, count: cards.count, expanded: isExpanded, in: size, fromBottom: corner.isBottom).contains(point) {
                return card.id
            }
        }
        return nil
    }
}

/// The Quick Access stack: one window, one layout, so thumbnails never pile up or fight over hover.
struct QuickAccessStackView: View {
    struct Actions {
        var copy: (UUID) -> Void
        var save: (UUID) -> Void
        var delete: (UUID) -> Void
        var pin: (UUID) -> Void
        var open: (UUID) -> Void
        var close: (UUID) -> Void
        var closeAll: () -> Void
        var showInFinder: (UUID) -> Void
    }

    let model: QuickAccessStackModel
    let actions: Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var alignment: Alignment {
        switch model.corner {
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        }
    }

    /// -1 when the stack sits on the left edge, 1 on the right.
    private var edge: CGFloat { model.corner.isLeft ? -1 : 1 }

    var body: some View {
        let count = model.cards.count
        ZStack(alignment: alignment) {
            ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                let place = model.geometry.placement(at: index, count: count, expanded: model.isExpanded)
                let isReachable = model.isExpanded || index == 0
                QuickAccessCard(
                    card: card,
                    size: model.geometry.cardSize,
                    isHovered: isReachable && model.hoveredID == card.id,
                    badge: !model.isExpanded && index == 0 && count > 1 ? count : nil,
                    actions: actions
                )
                .onHover { hovering in
                    if hovering {
                        model.hoveredID = card.id
                    } else if model.hoveredID == card.id {
                        model.hoveredID = nil
                    }
                }
                .allowsHitTesting(isReachable)
                .scaleEffect(place.scale, anchor: model.corner.isBottom ? .top : .bottom)
                .opacity(place.opacity)
                .offset(
                    x: model.swipeOffsets[card.id] ?? 0,
                    y: model.corner.isBottom ? -place.distance : place.distance
                )
                .zIndex(Double(count - index))
                .animation(floorAnimation(index: index), value: model.isExpanded)
                .transition(
                    .asymmetric(
                        insertion: .offset(x: reduceMotion ? 0 : edge * 60).combined(with: .opacity),
                        removal: .opacity
                    )
                )
            }
        }
        .padding(model.geometry.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// Floors rise one after another, nearest first, like a quick ripple.
    private func floorAnimation(index: Int) -> Animation {
        guard !reduceMotion else { return .easeInOut(duration: 0.15) }
        let spring: Animation = model.isExpanded
            ? .spring(response: 0.38 * model.speed, dampingFraction: 0.82)
            : .spring(response: 0.32 * model.speed, dampingFraction: 0.9)
        return spring.delay(model.isExpanded ? Double(index) * 0.025 * model.speed : 0)
    }
}

/// One thumbnail: the capture clipped to rounded corners, with actions while the pointer is over it.
private struct QuickAccessCard: View {
    let card: QuickAccessStackModel.Card
    let size: CGSize
    let isHovered: Bool
    /// How many captures are stacked, shown on the front thumbnail while collapsed.
    let badge: Int?
    let actions: QuickAccessStackView.Actions

    @State private var didCopy = false

    private var id: UUID { card.id }

    /// Tall captures show their top, where titles and headers usually are.
    private var cropAlignment: Alignment {
        let pixels = card.capture.pointSize
        return pixels.height > pixels.width ? .top : .center
    }

    var body: some View {
        Image(nsImage: card.thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height, alignment: cropAlignment)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12, style: .continuous))
            .onTapGesture { actions.open(id) }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
            .overlay {
                if isHovered {
                    hoverActions
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge, !isHovered {
                    Text(badge, format: .number)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .glassEffect(.regular, in: .capsule)
                        .padding(6)
                        .transition(.opacity)
                        .accessibilityLabel("\(badge) captures")
                }
            }
            // On a shape behind the card, so hover changes don't redraw the shadow.
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            }
            .animation(.smooth(duration: 0.18), value: isHovered)
            .contextMenu { contextMenu }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(card.capture.isVideo ? "Recording" : "Screenshot")
            .accessibilityAction(named: "Open in Editor") { actions.open(id) }
            .accessibilityAction(named: "Save") { actions.save(id) }
            .accessibilityAction(named: "Delete") { actions.delete(id) }
    }

    /// Clear glass buttons over a light dim, as macOS does for controls over photos and video.
    private var hoverActions: some View {
        ZStack {
            Color.black.opacity(0.2)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .onTapGesture { actions.open(id) }

            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    Button(didCopy ? "Copied" : "Copy") {
                        actions.copy(id)
                        didCopy = true
                    }
                    .buttonStyle(.glass)
                    Button("Save") { actions.save(id) }
                        .buttonStyle(.glassProminent)
                }
                .controlSize(.regular)
            }

            VStack {
                HStack {
                    cornerButton("Close", symbol: "xmark") { actions.close(id) }
                    Spacer()
                    if !card.capture.isVideo {
                        cornerButton("Pin to Screen", symbol: "pin") { actions.pin(id) }
                    }
                }
                Spacer()
                HStack {
                    cornerButton("Delete", symbol: "trash") { actions.delete(id) }
                    Spacer()
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(card.capture.isVideo ? "Open" : "Open in Editor") { actions.open(id) }
        Button("Copy") { actions.copy(id) }
        if card.capture.fileURL == nil {
            Button("Save") { actions.save(id) }
        } else {
            Button("Show in Finder") { actions.showInFinder(id) }
        }
        if let url = card.capture.fileURL {
            ShareLink(item: url) { Text("Share…") }
        }
        if !card.capture.isVideo {
            Button("Pin to Screen") { actions.pin(id) }
        }
        Divider()
        Button("Close") { actions.close(id) }
        Button("Close All") { actions.closeAll() }
        Divider()
        Button("Move to Trash", role: .destructive) { actions.delete(id) }
    }

    private func cornerButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}
