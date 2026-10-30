import SwiftUI

/// Draws a screenshot and its marks. The editor canvas and the exported image
/// both use this, so what you see is exactly what gets saved.
enum AnnotationRenderer {
    static func draw(
        image: CGImage,
        annotations: [Annotation],
        redacted: (AnnotationTool) -> CGImage?,
        in context: inout GraphicsContext
    ) {
        let size = CGSize(width: image.width, height: image.height)
        context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
        for annotation in annotations {
            draw(annotation, redacted: redacted, in: &context)
        }
    }

    static func draw(_ mark: Annotation, redacted: (AnnotationTool) -> CGImage?, in context: inout GraphicsContext) {
        let color = Color(.sRGB, red: mark.color.red, green: mark.color.green, blue: mark.color.blue, opacity: mark.color.opacity)
        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.28), radius: max(mark.lineWidth * 0.6, 2), y: max(mark.lineWidth * 0.25, 1)))

        switch mark.tool {
        case .arrow:
            shadowed.fill(arrowPath(from: mark.start, to: mark.end, width: mark.lineWidth), with: .color(color))

        case .line:
            var path = Path()
            path.move(to: mark.start)
            path.addLine(to: mark.end)
            shadowed.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: mark.lineWidth, lineCap: .round))

        case .rectangle, .ellipse:
            let rect = mark.bounds
            let shape: Path = mark.tool == .rectangle
                ? Path(roundedRect: rect, cornerRadius: min(mark.lineWidth * 1.5, rect.width / 2, rect.height / 2), style: .continuous)
                : Path(ellipseIn: rect)
            if mark.isFilled {
                shadowed.fill(shape, with: .color(color))
            } else {
                shadowed.stroke(shape, with: .color(color), style: StrokeStyle(lineWidth: mark.lineWidth, lineJoin: .round))
            }

        case .pen:
            shadowed.stroke(smoothPath(through: mark.points), with: .color(color), style: StrokeStyle(lineWidth: mark.lineWidth, lineCap: .round, lineJoin: .round))

        case .highlighter:
            var layer = context
            layer.blendMode = .multiply
            layer.opacity = 0.45
            layer.stroke(smoothPath(through: mark.points), with: .color(color), style: StrokeStyle(lineWidth: mark.lineWidth, lineCap: .butt, lineJoin: .round))

        case .text:
            let text = Text(mark.text)
                .font(.system(size: mark.fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            shadowed.draw(text, at: mark.start, anchor: .topLeading)

        case .counter:
            let radius = mark.counterRadius
            let circle = Path(ellipseIn: CGRect(x: mark.start.x - radius, y: mark.start.y - radius, width: radius * 2, height: radius * 2))
            shadowed.fill(circle, with: .color(color))
            context.stroke(circle, with: .color(.white.opacity(0.9)), lineWidth: max(radius * 0.12, 1.5))
            let number = Text("\(mark.number)")
                .font(.system(size: mark.fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(mark.color.prefersLightContent ? Color.white : Color.black)
            context.draw(number, at: mark.start, anchor: .center)

        case .blur, .pixelate:
            guard let layer = redacted(mark.tool) else { return }
            var clipped = context
            clipped.clip(to: Path(mark.bounds))
            clipped.draw(Image(decorative: layer, scale: 1), in: CGRect(x: 0, y: 0, width: layer.width, height: layer.height))

        case .select, .crop:
            break
        }
    }

    /// A tapered arrow: thin at the tail, full width at the head.
    static func arrowPath(from start: CGPoint, to end: CGPoint, width: CGFloat) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return Path() }
        let ux = dx / length
        let uy = dy / length
        let nx = -uy
        let ny = ux

        let headLength = min(max(width * 4.2, 14), length * 0.6)
        let headHalfWidth = max(width * 2.1, 7)
        let shaftHalfWidth = width / 2
        let tailHalfWidth = width * 0.15
        let neck = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)

        func point(_ base: CGPoint, _ offset: CGFloat) -> CGPoint {
            CGPoint(x: base.x + nx * offset, y: base.y + ny * offset)
        }

        var path = Path()
        path.move(to: point(start, tailHalfWidth))
        path.addLine(to: point(neck, shaftHalfWidth))
        path.addLine(to: point(neck, headHalfWidth))
        path.addLine(to: end)
        path.addLine(to: point(neck, -headHalfWidth))
        path.addLine(to: point(neck, -shaftHalfWidth))
        path.addLine(to: point(start, -tailHalfWidth))
        path.closeSubpath()
        return path
    }

    /// A curve through freehand points, smoothed with midpoint quadratics.
    static func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 1..<points.count - 1 {
            let current = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }

    /// Renders the finished image at full resolution, cropped if a crop is set.
    static func export(_ document: EditorDocument) -> CGImage? {
        let size = document.imageSize
        let annotations = document.annotations
        let image = document.image
        let blur = document.redactedImage(for: .blur)
        let pixelate = document.redactedImage(for: .pixelate)
        let renderer = ImageRenderer(content:
            Canvas { context, _ in
                draw(image: image, annotations: annotations, redacted: { $0 == .blur ? blur : pixelate }, in: &context)
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
