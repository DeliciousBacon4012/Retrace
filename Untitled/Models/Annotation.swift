import CoreGraphics
import Foundation

/// One mark drawn on a screenshot. Positions and sizes are in the image's pixels,
/// so marks stay put however the editor window is sized or zoomed.
nonisolated struct Annotation: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var tool: EditorTool
    var start: CGPoint
    var end: CGPoint
    /// The bend point of a curved arrow. `nil` means halfway, so the arrow is straight.
    var control: CGPoint?
    /// Freehand points for the pen and highlighter.
    var points: [CGPoint] = []
    var text = ""
    var number = 0
    var style: MarkStyle

    init(tool: EditorTool, at point: CGPoint, style: MarkStyle) {
        self.tool = tool
        start = point
        end = point
        self.style = style
        if tool.isFreehand {
            points = [point]
        }
    }

    /// Whether this highlighter mark was drawn as one straight stroke (with Shift).
    var isStraightStroke: Bool { tool == .highlighter && points.count == 2 }

    /// The rectangle a box-shaped mark covers.
    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// The bend point an arrow actually uses.
    var resolvedControl: CGPoint {
        control ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    /// The area the mark covers, before line width and shadow.
    var bounds: CGRect {
        switch tool {
        case .pen, .highlighter:
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        case .counter:
            let radius = style.counterRadius
            return CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
        case .text:
            return CGRect(origin: start, size: TextMetrics.size(of: text, style: style))
        case .arrow:
            let path = ArrowGeometry.centerline(for: self)
            return path.dropFirst().reduce(CGRect(origin: start, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        default:
            return rect
        }
    }

    var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    /// True when a drag was too small to mean anything, such as a stray click with the shape tool.
    var isNegligible: Bool {
        switch tool {
        case .text: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .counter: false
        case .pen, .highlighter: points.count < 2 || bounds.width + bounds.height < 3
        default: hypot(end.x - start.x, end.y - start.y) < 4
        }
    }

    /// Whether a click at `point` lands on this mark, with some slack for thin lines.
    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let slack = max(tolerance, style.lineWidth / 2 + 2)
        switch tool {
        case .arrow:
            let line = ArrowGeometry.centerline(for: self)
            return zip(line, line.dropFirst()).contains { Geometry.distance(from: point, toSegment: $0, $1) <= slack }
        case .pen, .highlighter:
            if points.count == 1, let only = points.first { return hypot(point.x - only.x, point.y - only.y) <= slack }
            return zip(points, points.dropFirst()).contains { Geometry.distance(from: point, toSegment: $0, $1) <= slack }
        case .shape where style.fill == .none:
            let outer = rect.insetBy(dx: -slack, dy: -slack)
            let inner = rect.insetBy(dx: slack, dy: slack)
            return outer.contains(point) && (inner.isNull || inner.isEmpty || !inner.contains(point))
        default:
            return bounds.insetBy(dx: -slack, dy: -slack).contains(point)
        }
    }

    mutating func move(by delta: CGSize) {
        start = start.offset(by: delta)
        end = end.offset(by: delta)
        control = control?.offset(by: delta)
        points = points.map { $0.offset(by: delta) }
    }
}

/// Everything about how a mark looks. Each tool remembers the last style used,
/// and the inspector edits the selected mark's style in place.
nonisolated struct MarkStyle: Hashable, Codable, Sendable {
    var color: RGBAColor = .coral
    var opacity: Double = 1
    /// Stroke width in pixels.
    var lineWidth: CGFloat = 6

    var shadow = true
    var shadowRadius: CGFloat = 6
    var shadowOpacity: Double = 0.3
    var dashed = false

    // Arrow
    var route: ArrowRoute = .straight
    var startHead: ArrowHead = .none
    var endHead: ArrowHead = .filled
    var headScale: Double = 1
    var tapered = true

    // Shape
    var shape: ShapeKind = .rectangle
    var fill: ShapeFill = .none
    /// Corner radius in pixels, for rectangles and redaction boxes.
    var cornerRadius: CGFloat = 8

    // Text
    var font: TextFont = .rounded
    var weight: TextWeight = .bold
    var fontSize: CGFloat = 32
    var textStyle: TextStyle = .plain

    // Counter
    var counterStyle: CounterStyle = .filled

    // Redaction
    var redaction: Redaction = .blur
    /// 0 is light, 1 is heavy.
    var strength: Double = 0.6

    // Spotlight: how the rest of the image recedes, each from 0 (untouched) to 1.
    var dim: Double = 0.5
    var fade: Double = 0
    var blur: Double = 0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case color, opacity, lineWidth, shadow, shadowRadius, shadowOpacity, dashed, route, startHead, endHead, headScale, tapered, shape, fill, cornerRadius, font, weight, fontSize, textStyle, counterStyle, redaction, strength, dim, fade, blur
    }

    /// Reads saved styles leniently: a setting that's missing, or that an older or newer
    /// version wrote differently, keeps its default instead of losing every saved style.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = (try? container.decodeIfPresent(type(of: color), forKey: .color)) ?? color
        opacity = (try? container.decodeIfPresent(type(of: opacity), forKey: .opacity)) ?? opacity
        lineWidth = (try? container.decodeIfPresent(type(of: lineWidth), forKey: .lineWidth)) ?? lineWidth
        shadow = (try? container.decodeIfPresent(type(of: shadow), forKey: .shadow)) ?? shadow
        shadowRadius = (try? container.decodeIfPresent(type(of: shadowRadius), forKey: .shadowRadius)) ?? shadowRadius
        shadowOpacity = (try? container.decodeIfPresent(type(of: shadowOpacity), forKey: .shadowOpacity)) ?? shadowOpacity
        dashed = (try? container.decodeIfPresent(type(of: dashed), forKey: .dashed)) ?? dashed
        route = (try? container.decodeIfPresent(type(of: route), forKey: .route)) ?? route
        startHead = (try? container.decodeIfPresent(type(of: startHead), forKey: .startHead)) ?? startHead
        endHead = (try? container.decodeIfPresent(type(of: endHead), forKey: .endHead)) ?? endHead
        headScale = (try? container.decodeIfPresent(type(of: headScale), forKey: .headScale)) ?? headScale
        tapered = (try? container.decodeIfPresent(type(of: tapered), forKey: .tapered)) ?? tapered
        shape = (try? container.decodeIfPresent(type(of: shape), forKey: .shape)) ?? shape
        fill = (try? container.decodeIfPresent(type(of: fill), forKey: .fill)) ?? fill
        cornerRadius = (try? container.decodeIfPresent(type(of: cornerRadius), forKey: .cornerRadius)) ?? cornerRadius
        font = (try? container.decodeIfPresent(type(of: font), forKey: .font)) ?? font
        weight = (try? container.decodeIfPresent(type(of: weight), forKey: .weight)) ?? weight
        fontSize = (try? container.decodeIfPresent(type(of: fontSize), forKey: .fontSize)) ?? fontSize
        textStyle = (try? container.decodeIfPresent(type(of: textStyle), forKey: .textStyle)) ?? textStyle
        counterStyle = (try? container.decodeIfPresent(type(of: counterStyle), forKey: .counterStyle)) ?? counterStyle
        redaction = (try? container.decodeIfPresent(type(of: redaction), forKey: .redaction)) ?? redaction
        strength = (try? container.decodeIfPresent(type(of: strength), forKey: .strength)) ?? strength
        dim = (try? container.decodeIfPresent(type(of: dim), forKey: .dim)) ?? dim
        fade = (try? container.decodeIfPresent(type(of: fade), forKey: .fade)) ?? fade
        blur = (try? container.decodeIfPresent(type(of: blur), forKey: .blur)) ?? blur
    }

    var counterRadius: CGFloat { fontSize * 0.75 }

    /// The style each tool starts with, sized for the screenshot's pixel density.
    static func defaults(for tool: EditorTool, scale: CGFloat) -> MarkStyle {
        var style = MarkStyle()
        style.lineWidth = 6 * scale
        style.shadowRadius = 6 * scale
        style.cornerRadius = 8 * scale
        style.fontSize = 28 * scale
        switch tool {
        case .shape:
            style.lineWidth = 5 * scale
        case .pen:
            style.lineWidth = 5 * scale
            style.shadow = false
        case .highlighter:
            style.color = .butter
            style.lineWidth = 22 * scale
            style.opacity = 0.45
            style.shadow = false
        case .text:
            style.shadow = true
        case .counter:
            style.fontSize = 22 * scale
        case .redact:
            // A solid box removes the pixels outright. Blur and pixelate can leave shapes behind.
            style.redaction = .solid
            style.color = .ink
            style.shadow = false
            style.cornerRadius = 4 * scale
        case .spotlight:
            style.shape = .ellipse
            style.shadow = false
            style.cornerRadius = 16 * scale
        default:
            break
        }
        return style
    }
}

