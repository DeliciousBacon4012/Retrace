import AppKit
import SwiftUI

enum ThumbnailMetrics {
    /// Clear space around each thumbnail for its shadow and the corner buttons.
    static let shadowPadding: CGFloat = 16
    static let maximumSide: CGFloat = 220
    /// How far back a thumbnail steps when another one is in front.
    static let backScale: CGFloat = 0.88
}

/// The floating thumbnail shown after a capture.
///
/// Hover for actions. Double-click to open it in the editor. Drag it into any app,
/// or flick it toward the screen edge to put it away.
struct QuickAccessThumbnail: View {
    struct Actions {
        var copy: () -> Void
        var save: () -> Void
        var delete: () -> Void
        var pin: () -> Void
        var open: () -> Void
        var close: () -> Void
        var hover: (Bool) -> Void
    }

    let capture: CapturedImage
    let stack: QuickAccessStack
    /// -1 when the stack sits on the left edge, 1 on the right.
    let edge: CGFloat
    let alignment: OverlayCorner
    let speed: Double
    let actions: Actions

    @State private var isShown = false
    @State private var isHovering = false
    @State private var didCopy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFocused: Bool { stack.focusedID == capture.id }

    private var thumbnailSize: CGSize {
        let maximum = ThumbnailMetrics.maximumSide
        let size = capture.pointSize
        guard size.width > 0, size.height > 0 else { return CGSize(width: maximum, height: maximum * 0.6) }
        let ratio = min(maximum / size.width, maximum / size.height)
        return CGSize(width: max(size.width * ratio, 130), height: max(size.height * ratio, 84))
    }

    /// Thumbnails grow and shrink toward the screen edge they sit on.
    private var anchor: UnitPoint {
        switch alignment {
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        }
    }

    var body: some View {
        card
            .scaleEffect(isFocused ? 1 : ThumbnailMetrics.backScale, anchor: anchor)
            .blur(radius: isFocused ? 0 : 1.2)
            .saturation(isFocused ? 1 : 0.45)
            .brightness(isFocused ? 0 : -0.04)
            .opacity(isFocused ? 1 : 0.88)
            .animation(.smooth(duration: 0.32 * speed), value: isFocused)
            .padding(ThumbnailMetrics.shadowPadding)
            // Arrives from the screen edge with a soft spring.
            .offset(x: isShown || reduceMotion ? 0 : edge * 70)
            .scaleEffect(isShown ? 1 : 0.9, anchor: anchor)
            .opacity(isShown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.55 * speed, bounce: 0.22)) { isShown = true }
            }
            .onHover { hovering in
                withAnimation(.smooth(duration: 0.22 * speed)) { isHovering = hovering }
                actions.hover(hovering)
            }
            .onTapGesture(count: 2, perform: actions.open)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(capture.isVideo ? "Recording" : "Screenshot")
            .accessibilityAction(named: "Open in Editor", actions.open)
            .accessibilityAction(named: "Save", actions.save)
            .accessibilityAction(named: "Delete", actions.delete)
    }

    private var card: some View {
        Image(nsImage: capture.nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .clipShape(.rect(cornerRadius: Design.radiusM - 4))
            .overlay {
                if isHovering {
                    hoverActions
                        .transition(.opacity)
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .rect(cornerRadius: Design.radiusM))
            .shadow(color: .black.opacity(isFocused ? 0.28 : 0.12), radius: isFocused ? 12 : 6, y: 4)
    }

    private var hoverActions: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Design.radiusM - 4)
                .fill(.black.opacity(0.28))

            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    Button(didCopy ? "Copied" : "Copy") {
                        actions.copy()
                        withAnimation(.response) { didCopy = true }
                    }
                    .buttonStyle(.glass)
                    .contentTransition(.interpolate)
                    Button("Save", action: actions.save)
                        .buttonStyle(.glassProminent)
                }
                .controlSize(.regular)
            }

            VStack {
                HStack {
                    cornerButton("Close", symbol: "xmark", action: actions.close)
                    Spacer()
                    if !capture.isVideo {
                        cornerButton("Pin to Screen", symbol: "pin.fill", action: actions.pin)
                    }
                }
                Spacer()
                HStack {
                    cornerButton("Delete", symbol: "trash", action: actions.delete)
                    Spacer()
                }
            }
            .padding(6)
        }
        .clipShape(.rect(cornerRadius: Design.radiusM - 4))
    }

    private func cornerButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}
