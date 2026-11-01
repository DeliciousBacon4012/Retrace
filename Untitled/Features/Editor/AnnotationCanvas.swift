import AppKit
import SwiftUI

/// The screenshot with its marks, taking pointer input for the current tool.
/// Each mark is its own layer, so marks can spring in and fade out on their own.
struct AnnotationCanvas: View {
    @Bindable var document: EditorDocument

    @State private var isPointerDown = false
    @State private var isHovering = false
    @State private var magnifyStart: CGFloat?
    @State private var scrollMonitor: Any?

    var body: some View {
        GeometryReader { proxy in
            let layout = CanvasLayout(document: document, in: proxy.size)
            let redactor: AnnotationRenderer.Redactor = { document.redactedImage($0, strength: $1) }

            ZStack(alignment: .topLeading) {
                // A soft shadow under exactly the visible part of the image.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    .frame(width: layout.visibleFrame.width, height: layout.visibleFrame.height)
                    .offset(x: layout.visibleFrame.minX, y: layout.visibleFrame.minY)

                ZStack(alignment: .topLeading) {
                    Image(decorative: document.image, scale: 1)
                        .resizable()
                        .interpolation(layout.factor * document.scale >= 2 ? .none : .high)
                        .frame(width: layout.imageFrame.width, height: layout.imageFrame.height)
                        .offset(x: layout.imageFrame.minX, y: layout.imageFrame.minY)
                        .accessibilityLabel("Screenshot")

                    ForEach(document.annotations) { mark in
                        MarkLayer(mark: mark, layout: layout, redactor: redactor)
                            .equatable()
                            .transition(.scale(scale: 0.6, anchor: layout.anchor(for: mark.center)).combined(with: .opacity))
                    }

                    if let draft = document.draft {
                        MarkLayer(mark: draft, layout: layout, redactor: redactor)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .mask(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: layout.visibleFrame.width, height: layout.visibleFrame.height)
                        .offset(x: layout.visibleFrame.minX, y: layout.visibleFrame.minY)
                }

                if document.tool == .crop {
                    CropShade(cropRect: document.cropRect, layout: layout)
                        .allowsHitTesting(false)
                }

                MarkSelectionOverlay(document: document, layout: layout)
                    .allowsHitTesting(false)

                if document.isPickingTextArea {
                    TextAreaShade(area: document.textArea, layout: layout)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if let id = document.editingTextID, let mark = document.annotations.first(where: { $0.id == id }) {
                    TextMarkEditor(document: document, mark: mark, layout: layout)
                        .id(id)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(.rect)
            .gesture(drawingGesture(layout: layout))
            .simultaneousGesture(magnifyGesture(layout: layout))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    isHovering = true
                    updateCursor(at: location, layout: layout)
                case .ended:
                    isHovering = false
                    NSCursor.arrow.set()
                }
            }
            .onAppear { installScrollMonitor(fitFactor: layout.fitFactor) }
            .onDisappear { removeScrollMonitor() }
        }
        .clipped()
    }

    // MARK: Gestures

    private func drawingGesture(layout: CanvasLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if document.isPickingTextArea {
                    if !isPointerDown {
                        isPointerDown = true
                        document.textAreaDown(at: layout.imagePoint(for: value.startLocation))
                    }
                    document.textAreaDragged(to: layout.imagePoint(for: value.location))
                    return
                }
                if !isPointerDown {
                    isPointerDown = true
                    document.pointerDown(
                        at: layout.imagePoint(for: value.startLocation),
                        tolerance: 7 / layout.factor,
                        clickCount: NSApp.currentEvent?.clickCount ?? 1
                    )
                }
                if value.translation != .zero {
                    document.pointerDragged(
                        to: layout.imagePoint(for: value.location),
                        constrained: NSEvent.modifierFlags.contains(.shift),
                        freehand: NSEvent.modifierFlags.contains(.option)
                    )
                }
            }
            .onEnded { _ in
                isPointerDown = false
                if document.isPickingTextArea {
                    document.textAreaUp()
                } else {
                    document.pointerUp()
                }
            }
    }

    private func magnifyGesture(layout: CanvasLayout) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = magnifyStart ?? document.currentZoom(fitFactor: layout.fitFactor)
                magnifyStart = start
                document.zoom = min(max(start * value.magnification, 0.1), 8)
            }
            .onEnded { _ in
                magnifyStart = nil
            }
    }

    /// Two-finger scrolling pans a zoomed image; with ⌘ held it zooms instead.
    private func installScrollMonitor(fitFactor: CGFloat) {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [document] event in
            guard isHovering, !document.isPointerOverZoomControl else { return event }
            if event.modifierFlags.contains(.command) {
                let current = document.currentZoom(fitFactor: fitFactor)
                document.zoom = min(max(current * (1 + event.scrollingDeltaY * 0.01), 0.1), 8)
                return nil
            }
            guard document.zoom != nil else { return event }
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            document.pan.width += event.scrollingDeltaX * multiplier
            document.pan.height += event.scrollingDeltaY * multiplier
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
    }

    // MARK: Cursor

    private func updateCursor(at location: CGPoint, layout: CanvasLayout) {
        guard !isPointerDown else { return }
        if document.isPickingTextArea {
            NSCursor.crosshair.set()
            return
        }
        let point = layout.imagePoint(for: location)
        let tolerance = 7 / layout.factor

        if document.tool != .crop {
            if let mark = document.selected, let handle = MarkHandle.hit(at: point, on: mark, tolerance: tolerance * 1.5) {
                cursor(for: handle).set()
                return
            }
            if let hit = document.annotations.last(where: { $0.contains(point, tolerance: tolerance) }) {
                (hit.tool == .text && document.tool == .text ? NSCursor.iBeam : NSCursor.openHand).set()
                return
            }
        }

        if document.tool == .crop, let box = document.cropBox {
            if let handle = MarkHandle.hit(at: point, on: box, tolerance: tolerance * 1.8) {
                cursor(for: handle).set()
                return
            }
            if box.rect.contains(point) {
                NSCursor.openHand.set()
                return
            }
        }

        switch document.tool {
        case .select: NSCursor.arrow.set()
        case .text: NSCursor.iBeam.set()
        default: NSCursor.crosshair.set()
        }
    }

    private func cursor(for handle: MarkHandle) -> NSCursor {
        switch handle {
        case .corner(0): .frameResize(position: .topLeft, directions: .all)
        case .corner(1): .frameResize(position: .topRight, directions: .all)
        case .corner(2): .frameResize(position: .bottomRight, directions: .all)
        case .corner: .frameResize(position: .bottomLeft, directions: .all)
        case .edge(0): .frameResize(position: .top, directions: .all)
        case .edge(1): .frameResize(position: .right, directions: .all)
        case .edge(2): .frameResize(position: .bottom, directions: .all)
        case .edge: .frameResize(position: .left, directions: .all)
        case .start, .end, .bend: .crosshair
        }
    }
}