nonisolated enum ArrowRoute: String, Codable, CaseIterable, Identifiable, Sendable {
    case straight, curved, elbow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .straight: String(localized: "Straight")
        case .curved: String(localized: "Curved")
        case .elbow: String(localized: "Elbow")
        }
    }
    var symbolName: String {
        switch self {
        case .straight: "arrow.up.right"
        case .curved: "arrow.turn.up.right"
        case .elbow: "arrow.turn.right.up"
        }
    }
}

nonisolated enum ArrowHead: String, Codable, CaseIterable, Identifiable, Sendable {
    case filled, open, circle, bar, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .filled: String(localized: "Filled")
        case .open: String(localized: "Open")
        case .circle: String(localized: "Dot")
        case .bar: String(localized: "Bar")
        case .none: String(localized: "None")
        }
    }
}

nonisolated enum ShapeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case rectangle, ellipse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rectangle: String(localized: "Rectangle")
        case .ellipse: String(localized: "Ellipse")
        }
    }
    var symbolName: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        }
    }
}

nonisolated enum ShapeFill: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, translucent, solid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: String(localized: "Outline")
        case .translucent: String(localized: "Tinted")
        case .solid: String(localized: "Solid")
        }
    }
}

nonisolated enum TextFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case rounded, system, monospaced, serif
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rounded: String(localized: "Rounded")
        case .system: String(localized: "System")
        case .monospaced: String(localized: "Mono")
        case .serif: String(localized: "Serif")
        }
    }
}

