import CoreGraphics
import Foundation

/// The shapes a crop can be locked to. Free lets it take any shape.
nonisolated enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case free
    case original
    case wide
    case standard
    case square
    case portrait
    case tall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: String(localized: "Free")
        case .original: String(localized: "Original")
        case .wide: "16:9"
        case .standard: "4:3"
        case .square: "1:1"
        case .portrait: "3:4"
        case .tall: "9:16"
        }
    }

    /// Width over height, or `nil` for Free.
    func ratio(for imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: imageSize.height > 0 ? imageSize.width / imageSize.height : nil
        case .wide: 16 / 9
        case .standard: 4 / 3
        case .square: 1
        case .portrait: 3 / 4
        case .tall: 9 / 16
        }
    }
}

/// Crop boxes that keep a fixed aspect ratio while you drag, and never leave the image.
nonisolated enum CropGeometry {
    /// A box from a fixed corner toward the pointer, as large as the pointer asks for in either
    /// direction, shrunk if needed so it stays inside `bounds`.
    static func box(from anchor: CGPoint, to point: CGPoint, ratio: CGFloat, in bounds: CGRect) -> CGRect {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let towardRight = dx >= 0
        let towardBottom = dy >= 0
        var width = abs(dx)
        var height = abs(dy)
        if width > height * ratio {
            height = width / ratio
        } else {
            width = height * ratio
        }
        let roomX = towardRight ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let roomY = towardBottom ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        let shrink = min(1, roomX / max(width, 0.001), roomY / max(height, 0.001))
        width *= max(shrink, 0)
        height *= max(shrink, 0)
        return CGRect(
            x: towardRight ? anchor.x : anchor.x - width,
            y: towardBottom ? anchor.y : anchor.y - height,
            width: width,
            height: height
        )
    }

    /// Moving one edge (top, right, bottom, left): the opposite edge stays put and the other
    /// two follow the ratio, centered, so the box grows evenly.
    static func box(movingEdge edge: Int, of rect: CGRect, to point: CGPoint, ratio: CGFloat, in bounds: CGRect) -> CGRect {
        switch edge {
        case 0, 2:
            let fixedY = edge == 0 ? rect.maxY : rect.minY
            var height = max(edge == 0 ? fixedY - point.y : point.y - fixedY, 1)
            var width = height * ratio
            let roomX = 2 * min(rect.midX - bounds.minX, bounds.maxX - rect.midX)
            let roomY = edge == 0 ? fixedY - bounds.minY : bounds.maxY - fixedY
            let shrink = min(1, roomX / width, roomY / height)
            width *= shrink
            height *= shrink
            return CGRect(x: rect.midX - width / 2, y: edge == 0 ? fixedY - height : fixedY, width: width, height: height)
        default:
            let fixedX = edge == 3 ? rect.maxX : rect.minX
            var width = max(edge == 3 ? fixedX - point.x : point.x - fixedX, 1)
            var height = width / ratio
            let roomY = 2 * min(rect.midY - bounds.minY, bounds.maxY - rect.midY)
            let roomX = edge == 3 ? fixedX - bounds.minX : bounds.maxX - fixedX
            let shrink = min(1, roomX / width, roomY / height)
            width *= shrink
            height *= shrink
            return CGRect(x: edge == 3 ? fixedX - width : fixedX, y: rect.midY - height / 2, width: width, height: height)
        }
    }

    /// The largest box of `ratio` that fits in `bounds`, centered on `center` where possible.
    static func largest(ratio: CGFloat, in bounds: CGRect, around center: CGPoint) -> CGRect {
        var width = bounds.width
        var height = width / ratio
        if height > bounds.height {
            height = bounds.height
            width = height * ratio
        }
        let x = min(max(center.x - width / 2, bounds.minX), bounds.maxX - width)
        let y = min(max(center.y - height / 2, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
