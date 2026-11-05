import AppKit
import Observation
import SwiftUI

/// Creates a Retina-sized copy without blocking the capture-completion path.
nonisolated enum QuickAccessThumbnailRenderer {
    static func needsDownsampling(_ image: CGImage, for cardSize: CGSize) -> Bool {
        let target = CGSize(width: cardSize.width * 2, height: cardSize.height * 2)
        let factor = max(target.width / CGFloat(image.width), target.height / CGFloat(image.height))
        return factor > 0 && factor < 1
    }

    static func downsample(_ image: CGImage, for cardSize: CGSize) -> CGImage? {
        let target = CGSize(width: cardSize.width * 2, height: cardSize.height * 2)
        let factor = max(target.width / CGFloat(image.width), target.height / CGFloat(image.height))
        guard factor > 0, factor < 1,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// Everything the Quick Access stack shows, newest thumbnail first.
@Observable
final class QuickAccessStackModel {
    struct Card: Identifiable {
        let id: UUID
        var capture: CapturedImage
        /// A small copy for display, so a stack of 5K captures stays light.
        var thumbnail: NSImage
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
                .animation(floorAnimation, value: model.isExpanded)
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

    /// Every floor responds together; the spring keeps the stack tactile without a staggered wait.
    private var floorAnimation: Animation {
        guard !reduceMotion else { return .easeInOut(duration: 0.15) }
        return model.isExpanded
            ? .spring(response: 0.38 * model.speed, dampingFraction: 0.82)
            : .spring(response: 0.32 * model.speed, dampingFraction: 0.9)
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
        cardSurface
            .contextMenu { QuickAccessCardContextMenu(card: card, actions: actions) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(card.capture.isVideo ? "Recording" : "Screenshot")
            .accessibilityAction(named: "Open in Editor") { actions.open(id) }
            .accessibilityAction(named: "Save") { actions.save(id) }
            .accessibilityAction(named: "Delete") { actions.delete(id) }
    }

    private var cardSurface: some View {
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
            .overlay { hoverOverlay }
            .overlay(alignment: .topTrailing) { badgeOverlay }
            // On a shape behind the card, so hover changes don't redraw the shadow.
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            }
            .animation(.smooth(duration: 0.18), value: isHovered)
    }

    @ViewBuilder
    private var hoverOverlay: some View {
        if isHovered {
            hoverActions
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var badgeOverlay: some View {
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
                    // A capture that's already on disk has nothing to save, only somewhere to go.
                    if card.capture.fileURL == nil {
                        Button("Save") { actions.save(id) }
                            .buttonStyle(.glassProminent)
                    } else {
                        Button("Show in Finder") { actions.showInFinder(id) }
                            .buttonStyle(.glass)
                    }
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

private struct QuickAccessCardContextMenu: View {
    let card: QuickAccessStackModel.Card
    let actions: QuickAccessStackView.Actions

    private var id: UUID { card.id }

    @ViewBuilder
    var body: some View {
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
}

#Preview("Quick Access stack") {
    QuickAccessStackPreview(expanded: false)
}

#Preview("Quick Access column") {
    QuickAccessStackPreview(expanded: true)
}

#Preview("Quick Access actions") {
    QuickAccessStackPreview(expanded: false, hovered: true)
}

@MainActor
private struct QuickAccessStackPreview: View {
    let expanded: Bool
    private let model: QuickAccessStackModel

    init(expanded: Bool, hovered: Bool = false) {
        self.expanded = expanded
        let model = QuickAccessStackModel()
        model.corner = .bottomRight
        model.isExpanded = expanded
        model.geometry.cardSize = QuickAccessSize.medium.cardSize(for: .threeTwo)
        model.cards = [
            Self.card(background: CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1), accent: CGColor(srgbRed: 0.25, green: 0.50, blue: 0.85, alpha: 1)),
            Self.card(background: CGColor(srgbRed: 0.93, green: 0.95, blue: 0.95, alpha: 1), accent: CGColor(srgbRed: 0.27, green: 0.65, blue: 0.53, alpha: 1)),
            Self.card(background: CGColor(srgbRed: 0.96, green: 0.94, blue: 0.91, alpha: 1), accent: CGColor(srgbRed: 0.83, green: 0.48, blue: 0.24, alpha: 1)),
        ]
        if hovered { model.hoveredID = model.cards.first?.id }
        self.model = model
    }

    var body: some View {
        let size = model.geometry.panelSize(count: model.cards.count, expanded: expanded)
        QuickAccessStackView(model: model, actions: .preview)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .padding(24)
            .background(Color(nsColor: .underPageBackgroundColor))
    }

    private static func card(background: CGColor, accent: CGColor) -> QuickAccessStackModel.Card {
        let width = 900
        let height = 600
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 535, width: CGFloat(width), height: 65))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 205, height: 535))
        context.setFillColor(accent)
        context.fill(CGRect(x: 244, y: 438, width: 250, height: 16))
        context.setFillColor(CGColor(gray: 0.82, alpha: 1))
        for row in 0..<5 {
            context.fill(CGRect(x: 244, y: CGFloat(360 - row * 58), width: CGFloat(560 - row * 26), height: 10))
        }
        let image = context.makeImage()!
        let capture = CapturedImage(image: image, scale: 2, date: .now)
        return QuickAccessStackModel.Card(id: capture.id, capture: capture, thumbnail: capture.nsImage)
    }
}

private extension QuickAccessStackView.Actions {
    static var preview: Self {
        Self(
            copy: { _ in },
            save: { _ in },
            delete: { _ in },
            pin: { _ in },
            open: { _ in },
            close: { _ in },
            closeAll: {},
            showInFinder: { _ in }
        )
    }
}