nonisolated enum TextWeight: String, Codable, CaseIterable, Identifiable, Sendable {
    case regular, semibold, bold, heavy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .regular: String(localized: "Regular")
        case .semibold: String(localized: "Semibold")
        case .bold: String(localized: "Bold")
        case .heavy: String(localized: "Heavy")
        }
    }
}

nonisolated enum TextStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case plain, outlined, label
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plain: String(localized: "Plain")
        case .outlined: String(localized: "Outlined")
        case .label: String(localized: "Label")
        }
    }
}

nonisolated enum CounterStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case filled, ring
    var id: String { rawValue }
    var title: String {
        switch self {
        case .filled: String(localized: "Filled")
        case .ring: String(localized: "Ring")
        }
    }
}

nonisolated enum Redaction: String, Codable, CaseIterable, Identifiable, Sendable {
    case blur, pixelate, solid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blur: String(localized: "Blur")
        case .pixelate: String(localized: "Mosaic")
        case .solid: String(localized: "Redact")
        }
    }
    var symbolName: String {
        switch self {
        case .blur: "drop.halffull"
        case .pixelate: "checkerboard.rectangle"
        case .solid: "rectangle.fill"
        }
    }
}

/// A color stored as plain numbers, so marks are `Sendable`, `Codable`, and easy to compare.
nonisolated struct RGBAColor: Hashable, Codable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// A color from a hex value such as 0xF2716B.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    // Pastel: soft enough to sit on any screenshot, strong enough to read at a glance.
    static let coral = RGBAColor(hex: 0xF2716B)
    static let apricot = RGBAColor(hex: 0xF7A35C)
    static let butter = RGBAColor(hex: 0xF5D06A)
    static let pistachio = RGBAColor(hex: 0xA8D672)
    static let mint = RGBAColor(hex: 0x6CCB9F)
    static let aqua = RGBAColor(hex: 0x5EC4D6)
    static let sky = RGBAColor(hex: 0x6FA8F2)
    static let periwinkle = RGBAColor(hex: 0x9393EE)
    static let lilac = RGBAColor(hex: 0xC18DE8)
    static let blush = RGBAColor(hex: 0xF08DB5)
    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let ink = RGBAColor(hex: 0x1D1D1F)

    // Vivid: the earlier system-like colors, kept for people who want more punch.
    static let vividRed = RGBAColor(red: 1, green: 0.23, blue: 0.19)
    static let vividOrange = RGBAColor(red: 1, green: 0.58, blue: 0)
    static let vividYellow = RGBAColor(red: 1, green: 0.84, blue: 0.04)
    static let vividGreen = RGBAColor(red: 0.2, green: 0.78, blue: 0.35)
    static let vividMint = RGBAColor(red: 0, green: 0.78, blue: 0.75)
    static let vividCyan = RGBAColor(red: 0.2, green: 0.68, blue: 0.9)
    static let vividBlue = RGBAColor(red: 0, green: 0.48, blue: 1)
    static let vividIndigo = RGBAColor(red: 0.35, green: 0.34, blue: 0.84)
    static let vividPurple = RGBAColor(red: 0.69, green: 0.32, blue: 0.87)
    static let vividPink = RGBAColor(red: 1, green: 0.18, blue: 0.47)
    static let black = RGBAColor(red: 0.08, green: 0.08, blue: 0.09)

    /// The same color with the opacity of `other`.
    func withOpacity(of other: RGBAColor) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, opacity: other.opacity)
    }

    /// Whether the two colors match, ignoring opacity.
    func sameHue(as other: RGBAColor) -> Bool {
        red == other.red && green == other.green && blue == other.blue
    }

    /// White text reads better on dark colors, black on light ones.
    var prefersLightContent: Bool {
        0.299 * red + 0.587 * green + 0.114 * blue < 0.6
    }
}

/// Small geometry helpers shared by marks and their renderer.
nonisolated enum Geometry {
    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// Snaps the line from `start` to `point` to the nearest 45°.
    static func snapped(from start: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }
}

nonisolated extension CGPoint {
    func offset(by delta: CGSize) -> CGPoint {
        CGPoint(x: x + delta.width, y: y + delta.height)
    }
}
