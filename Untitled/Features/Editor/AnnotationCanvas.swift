import AppKit
import SwiftUI

/// The screenshot with its marks, scaled to fit, taking pointer input for the current tool.
struct AnnotationCanvas: View {
    @Bindable var document: EditorDocument
    @State private var isPointerDown = false

    var body: some View {
        GeometryReader { proxy in
            let layout = CanvasLayout(imageSize: document.imageSize, in: proxy.size)

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.translateBy(x: layout.origin.x, y: layout.origin.y)
                    context.scaleBy(x: layout.factor, y: layout.factor)
                    AnnotationRenderer.draw(
                        image: document.image,
                        annotations: document.visibleAnnotations.filter { $0.id != document.editingTextID },
                        redacted: document.redactedImage(for:),
                        in: &context
                    )
                    drawCropShade(in: &context)
                    drawSelection(in: &context, factor: layout.factor)
                }
                .clipShape(.rect(cornerRadius: 6))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)

                if let id = document.editingTextID, let mark = document.annotations.first(where: { $0.id == id }) {
                    TextMarkEditor(document: document, mark: mark, layout: layout)
                }
            }
            .contentShape(.rect)
            .gesture(drawingGesture(layout: layout))
            .onContinuousHover { phase in
                updateCursor(phase)
            }
        }
    }

    private func drawingGesture(layout: CanvasLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isPointerDown {
                    isPointerDown = true
                    document.pointerDown(at: layout.imagePoint(for: value.startLocation))
                }
                if value.translation != .zero {
                    document.pointerDragged(
                        to: layout.imagePoint(for: value.location),
                        constrained: NSEvent.modifierFlags.contains(.shift)
                    )
                }
            }
            .onEnded { _ in
                isPointerDown = false
                document.pointerUp()
            }
    }

    private func drawCropShade(in context: inout GraphicsContext) {
        guard let crop = document.cropRect else { return }
        var outside = Path(CGRect(origin: .zero, size: document.imageSize))
        outside.addRect(crop)
        context.fill(outside, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
        context.stroke(Path(crop), with: .color(.white), style: StrokeStyle(lineWidth: 1.5 * document.scale, dash: [6 * document.scale, 4 * document.scale]))
    }

    private func drawSelection(in context: inout GraphicsContext, factor: CGFloat) {
        guard document.tool == .select, let mark = document.selected else { return }
        let inset = -(mark.lineWidth / 2 + 6 / factor)
        let rect = mark.bounds.insetBy(dx: inset, dy: inset)
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 4 / factor),
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 1.5 / factor, dash: [5 / factor, 3 / factor])
        )
    }

    private func updateCursor(_ phase: HoverPhase) {
        switch phase {
        case .active:
            switch document.tool {
            case .select: NSCursor.arrow.set()
            case .text: NSCursor.iBeam.set()
            default: NSCursor.crosshair.set()
            }
        case .ended:
            NSCursor.arrow.set()
        }
    }
}

/// Converts between the view's points and the image's pixels.
struct CanvasLayout {
    let factor: CGFloat
    let origin: CGPoint

    init(imageSize: CGSize, in available: CGSize) {
        let padding: CGFloat = 24
        let width = max(available.width - padding * 2, 1)
        let height = max(available.height - padding * 2, 1)
        let fit = min(width / max(imageSize.width, 1), height / max(imageSize.height, 1))
        factor = min(fit, 1)
        origin = CGPoint(
            x: (available.width - imageSize.width * factor) / 2,
            y: (available.height - imageSize.height * factor) / 2
        )
    }

    func imagePoint(for viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: (viewPoint.x - origin.x) / factor, y: (viewPoint.y - origin.y) / factor)
    }

    func viewPoint(for imagePoint: CGPoint) -> CGPoint {
        CGPoint(x: imagePoint.x * factor + origin.x, y: imagePoint.y * factor + origin.y)
    }
}

/// A text field placed over a text mark while it's being typed.
private struct TextMarkEditor: View {
    let document: EditorDocument
    let mark: Annotation
    let layout: CanvasLayout

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let position = layout.viewPoint(for: mark.start)
        let color = Color(.sRGB, red: mark.color.red, green: mark.color.green, blue: mark.color.blue, opacity: mark.color.opacity)

        let fontSize = mark.fontSize * layout.factor
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = max(lines.map(\.count).max() ?? 0, 4) + 2

        TextField("Text", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            // An explicit size keeps clicks outside the text going to the canvas.
            .frame(width: CGFloat(longest) * fontSize * 0.62, height: CGFloat(max(lines.count, 1)) * fontSize * 1.3, alignment: .topLeading)
            .focused($isFocused)
            // Padding, not offset, so the field's real frame sits under the text.
            .padding(.leading, position.x)
            .padding(.top, position.y)
            .onAppear {
                text = mark.text
                isFocused = true
            }
            .onChange(of: text) { _, newValue in
                document.updateText(newValue, for: mark.id)
            }
            .onSubmit { document.finishTextEditing() }
            .onExitCommand { document.finishTextEditing() }
    }
}