/// Converts between the view's points and the image's pixels, for the current zoom and pan.
nonisolated struct CanvasLayout: Equatable {
    let factor: CGFloat
    let fitFactor: CGFloat
    let origin: CGPoint
    let viewSize: CGSize
    let imageSize: CGSize

    @MainActor
    init(document: EditorDocument, in available: CGSize) {
        self.init(imageSize: document.imageSize, scale: document.scale, zoom: document.zoom, pan: document.pan, focus: document.visibleRect, in: available)
    }

    /// `focus` is the part of the image to frame, such as a finished crop. `nil` frames all of it.
    init(imageSize: CGSize, scale: CGFloat, zoom: CGFloat?, pan: CGSize, focus: CGRect? = nil, in available: CGSize) {
        let padding: CGFloat = 36
        let width = max(available.width - padding * 2, 1)
        let height = max(available.height - padding * 2, 1)
        let shown = focus ?? CGRect(origin: .zero, size: imageSize)
        // Fit the window, but never blow a small screenshot up past its real size.
        let fit = min(width / max(shown.width, 1), height / max(shown.height, 1), 1 / scale)
        fitFactor = fit
        factor = zoom.map { $0 / scale } ?? fit
        self.imageSize = imageSize
        self.focus = focus
        viewSize = available
        origin = CGPoint(
            x: (available.width - shown.width * factor) / 2 - shown.minX * factor + pan.width,
            y: (available.height - shown.height * factor) / 2 - shown.minY * factor + pan.height
        )
    }

    /// The finished crop, if the canvas is framed to one.
    let focus: CGRect?

    /// The part of the view that shows image: the whole image, or just the crop.
    var visibleFrame: CGRect {
        focus.map(viewRect(for:)) ?? imageFrame
    }

    var imageFrame: CGRect {
        CGRect(origin: origin, size: CGSize(width: imageSize.width * factor, height: imageSize.height * factor))
    }

    func imagePoint(for viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: (viewPoint.x - origin.x) / factor, y: (viewPoint.y - origin.y) / factor)
    }

    func viewPoint(for imagePoint: CGPoint) -> CGPoint {
        CGPoint(x: imagePoint.x * factor + origin.x, y: imagePoint.y * factor + origin.y)
    }

    func viewRect(for imageRect: CGRect) -> CGRect {
        CGRect(origin: viewPoint(for: imageRect.origin), size: CGSize(width: imageRect.width * factor, height: imageRect.height * factor))
    }

    /// Where an image point sits, as a fraction of the view, for scaling from that spot.
    func anchor(for imagePoint: CGPoint) -> UnitPoint {
        let point = viewPoint(for: imagePoint)
        return UnitPoint(x: point.x / max(viewSize.width, 1), y: point.y / max(viewSize.height, 1))
    }
}

/// One mark, drawn on its own layer. It only redraws when the mark or the layout changes.
private struct MarkLayer: View, Equatable {
    let mark: Annotation
    let layout: CanvasLayout
    let redactor: AnnotationRenderer.Redactor

