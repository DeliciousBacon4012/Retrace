import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import OSLog
import SwiftUI

/// The state of one editor window: the screenshot, its marks, the selection, the crop,
/// and undo history. All positions are in image pixels.
@Observable
final class EditorDocument {
    let image: CGImage
    /// Pixels per point of the original capture, used to size new marks sensibly.
    let scale: CGFloat
    private(set) var fileURL: URL?

    private(set) var annotations: [Annotation] = []
    private(set) var cropRect: CGRect?
    private(set) var selectedID: Annotation.ID?
    /// The text mark being typed into, if any.
    private(set) var editingTextID: Annotation.ID?
    /// A mark being drawn right now, not yet in `annotations`.
    private(set) var draft: Annotation?
    private(set) var hasUnsavedChanges = false

    var tool: EditorTool = .arrow {
        didSet {
            guard tool != oldValue else { return }
            finishTextEditing()
            if tool == .crop { select(nil) }
        }
    }

    /// The zoom, as a fraction of the image's actual size. `nil` fits the image to the window.
    var zoom: CGFloat?
    /// How far the image is scrolled from center, in view points.
    var pan: CGSize = .zero

    /// The last style used with each tool, so new marks look like the previous one.
    private(set) var toolStyles: [EditorTool: MarkStyle]

    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    @ObservationIgnored private var gesture: Gesture?
    @ObservationIgnored private var gestureSnapshot: Snapshot?
    @ObservationIgnored private var textEditSnapshot: Snapshot?
    @ObservationIgnored private var lastStyleEdit: (id: Annotation.ID?, tool: EditorTool, date: Date)?
    @ObservationIgnored private var redactionLayers: [String: CGImage] = [:]
    @ObservationIgnored private let styleStore: EditorStyleStore

    private struct Snapshot: Equatable {
        let annotations: [Annotation]
        let cropRect: CGRect?
    }

    private enum Gesture {
        case drawing
        case moving(last: CGPoint)
        case handle(MarkHandle)
        case cropping(origin: CGPoint)
    }

    init(image: CGImage, scale: CGFloat, fileURL: URL?, annotations: [Annotation] = [], styleStore: EditorStyleStore = EditorStyleStore()) {
        self.image = image
        self.scale = max(scale, 1)
        self.fileURL = fileURL
        self.annotations = annotations
        self.styleStore = styleStore
        toolStyles = styleStore.load(scale: max(scale, 1))
    }

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selected: Annotation? { annotations.first { $0.id == selectedID } }

    /// The tool whose settings the inspector shows: the selected mark's, or the current tool's.
    var inspectedTool: EditorTool { selected?.tool ?? tool }

    /// The style the inspector edits. Changing it restyles the selected mark and becomes
    /// that tool's style for the next mark.
    var style: MarkStyle {
        get { selected?.style ?? style(for: tool) }
        set { applyStyle(newValue) }
    }

    func style(for tool: EditorTool) -> MarkStyle {
        toolStyles[tool] ?? MarkStyle.defaults(for: tool, scale: scale)
    }

    /// Puts the inspected tool back to its original look, including the selected mark.
    func resetStyle() {
        let tool = inspectedTool
        style = MarkStyle.defaults(for: tool, scale: scale)
    }

    // MARK: Pointer input, in image pixels

