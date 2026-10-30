import CoreGraphics
import Foundation

/// One mark drawn on a screenshot. Positions are in the image's pixels, so marks
/// stay put however the editor window is sized.
nonisolated struct Annotation: Identifiable, Hashable, Sendable {
    let id: UUID
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    /// Freehand points for the pen and highlighter.
    var points: [CGPoint] = []
    var color: RGBAColor
    var lineWidth: CGFloat
    var isFilled = false
    var text = ""
    var number = 0
    var fontSize: CGFloat = 28

    init(tool: AnnotationTool, at point: CGPoint, color: RGBAColor, lineWidth: CGFloat) {
        id = UUID()
        self.tool = tool
        start = point
        end = point
        self.color = color
        self.lineWidth = lineWidth
        if tool.isFreehand {
            points = [point]
        }
    }

    /// The area the mark covers, before line width.
    var bounds: CGRect {
        switch tool {
        case .pen, .highlighter:
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        case .counter:
            let radius = counterRadius
            return CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
        case .text:
            let lines = max(text.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
            let longest = text.split(separator: "\n").map(\.count).max() ?? 1
            return CGRect(x: start.x, y: start.y, width: CGFloat(max(longest, 1)) * fontSize * 0.6, height: CGFloat(lines) * fontSize * 1.25)
        default:
            return CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            )
        }
    }

    var counterRadius: CGFloat { fontSize * 0.8 }

    /// True when a drag was too small to mean anything, such as a stray click with the rectangle tool.
    var isNegligible: Bool {
        switch tool {
        case .text: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .counter: false
        case .pen, .highlighter: points.count < 2
        default: hypot(end.x - start.x, end.y - start.y) < 4
        }
    }

    /// Whether a click at `point` lands on this mark, with some slack for thin lines.
    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let slack = max(tolerance, lineWidth)
        switch tool {
        case .arrow, .line:
            return distance(from: point, toSegment: start, end) <= slack
        case .pen, .highlighter:
            return zip(points, points.dropFirst()).contains { distance(from: point, toSegment: $0, $1) <= slack }
        case .rectangle, .ellipse:
            if isFilled { return bounds.insetBy(dx: -slack, dy: -slack).contains(point) }
            let outer = bounds.insetBy(dx: -slack, dy: -slack)
            let inner = bounds.insetBy(dx: slack, dy: slack)
            return outer.contains(point) && (inner.isNull || !inner.contains(point))
        default:
            return bounds.insetBy(dx: -slack, dy: -slack).contains(point)
        }
    }

    mutating func move(by delta: CGSize) {
        start = CGPoint(x: start.x + delta.width, y: start.y + delta.height)
        end = CGPoint(x: end.x + delta.width, y: end.y + delta.height)
        points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
    }

    private func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}

/// The editor's tools, in toolbar order.
nonisolated enum AnnotationTool: String, CaseIterable, Identifiable, Hashable, Sendable {
    case select
    case arrow
    case rectangle
    case ellipse
    case line
    case pen
    case highlighter
    case text
    case counter
    case blur
    case pixelate
    case crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: String(localized: "Select")
        case .arrow: String(localized: "Arrow")
        case .rectangle: String(localized: "Rectangle")
        case .ellipse: String(localized: "Ellipse")
        case .line: String(localized: "Line")
        case .pen: String(localized: "Pen")
        case .highlighter: String(localized: "Highlighter")
        case .text: String(localized: "Text")
        case .counter: String(localized: "Step Counter")
        case .blur: String(localized: "Blur")
        case .pixelate: String(localized: "Pixelate")
        case .crop: String(localized: "Crop")
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .blur: "drop.halffull"
        case .pixelate: "checkerboard.rectangle"
        case .crop: "crop"
        }
    }

    /// The single key that picks this tool, shown in its tooltip.
    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .rectangle: "r"
        case .ellipse: "o"
        case .line: "l"
        case .pen: "p"
        case .highlighter: "h"
        case .text: "t"
        case .counter: "n"
        case .blur: "b"
        case .pixelate: "x"
        case .crop: "c"
        }
    }

    var isFreehand: Bool { self == .pen || self == .highlighter }
    var isRedaction: Bool { self == .blur || self == .pixelate }
    /// Tools that draw a new mark, as opposed to selecting or cropping.
    var draws: Bool { self != .select && self != .crop }
    var supportsFill: Bool { self == .rectangle || self == .ellipse }
}

/// A color stored as plain numbers, so marks are `Sendable` and easy to compare.
nonisolated struct RGBAColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1

    static let red = RGBAColor(red: 1, green: 0.23, blue: 0.19)
    static let orange = RGBAColor(red: 1, green: 0.58, blue: 0)
    static let yellow = RGBAColor(red: 1, green: 0.8, blue: 0)
    static let green = RGBAColor(red: 0.2, green: 0.78, blue: 0.35)
    static let blue = RGBAColor(red: 0, green: 0.48, blue: 1)
    static let purple = RGBAColor(red: 0.69, green: 0.32, blue: 0.87)
    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)

    static let presets: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]

    /// White text reads better on dark colors, black on light ones.
    var prefersLightContent: Bool {
        0.299 * red + 0.587 * green + 0.114 * blue < 0.6
    }
}
