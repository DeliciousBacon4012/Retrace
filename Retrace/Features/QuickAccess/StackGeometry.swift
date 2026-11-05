import CoreGraphics

/// Where each Quick Access thumbnail sits, as distances from the screen corner the stack
/// lives in. Index 0 is the newest thumbnail, nearest the corner.
///
/// Collapsed, older thumbnails peek out a few points behind the newest one, each a little
/// smaller. Expanded, every thumbnail gets its own "floor", evenly spaced away from the corner:
/// upward from a bottom corner, downward from a top corner.
nonisolated struct StackGeometry: Equatable, Sendable {
    struct Placement: Equatable, Sendable {
        /// How far the thumbnail's near edge moves away from the corner, in points.
        var distance: CGFloat
        /// Scaled toward the far edge, so a smaller thumbnail still peeks out above the one in front.
        var scale: CGFloat
        var opacity: Double
    }

    var cardSize: CGSize
    /// Clear space around the stack inside its window, for shadows and for flicking off-screen.
    var padding: CGFloat = 16
    /// How much of each older thumbnail shows behind the newest one when collapsed.
    var peek: CGFloat = 7
    /// Space between floors when expanded.
    var gap: CGFloat = 10
    /// How many older thumbnails peek out when collapsed.
    var peekingCount = 2
    /// How much smaller each older thumbnail is when collapsed.
    var scaleStep: CGFloat = 0.06

    func placement(at index: Int, count: Int, expanded: Bool) -> Placement {
        guard index > 0 else { return Placement(distance: 0, scale: 1, opacity: 1) }
        if expanded {
            return Placement(distance: CGFloat(index) * (cardSize.height + gap), scale: 1, opacity: 1)
        }
        let depth = min(index, peekingCount)
        return Placement(
            distance: CGFloat(depth) * peek,
            scale: 1 - CGFloat(depth) * scaleStep,
            opacity: index <= peekingCount ? 1 : 0
        )
    }

    /// The height the thumbnails cover, without padding.
    func contentHeight(count: Int, expanded: Bool) -> CGFloat {
        guard count > 0 else { return 0 }
        if expanded {
            return CGFloat(count) * cardSize.height + CGFloat(count - 1) * gap
        }
        return cardSize.height + CGFloat(min(count - 1, peekingCount)) * peek
    }

    /// The size of the window that holds the stack.
    func panelSize(count: Int, expanded: Bool) -> CGSize {
        CGSize(width: cardSize.width + padding * 2, height: contentHeight(count: count, expanded: expanded) + padding * 2)
    }

    /// How many thumbnails fit, expanded, in a screen area this tall.
    func capacity(forHeight height: CGFloat) -> Int {
        max(1, Int((height - padding * 2 + gap) / (cardSize.height + gap)))
    }

    /// The thumbnail's rectangle inside the stack's window, top-left origin, for hit testing.
    func frame(at index: Int, count: Int, expanded: Bool, in size: CGSize, fromBottom: Bool) -> CGRect {
        let place = placement(at: index, count: count, expanded: expanded)
        let width = cardSize.width * place.scale
        let height = cardSize.height * place.scale
        let x = padding + (cardSize.width - width) / 2
        // Scaling keeps the far edge in place, so the near edge moves toward the far one.
        let y = fromBottom
            ? size.height - (padding + place.distance + cardSize.height)
            : padding + place.distance + cardSize.height - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
