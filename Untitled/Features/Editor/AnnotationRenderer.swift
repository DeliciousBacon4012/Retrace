import SwiftUI

/// Draws a screenshot and its marks. The editor canvas and the exported image
/// both use this, so what you see is exactly what gets saved.
enum AnnotationRenderer {
    /// Supplies the blurred or pixelated copy of the screenshot for a redaction at a strength.
    typealias Redactor = (Redaction, Double) -> CGImage?

    static func draw(image: CGImage, annotations: [Annotation], redacted: Redactor, in context: inout GraphicsContext) {
        context.draw(Image(decorative: image, scale: 1), in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for annotation in annotations {
            draw(annotation, redacted: redacted, in: &context)
        }
    }

    static func draw(_ mark: Annotation, redacted: Redactor, in context: inout GraphicsContext) {
        let style = mark.style
        var outer = context
        if style.shadow, mark.tool != .highlighter, mark.tool != .redact {
            outer.addFilter(.shadow(
                color: .black.opacity(style.shadowOpacity),
                radius: style.shadowRadius,
                x: 0,
                y: style.shadowRadius * 0.35
            ))
        }
        if mark.tool == .highlighter {
            outer.blendMode = .multiply
        }
        outer.opacity = mark.tool == .redact ? 1 : style.opacity

        // Everything is drawn into one layer first, so the shadow and opacity
        // apply to the mark as a whole and overlapping parts don't double up.
        outer.drawLayer { layer in
            switch mark.tool {
            case .arrow: drawArrow(mark, in: &layer)
            case .shape: drawShape(mark, in: &layer)
            case .pen: drawPen(mark, in: &layer)
            case .highlighter: drawHighlighter(mark, in: &layer)
            case .text: drawText(mark, in: &layer)
            case .counter: drawCounter(mark, in: &layer)
            case .redact: drawRedaction(mark, redacted: redacted, in: &layer)
            case .select, .crop: break
            }
        }
    }

    // MARK: Arrows

    private static func drawArrow(_ mark: Annotation, in layer: inout GraphicsContext) {
        let style = mark.style
        let color = style.color.swiftUIColor
        let line = ArrowGeometry.centerline(for: mark)
        let total = ArrowGeometry.length(of: line)
        guard total > 0.5, let tip = line.last, let tail = line.first else { return }

        let width = max(style.lineWidth, 1)
        let headLength = min(max(width * 3.4, 6) * style.headScale, total * 0.45)
        let headHalfWidth = max(width * 1.75, 4) * style.headScale

        var shaft = line
        if style.endHead == .filled {
            shaft = ArrowGeometry.trimmingEnd(shaft, by: headLength * 0.7)
        }
        if style.startHead == .filled {
            shaft = Array(ArrowGeometry.trimmingEnd(shaft.reversed(), by: headLength * 0.7).reversed())
        }

        if style.tapered, !style.dashed, style.startHead == .none, shaft.count >= 2 {
            layer.fill(taperedPath(shaft, from: width * 0.2, to: width), with: .color(color))
            if style.endHead != .filled, let last = shaft.last {
                layer.fill(Path(ellipseIn: CGRect(x: last.x - width / 2, y: last.y - width / 2, width: width, height: width)), with: .color(color))
            }
        } else if shaft.count >= 2 {
            var path = Path()
            path.addLines(shaft)
            layer.stroke(path, with: .color(color), style: StrokeStyle(
                lineWidth: width,
                lineCap: .round,
                lineJoin: .round,
                dash: style.dashed ? [width * 1.2, width * 2.4] : []
            ))
        }

        drawHead(style.endHead, tip: tip, direction: ArrowGeometry.arrivalDirection(of: line, span: headLength), length: headLength, halfWidth: headHalfWidth, lineWidth: width, color: color, in: &layer)
        drawHead(style.startHead, tip: tail, direction: ArrowGeometry.arrivalDirection(of: line.reversed(), span: headLength), length: headLength, halfWidth: headHalfWidth, lineWidth: width, color: color, in: &layer)
    }

    private static func drawHead(
        _ head: ArrowHead,
        tip: CGPoint,
        direction: CGVector,
        length: CGFloat,
        halfWidth: CGFloat,
        lineWidth: CGFloat,
        color: Color,
        in layer: inout GraphicsContext
    ) {
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let neck = CGPoint(x: tip.x - direction.dx * length, y: tip.y - direction.dy * length)
        func point(_ base: CGPoint, along: CGFloat = 0, across: CGFloat = 0) -> CGPoint {
            CGPoint(
                x: base.x + direction.dx * along + normal.dx * across,
                y: base.y + direction.dy * along + normal.dy * across
            )
        }

        switch head {
        case .filled:
            // A swept head with a slight notch at the back, softened at the corners.
            var path = Path()
            path.move(to: tip)
            path.addLine(to: point(neck, across: halfWidth))
            path.addLine(to: point(neck, along: length * 0.2))
            path.addLine(to: point(neck, across: -halfWidth))
            path.closeSubpath()
            layer.fill(path, with: .color(color))
            layer.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(lineWidth * 0.3, 1), lineJoin: .round))
        case .open:
            var path = Path()
            path.move(to: point(neck, across: halfWidth))
            path.addLine(to: tip)
            path.addLine(to: point(neck, across: -halfWidth))
            layer.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        case .circle:
            let radius = max(halfWidth * 0.62, lineWidth)
            layer.fill(Path(ellipseIn: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        case .bar:
            var path = Path()
            path.move(to: point(tip, across: halfWidth))
            path.addLine(to: point(tip, across: -halfWidth))
            layer.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        case .none:
            break
        }
    }

    /// A filled outline that widens smoothly from tail to tip, mitred at corners.
    static func taperedPath(_ line: [CGPoint], from startWidth: CGFloat, to endWidth: CGFloat) -> Path {
        let total = max(ArrowGeometry.length(of: line), 0.001)
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        var travelled: CGFloat = 0

        for index in line.indices {
            if index > 0 {
                travelled += hypot(line[index].x - line[index - 1].x, line[index].y - line[index - 1].y)
            }
            let half = (startWidth + (endWidth - startWidth) * travelled / total) / 2
            let (normal, miter) = vertexNormal(line, at: index)
            let offset = half * miter
            left.append(CGPoint(x: line[index].x + normal.dx * offset, y: line[index].y + normal.dy * offset))
            right.append(CGPoint(x: line[index].x - normal.dx * offset, y: line[index].y - normal.dy * offset))
        }

        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    private static func vertexNormal(_ line: [CGPoint], at index: Int) -> (CGVector, CGFloat) {
        func segmentNormal(_ a: CGPoint, _ b: CGPoint) -> CGVector? {
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = hypot(dx, dy)
            guard length > 0.0001 else { return nil }
            return CGVector(dx: -dy / length, dy: dx / length)
        }
        let before = index > 0 ? segmentNormal(line[index - 1], line[index]) : nil
        let after = index < line.count - 1 ? segmentNormal(line[index], line[index + 1]) : nil
        guard let first = before ?? after else { return (CGVector(dx: 0, dy: 1), 1) }
        let second = after ?? first
        var average = CGVector(dx: first.dx + second.dx, dy: first.dy + second.dy)
        let length = hypot(average.dx, average.dy)
        guard length > 0.0001 else { return (second, 1) }
        average = CGVector(dx: average.dx / length, dy: average.dy / length)
        let cosine = average.dx * second.dx + average.dy * second.dy
        return (average, 1 / max(cosine, 0.35))
    }

    // MARK: Shapes and strokes

    private static func shapePath(_ kind: ShapeKind, in rect: CGRect, cornerRadius: CGFloat) -> Path {
        switch kind {
        case .ellipse:
            Path(ellipseIn: rect)
        case .rectangle:
            Path(roundedRect: rect, cornerRadius: max(0, min(cornerRadius, rect.width / 2, rect.height / 2)), style: .continuous)
        }
    }

    private static func drawShape(_ mark: Annotation, in layer: inout GraphicsContext) {
        let style = mark.style
        let color = style.color.swiftUIColor
        let path = shapePath(style.shape, in: mark.rect, cornerRadius: style.cornerRadius)
        switch style.fill {
        case .solid:
            layer.fill(path, with: .color(color))
        case .translucent:
            layer.fill(path, with: .color(color.opacity(0.22)))
        case .none:
            break
        }
        guard style.fill != .solid, style.lineWidth > 0 else { return }
        layer.stroke(path, with: .color(color), style: StrokeStyle(
            lineWidth: style.lineWidth,
            lineCap: style.dashed ? .round : .butt,
            lineJoin: .round,
            dash: style.dashed ? [style.lineWidth * 1.2, style.lineWidth * 2.4] : []
        ))
    }

    private static func drawPen(_ mark: Annotation, in layer: inout GraphicsContext) {
        layer.stroke(
            smoothPath(through: mark.points),
            with: .color(mark.style.color.swiftUIColor),
            style: StrokeStyle(lineWidth: mark.style.lineWidth, lineCap: .round, lineJoin: .round, dash: mark.style.dashed ? [mark.style.lineWidth * 1.2, mark.style.lineWidth * 2.4] : [])
        )
    }

    private static func drawHighlighter(_ mark: Annotation, in layer: inout GraphicsContext) {
        let color = mark.style.color.swiftUIColor
        if mark.isStraightStroke {
            // A straight stroke gets crisp square ends, like a real marker pulled along a ruler.
            var path = Path()
            path.move(to: mark.points[0])
            path.addLine(to: mark.points[1])
            layer.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: mark.style.lineWidth, lineCap: .butt))
        } else {
            layer.stroke(smoothPath(through: mark.points), with: .color(color), style: StrokeStyle(lineWidth: mark.style.lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Text and counters

    static func font(for style: MarkStyle) -> Font {
        let weight: Font.Weight = switch style.weight {
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
        let design: Font.Design = switch style.font {
        case .rounded: .rounded
        case .system: .default
        case .monospaced: .monospaced
        case .serif: .serif
        }
        return .system(size: style.fontSize, weight: weight, design: design)
    }

    private static func drawText(_ mark: Annotation, in layer: inout GraphicsContext) {
        let style = mark.style
        let color = style.color.swiftUIColor
        let font = font(for: style)
        let size = TextMetrics.size(of: mark.text, style: style)
        let rect = CGRect(origin: mark.start, size: size)
        func text(_ fill: Color) -> Text { Text(mark.text).font(font).foregroundStyle(fill) }

        switch style.textStyle {
        case .plain:
            layer.draw(text(color), in: rect)
        case .outlined:
            let outline: Color = style.color.prefersLightContent ? .white : .black
            let radius = max(style.fontSize * 0.07, 1)
            let resolved = layer.resolve(text(outline))
            for step in 0..<16 {
                let angle = Double(step) / 16 * 2 * .pi
                layer.draw(resolved, in: rect.offsetBy(dx: cos(angle) * radius, dy: sin(angle) * radius))
            }
            layer.draw(text(color), in: rect)
        case .label:
            let padding = style.fontSize * 0.32
            let background = rect.insetBy(dx: -padding * 1.15, dy: -padding * 0.55)
            layer.fill(Path(roundedRect: background, cornerRadius: padding * 1.4, style: .continuous), with: .color(color))
            layer.draw(text(style.color.prefersLightContent ? .white : .black), in: rect)
        }
    }

    private static func drawCounter(_ mark: Annotation, in layer: inout GraphicsContext) {
        let style = mark.style
        let color = style.color.swiftUIColor
        let radius = style.counterRadius
        let circle = Path(ellipseIn: CGRect(x: mark.start.x - radius, y: mark.start.y - radius, width: radius * 2, height: radius * 2))
        let numberColor: Color
        switch style.counterStyle {
        case .filled:
            layer.fill(circle, with: .color(color))
            layer.stroke(circle, with: .color(.white.opacity(0.95)), lineWidth: max(radius * 0.12, 1.5))
            numberColor = style.color.prefersLightContent ? .white : .black
        case .ring:
            layer.fill(circle, with: .color(.white))
            layer.stroke(circle, with: .color(color), lineWidth: max(radius * 0.2, 2))
            numberColor = color
        }
        let number = Text("\(mark.number)")
            .font(.system(size: style.fontSize * 0.82, weight: .bold, design: .rounded))
            .foregroundStyle(numberColor)
        layer.draw(number, at: mark.start, anchor: .center)
    }

    // MARK: Redaction

    private static func drawRedaction(_ mark: Annotation, redacted: Redactor, in layer: inout GraphicsContext) {
        let style = mark.style
        let path = shapePath(style.shape, in: mark.rect, cornerRadius: style.cornerRadius)
        switch style.redaction {
        case .solid:
            layer.fill(path, with: .color(style.color.swiftUIColor))
        case .blur, .pixelate:
            guard let image = redacted(style.redaction, style.strength) else { return }
            var clipped = layer
            clipped.clip(to: path)
            clipped.draw(Image(decorative: image, scale: 1), in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    /// A curve through freehand points, smoothed with midpoint quadratics.
    static func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            if points.count == 1 {
                path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
            }
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 1..<points.count - 1 {
            let current = points[index]
            let next = points[index + 1]
            path.addQuadCurve(to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2), control: current)
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }

    // MARK: Export

    /// Renders the finished image at full resolution, cropped if a crop is set.
    static func export(_ document: EditorDocument) -> CGImage? {
        let size = document.imageSize
        let annotations = document.annotations
        let image = document.image

        // Make every redaction layer up front, so rendering only reads values.
        var layers: [String: CGImage] = [:]
        for mark in annotations where mark.tool == .redact {
            let key = "\(mark.style.redaction.rawValue)-\(mark.style.strength)"
            if layers[key] == nil, let layer = document.redactedImageNow(mark.style.redaction, strength: mark.style.strength) {
                layers[key] = layer
            }
        }

        let renderer = ImageRenderer(content:
            Canvas { context, _ in
                draw(image: image, annotations: annotations, redacted: { layers["\($0.rawValue)-\($1)"] }, in: &context)
            }
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = 1
        renderer.isOpaque = false
        guard let rendered = renderer.cgImage else { return nil }
        guard let crop = document.cropRect?.integral, crop.width >= 1, crop.height >= 1 else { return rendered }
        return rendered.cropping(to: crop) ?? rendered
    }
}

extension RGBAColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