    nonisolated static func == (lhs: MarkLayer, rhs: MarkLayer) -> Bool {
        lhs.mark == rhs.mark && lhs.layout == rhs.layout
    }

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: layout.origin.x, y: layout.origin.y)
            context.scaleBy(x: layout.factor, y: layout.factor)
            context.clip(to: Path(CGRect(origin: .zero, size: layout.imageSize)))
            AnnotationRenderer.draw(mark, redacted: redactor, in: &context)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// While choosing an area to read text from: the image dims a little, and the area being
/// dragged shows at full brightness with an accent outline.
private struct TextAreaShade: View {
    let area: CGRect?
    let layout: CanvasLayout

    var body: some View {
        Canvas { context, _ in
            var outside = Path(layout.visibleFrame)
            if let area {
                let frame = layout.viewRect(for: area)
                outside.addRect(frame)
                context.fill(outside, with: .color(.black.opacity(0.35)), style: FillStyle(eoFill: true))
                context.stroke(Path(frame), with: .color(.accentColor), lineWidth: 1.5)
            } else {
                context.fill(outside, with: .color(.black.opacity(0.18)))
            }
        }
    }
}

/// Dims everything outside the crop and outlines it with a thirds grid.
private struct CropShade: View {
    let cropRect: CGRect?
    let layout: CanvasLayout

    var body: some View {
        if let cropRect {
            let frame = layout.viewRect(for: cropRect)
            Canvas { context, _ in
                var outside = Path(layout.imageFrame)
                outside.addRect(frame)
                context.fill(outside, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                var grid = Path()
                for step in 1...2 {
                    let x = frame.minX + frame.width * CGFloat(step) / 3
                    let y = frame.minY + frame.height * CGFloat(step) / 3
                    grid.move(to: CGPoint(x: x, y: frame.minY))
                    grid.addLine(to: CGPoint(x: x, y: frame.maxY))
                    grid.move(to: CGPoint(x: frame.minX, y: y))
                    grid.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
                context.stroke(grid, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
                context.stroke(Path(frame), with: .color(.white), lineWidth: 1.5)
                // Corner brackets show the crop can be grabbed and resized.
                let arm = min(18, frame.width / 3, frame.height / 3)
                var corners = Path()
                for (x, y, dx, dy) in [(frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
                                       (frame.maxX, frame.maxY, -1.0, -1.0), (frame.minX, frame.maxY, 1.0, -1.0)] {
                    corners.move(to: CGPoint(x: x + dx * arm, y: y))
                    corners.addLine(to: CGPoint(x: x, y: y))
                    corners.addLine(to: CGPoint(x: x, y: y + dy * arm))
                }
                context.stroke(corners, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            .transition(.opacity)
        }
    }
}

/// The selected mark's outline and grab handles.
private struct MarkSelectionOverlay: View {
    let document: EditorDocument
    let layout: CanvasLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let mark = document.selected {
                let handles = MarkHandle.handles(for: mark)
                if handles.isEmpty || mark.tool.isBoxShaped {
                    let padding = handles.isEmpty ? mark.style.lineWidth / 2 * layout.factor + 6 : 0
                    let frame = layout.viewRect(for: mark.bounds).insetBy(dx: -padding, dy: -padding)
                    RoundedRectangle(cornerRadius: handles.isEmpty ? 5 : 0)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.25, dash: handles.isEmpty ? [5, 3] : []))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
                if mark.tool == .arrow, mark.style.route == .curved {
                    BendGuide(start: layout.viewPoint(for: mark.start), bend: layout.viewPoint(for: mark.resolvedControl), end: layout.viewPoint(for: mark.end))
                }
                ForEach(handles, id: \.0) { handle, point in
                    HandleDot(isBend: handle == .bend)
                        .position(layout.viewPoint(for: point))
                }
            }
        }
        .frame(width: layout.viewSize.width, height: layout.viewSize.height, alignment: .topLeading)
        .transition(.opacity)
    }
}

private struct BendGuide: View {
    let start: CGPoint
    let bend: CGPoint
    let end: CGPoint

    var body: some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: bend)
            path.addLine(to: end)
        }
        .stroke(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }
}

private struct HandleDot: View {
    let isBend: Bool

    var body: some View {
        Circle()
            .fill(isBend ? Color.accentColor : .white)
            .overlay {
                Circle().strokeBorder(isBend ? .white : Color.accentColor, lineWidth: 1.5)
            }
            .frame(width: 11, height: 11)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .transition(.scale.combined(with: .opacity))
    }
}

/// A text field over a text mark while it's typed into. The mark itself draws the text
/// underneath in its real style, so the field only shows the caret and selection.
private struct TextMarkEditor: View {
    let document: EditorDocument
    let mark: Annotation
    let layout: CanvasLayout

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let position = layout.viewPoint(for: mark.start)
        let style = mark.style.scaled(by: layout.factor)
        let size = TextMetrics.size(of: text.isEmpty ? "M" : text + "M", style: style)

        TextField("", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(AnnotationRenderer.font(for: style))
            .foregroundStyle(text.isEmpty ? mark.style.color.swiftUIColor.opacity(0.5) : .clear)
            .tint(mark.style.color.swiftUIColor)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .focused($isFocused)
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
            .onChange(of: isFocused) { _, focused in
                if !focused { document.finishTextEditing() }
            }
    }
}