    /// Starts a click or drag. `tolerance` is how far, in pixels, a click may miss a thin mark.
    func pointerDown(at point: CGPoint, tolerance: CGFloat, clickCount: Int) {
        finishTextEditing()
        gestureSnapshot = snapshot
        if tool == .crop {
            gesture = .cropping(origin: clamp(point))
            return
        }

        // A handle on the selected mark wins over everything else.
        if let mark = selected, let handle = MarkHandle.hit(at: point, on: mark, tolerance: tolerance * 1.5) {
            gesture = .handle(handle)
            return
        }

        if let hit = annotations.last(where: { $0.contains(point, tolerance: tolerance) }) {
            if hit.tool == .text, clickCount >= 2 || tool == .text {
                beginEditing(hit.id)
                gesture = nil
                return
            }
            select(hit.id)
            gesture = .moving(last: point)
            return
        }

        select(nil)
        guard tool.draws else {
            gesture = nil
            return
        }

        var mark = Annotation(tool: tool, at: point, style: style(for: tool))
        switch tool {
        case .text:
            textEditSnapshot = gestureSnapshot
            withAnimation(.response) { annotations.append(mark) }
            hasUnsavedChanges = true
            select(mark.id)
            editingTextID = mark.id
            gesture = nil
        case .counter:
            mark.number = (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1
            pushUndo(gestureSnapshot)
            withAnimation(.pop) { annotations.append(mark) }
            select(mark.id)
            gesture = .moving(last: point)
            gestureSnapshot = nil
        default:
            draft = mark
            gesture = .drawing
        }
    }

    func pointerDragged(to point: CGPoint, constrained: Bool) {
        switch gesture {
        case .drawing:
            guard var mark = draft else { return }
            switch mark.tool {
            case .pen:
                if let last = mark.points.last, hypot(point.x - last.x, point.y - last.y) >= 1.5 {
                    mark.points.append(point)
                }
            case .highlighter:
                if constrained, let first = mark.points.first {
                    // Shift draws one perfectly straight stroke.
                    mark.points = [first, Geometry.snapped(from: first, to: point)]
                } else if let last = mark.points.last, hypot(point.x - last.x, point.y - last.y) >= 1.5 {
                    mark.points.append(point)
                }
            case .arrow:
                mark.end = constrained ? Geometry.snapped(from: mark.start, to: point) : point
                if mark.style.route == .curved {
                    mark.control = ArrowGeometry.defaultBend(from: mark.start, to: mark.end)
                }
            default:
                mark.end = constrained ? squared(from: mark.start, to: point) : point
            }
            draft = mark

        case .moving(let last):
            guard let index = selectedIndex else { return }
            annotations[index].move(by: CGSize(width: point.x - last.x, height: point.y - last.y))
            gesture = .moving(last: point)
            hasUnsavedChanges = true

        case .handle(let handle):
            guard let index = selectedIndex else { return }
            handle.drag(&annotations[index], to: point, constrained: constrained)
            hasUnsavedChanges = true

        case .cropping(let origin):
            cropRect = CGRect(origin: origin, size: .zero)
                .union(CGRect(origin: clamp(constrained ? squared(from: origin, to: point) : point), size: .zero))
                .intersection(CGRect(origin: .zero, size: imageSize))

        case nil:
            break
        }
    }

    func pointerUp() {
        switch gesture {
        case .drawing:
            if let mark = draft {
                draft = nil
                if !mark.isNegligible {
                    pushUndo(gestureSnapshot)
                    annotations.append(mark)
                    select(mark.id)
                }
            }
        case .cropping:
            if let crop = cropRect, crop.width < 8 || crop.height < 8 {
                cropRect = gestureSnapshot?.cropRect
            } else {
                pushUndo(gestureSnapshot)
            }
        case .moving, .handle:
            pushUndo(gestureSnapshot)
        case nil:
            break
        }
        gesture = nil
        gestureSnapshot = nil
    }

    var isDragging: Bool { gesture != nil }

    // MARK: Selection and editing

    func select(_ id: Annotation.ID?) {
        guard selectedID != id else { return }
        withAnimation(.response) { selectedID = id }
        lastStyleEdit = nil
    }

    func beginEditing(_ id: Annotation.ID) {
        select(id)
        editingTextID = id
        textEditSnapshot = snapshot
    }

    func updateText(_ text: String, for id: Annotation.ID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].text != text else { return }
        annotations[index].text = text
        hasUnsavedChanges = true
    }

    /// Ends text entry, removing the mark if nothing was typed.
    func finishTextEditing() {
        guard let id = editingTextID else { return }
        editingTextID = nil
        if let mark = annotations.first(where: { $0.id == id }), mark.isNegligible {
            withAnimation(.response) { annotations.removeAll { $0.id == id } }
            if selectedID == id { select(nil) }
        } else if let before = textEditSnapshot, before != snapshot {
            pushUndo(before)
        }
        textEditSnapshot = nil
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        pushUndo(snapshot)
        editingTextID = nil
        withAnimation(.response) {
            annotations.removeAll { $0.id == id }
        }
        select(nil)
    }

    func duplicateSelection() {
        guard var copy = selected else { return }
        pushUndo(snapshot)
        copy.id = UUID()
        let offset = 16 * scale
        copy.move(by: CGSize(width: offset, height: offset))
        if copy.tool == .counter {
            copy.number = (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1
        }
        withAnimation(.pop) { annotations.append(copy) }
        select(copy.id)
    }

    func bringSelectionToFront() {
        guard let index = selectedIndex, index < annotations.count - 1 else { return }
        pushUndo(snapshot)
        let mark = annotations.remove(at: index)
        annotations.append(mark)
    }

    func sendSelectionToBack() {
        guard let index = selectedIndex, index > 0 else { return }
        pushUndo(snapshot)
        let mark = annotations.remove(at: index)
        annotations.insert(mark, at: 0)
    }

    /// Moves the selection by whole points with the arrow keys.
    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard let index = selectedIndex else { return }
        coalescedUndo(for: annotations[index].id)
        annotations[index].move(by: CGSize(width: dx * scale, height: dy * scale))
    }

