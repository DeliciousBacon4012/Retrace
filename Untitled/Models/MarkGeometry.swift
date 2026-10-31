import AppKit
import CoreText

/// The path an arrow follows, as points from tail to tip.
nonisolated enum ArrowGeometry {
    static func centerline(for mark: Annotation) -> [CGPoint] {
        let start = mark.start
        let end = mark.end
        switch mark.style.route {
        case .straight:
            return [start, end]
        case .elbow:
            let dx = end.x - start.x
            let dy = end.y - start.y
            let corner = abs(dx) >= abs(dy) ? CGPoint(x: end.x, y: start.y) : CGPoint(x: start.x, y: end.y)
            return [start, corner, end]
        case .curved:
            // The handle sits on the curve halfway along, so the control point is
            // reflected out from the chord.
            let through = mark.resolvedControl
            let control = CGPoint(x: 2 * through.x - (start.x + end.x) / 2, y: 2 * through.y - (start.y + end.y) / 2)
            let steps = 32
            return (0...steps).map { step in
                let t = CGFloat(step) / CGFloat(steps)
                let a = (1 - t) * (1 - t)
                let b = 2 * (1 - t) * t
                let c = t * t
                return CGPoint(x: a * start.x + b * control.x + c * end.x, y: a * start.y + b * control.y + c * end.y)
            }
        }
    }

    /// The default bend for a new curved arrow: a gentle arc to the left of travel.
    static func defaultBend(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        let bend = length * 0.22
        return CGPoint(x: mid.x + dy / length * bend, y: mid.y - dx / length * bend)
    }

    static func length(of line: [CGPoint]) -> CGFloat {
        zip(line, line.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// Shortens a polyline by `distance` from its far end.
    static func trimmingEnd(_ line: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        guard distance > 0, line.count >= 2 else { return line }
        var remaining = distance
        var points = line
        while points.count >= 2 {
            let last = points[points.count - 1]
            let previous = points[points.count - 2]
            let segment = hypot(last.x - previous.x, last.y - previous.y)
            if segment > remaining {
                let t = (segment - remaining) / segment
                points[points.count - 1] = CGPoint(x: previous.x + (last.x - previous.x) * t, y: previous.y + (last.y - previous.y) * t)
                return points
            }
            remaining -= segment
            points.removeLast()
        }
        return points
    }

    /// The direction the line arrives at its end, measured over the last `span` of length
    /// so curves get a head that follows the curve.
    static func arrivalDirection(of line: [CGPoint], span: CGFloat) -> CGVector {
        guard let tip = line.last else { return CGVector(dx: 1, dy: 0) }
        let back = trimmingEnd(line, by: max(span, 1)).last ?? line.first ?? tip
        var dx = tip.x - back.x
        var dy = tip.y - back.y
        if hypot(dx, dy) < 0.001, line.count >= 2 {
            dx = tip.x - line[line.count - 2].x
            dy = tip.y - line[line.count - 2].y
        }
        let length = max(hypot(dx, dy), 0.001)
        return CGVector(dx: dx / length, dy: dy / length)
    }
}

/// Measures text marks the same way they're drawn.
nonisolated enum TextMetrics {
    static func font(for style: MarkStyle) -> NSFont {
        let weight: NSFont.Weight = switch style.weight {
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
        let base = NSFont.systemFont(ofSize: style.fontSize, weight: weight)
        let design: NSFontDescriptor.SystemDesign = switch style.font {
        case .rounded: .rounded
        case .system: .default
        case .monospaced: .monospaced
        case .serif: .serif
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: descriptor, size: style.fontSize) ?? base
    }

    static func size(of text: String, style: MarkStyle) -> CGSize {
        let font = font(for: style)
        let lines = (text.isEmpty ? " " : text).split(separator: "\n", omittingEmptySubsequences: false)
        var width: CGFloat = 0
        for line in lines {
            let attributed = NSAttributedString(string: line.isEmpty ? " " : String(line), attributes: [.font: font])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            width = max(width, CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil)))
        }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return CGSize(width: ceil(width) + 2, height: lineHeight * CGFloat(lines.count))
    }
}