    func clearAll() {
        guard !annotations.isEmpty || cropRect != nil else { return }
        pushUndo(snapshot)
        withAnimation(.response) {
            annotations.removeAll()
            cropRect = nil
        }
        select(nil)
    }

    func resetCrop() {
        guard cropRect != nil else { return }
        pushUndo(snapshot)
        withAnimation(.response) { cropRect = nil }
    }

    /// Crops to a fixed aspect ratio, as large as fits and centered.
    func applyCropAspect(_ ratio: CGFloat) {
        let size = imageSize
        var width = size.width
        var height = width / ratio
        if height > size.height {
            height = size.height
            width = height * ratio
        }
        pushUndo(snapshot)
        withAnimation(.response) {
            cropRect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height).integral
        }
    }

    func undo() {
        finishTextEditing()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    func markSaved(to url: URL) {
        fileURL = url
        hasUnsavedChanges = false
    }

    // MARK: Zoom

    func zoomIn(fitFactor: CGFloat) { setZoom(currentZoom(fitFactor: fitFactor) * 1.25) }
    func zoomOut(fitFactor: CGFloat) { setZoom(currentZoom(fitFactor: fitFactor) / 1.25) }

    func zoomToFit() {
        withAnimation(.panel) {
            zoom = nil
            pan = .zero
        }
    }

    func zoomToActualSize() { setZoom(1) }

    /// The zoom in effect, as a fraction of actual size.
    func currentZoom(fitFactor: CGFloat) -> CGFloat {
        zoom ?? fitFactor * scale
    }

    func setZoom(_ value: CGFloat) {
        withAnimation(.panel) { zoom = min(max(value, 0.1), 8) }
    }

    // MARK: Redaction

    /// The blurred or pixelated copy of the screenshot that a redaction mark reveals.
    func redactedImage(_ redaction: Redaction, strength: Double) -> CGImage? {
        guard redaction != .solid else { return nil }
        let level = Int((min(max(strength, 0), 1) * 10).rounded())
        let key = "\(redaction.rawValue)-\(level)"
        if let cached = redactionLayers[key] { return cached }
        let layer = Self.redacted(image, redaction: redaction, level: Double(level) / 10, scale: scale)
        redactionLayers[key] = layer
        return layer
    }

    // MARK: Helpers

    private var snapshot: Snapshot { Snapshot(annotations: annotations, cropRect: cropRect) }
    private var selectedIndex: Int? { annotations.firstIndex { $0.id == selectedID } }

    private func applyStyle(_ newStyle: MarkStyle) {
        if let index = selectedIndex {
            let mark = annotations[index]
            guard mark.style != newStyle else { return }
            coalescedUndo(for: mark.id)
            annotations[index].style = newStyle
            if mark.style.route != newStyle.route, newStyle.route == .curved, annotations[index].control == nil {
                annotations[index].control = ArrowGeometry.defaultBend(from: mark.start, to: mark.end)
            }
            remember(newStyle, for: mark.tool)
        } else {
            remember(newStyle, for: tool)
        }
    }

    private func remember(_ style: MarkStyle, for tool: EditorTool) {
        toolStyles[tool] = style
        styleStore.save(toolStyles, scale: scale)
    }

    /// Records one undo step for a run of quick changes to the same mark, like dragging a slider.
    private func coalescedUndo(for id: Annotation.ID?) {
        let now = Date()
        if let last = lastStyleEdit, last.id == id, now.timeIntervalSince(last.date) < 1 {
            lastStyleEdit = (id, tool, now)
            hasUnsavedChanges = true
            return
        }
        pushUndo(snapshot)
        lastStyleEdit = (id, tool, now)
    }

    private func pushUndo(_ previous: Snapshot?) {
        guard let previous, previous != snapshot || gesture == nil else { return }
        undoStack.append(previous)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        hasUnsavedChanges = true
    }

    private func restore(_ snapshot: Snapshot) {
        withAnimation(.response) {
            annotations = snapshot.annotations
            cropRect = snapshot.cropRect
        }
        if let id = selectedID, !annotations.contains(where: { $0.id == id }) {
            select(nil)
        }
        lastStyleEdit = nil
        hasUnsavedChanges = true
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), imageSize.width), y: min(max(point.y, 0), imageSize.height))
    }

    /// With Shift held, boxes become squares and circles.
    private func squared(from start: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func redacted(_ image: CGImage, redaction: Redaction, level: Double, scale: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output: CIImage?
        switch redaction {
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = input.clampedToExtent()
            filter.radius = Float((4 + 26 * level) * scale)
            output = filter.outputImage
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = input.clampedToExtent()
            filter.scale = Float((5 + 23 * level) * scale)
            filter.center = .zero
            output = filter.outputImage
        case .solid:
            output = nil
        }
        guard let output else { return nil }
        let result = ciContext.createCGImage(output.cropped(to: input.extent), from: input.extent)
        if result == nil {
            Log.capture.error("Making the \(redaction.rawValue, privacy: .public) layer failed")
        }
        return result
    }
}

/// A grab point on a selected mark.
nonisolated enum MarkHandle: Hashable, Sendable {
    case start
    case end
    case bend
    /// Top-left, top-right, bottom-right, bottom-left.
    case corner(Int)
    /// Top, right, bottom, left.
    case edge(Int)

    /// The handles a mark offers, with where each one sits.
    static func handles(for mark: Annotation) -> [(MarkHandle, CGPoint)] {
        switch mark.tool {
        case .arrow:
            var handles: [(MarkHandle, CGPoint)] = [(.start, mark.start), (.end, mark.end)]
            if mark.style.route == .curved { handles.append((.bend, mark.resolvedControl)) }
            return handles
        case .highlighter where mark.isStraightStroke:
            return [(.start, mark.points[0]), (.end, mark.points[1])]
        case .shape, .redact:
            let r = mark.rect
            return [
                (.corner(0), CGPoint(x: r.minX, y: r.minY)), (.corner(1), CGPoint(x: r.maxX, y: r.minY)),
                (.corner(2), CGPoint(x: r.maxX, y: r.maxY)), (.corner(3), CGPoint(x: r.minX, y: r.maxY)),
                (.edge(0), CGPoint(x: r.midX, y: r.minY)), (.edge(1), CGPoint(x: r.maxX, y: r.midY)),
                (.edge(2), CGPoint(x: r.midX, y: r.maxY)), (.edge(3), CGPoint(x: r.minX, y: r.midY)),
            ]
        default:
            return []
        }
    }

    static func hit(at point: CGPoint, on mark: Annotation, tolerance: CGFloat) -> MarkHandle? {
        handles(for: mark)
            .map { ($0.0, hypot($0.1.x - point.x, $0.1.y - point.y)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    var isCornerOrEdge: Bool {
        switch self {
        case .corner, .edge: true
        default: false
        }
    }

    func drag(_ mark: inout Annotation, to point: CGPoint, constrained: Bool) {
        switch self {
        case .start where mark.isStraightStroke:
            mark.points[0] = constrained ? Geometry.snapped(from: mark.points[1], to: point) : point
        case .end where mark.isStraightStroke:
            mark.points[1] = constrained ? Geometry.snapped(from: mark.points[0], to: point) : point
        case .start:
            mark.start = constrained ? Geometry.snapped(from: mark.end, to: point) : point
        case .end:
            mark.end = constrained ? Geometry.snapped(from: mark.start, to: point) : point
        case .bend:
            mark.control = point
        case .corner(let index):
            let r = mark.rect
            let opposite = [CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)][index]
            var target = point
            if constrained {
                let dx = point.x - opposite.x
                let dy = point.y - opposite.y
                let side = max(abs(dx), abs(dy))
                target = CGPoint(x: opposite.x + (dx < 0 ? -side : side), y: opposite.y + (dy < 0 ? -side : side))
            }
            mark.start = opposite
            mark.end = target
        case .edge(let index):
            var r = mark.rect
            switch index {
            case 0: r = CGRect(x: r.minX, y: point.y, width: r.width, height: r.maxY - point.y)
            case 1: r.size.width = point.x - r.minX
            case 2: r.size.height = point.y - r.minY
            default: r = CGRect(x: point.x, y: r.minY, width: r.maxX - point.x, height: r.height)
            }
            r = r.standardized
            mark.start = r.origin
            mark.end = CGPoint(x: r.maxX, y: r.maxY)
        }
    }
}
