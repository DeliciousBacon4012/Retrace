import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import OSLog
import SwiftUI

/// The state of one editor window: the screenshot, its marks, the crop, and undo history.
@Observable
final class EditorDocument {
    let image: CGImage
    /// Pixels per point of the original capture, used to size new marks sensibly.
    let scale: CGFloat
    private(set) var fileURL: URL?

    private(set) var annotations: [Annotation] = []
    private(set) var cropRect: CGRect?
    var selectedID: Annotation.ID?
    /// The text mark being typed into, if any.
    var editingTextID: Annotation.ID?

    var tool: AnnotationTool = .arrow {
        didSet {
            if tool != .select { selectedID = nil }
            finishTextEditing()
        }
    }
    var color: RGBAColor = .red {
        didSet { restyleSelection { $0.color = color } }
    }
    /// Line width in points; marks store it in pixels.
    var lineWidth: CGFloat = 6 {
        didSet { restyleSelection { $0.lineWidth = lineWidth * scale } }
    }
    var fillsShapes = false {
        didSet { restyleSelection { if $0.tool.supportsFill { $0.isFilled = fillsShapes } } }
    }

    private(set) var hasUnsavedChanges = false

    /// A mark being drawn right now, not yet in `annotations`.
    private(set) var draft: Annotation?

    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    @ObservationIgnored private var dragOrigin: CGPoint?
    @ObservationIgnored private var cropOrigin: CGPoint?
    @ObservationIgnored private lazy var blurredImage: CGImage? = Self.redacted(image, tool: .blur, scale: scale)
    @ObservationIgnored private lazy var pixelatedImage: CGImage? = Self.redacted(image, tool: .pixelate, scale: scale)

    private struct Snapshot {
        let annotations: [Annotation]
        let cropRect: CGRect?
    }

    init(image: CGImage, scale: CGFloat, fileURL: URL?) {
        self.image = image
        self.scale = max(scale, 1)
        self.fileURL = fileURL
    }

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selected: Annotation? { annotations.first { $0.id == selectedID } }

    /// Everything to draw, with the in-progress mark on top.
    var visibleAnnotations: [Annotation] {
        draft.map { annotations + [$0] } ?? annotations
    }

    /// The blurred or pixelated copy of the screenshot that redaction marks reveal.
    func redactedImage(for tool: AnnotationTool) -> CGImage? {
        switch tool {
        case .blur: blurredImage
        case .pixelate: pixelatedImage
        default: nil
        }
    }

    // MARK: Pointer input, in image pixels

    func pointerDown(at point: CGPoint) {
        finishTextEditing()
        switch tool {
        case .select:
            selectedID = annotations.last { $0.contains(point, tolerance: 8 * scale) }?.id
            if selectedID != nil {
                recordUndo()
                dragOrigin = point
            }
        case .crop:
            cropOrigin = point
        case .text:
            if let existing = annotations.last(where: { $0.tool == .text && $0.contains(point, tolerance: 4 * scale) }) {
                editingTextID = existing.id
                selectedID = existing.id
                return
            }
            var mark = newMark(at: point)
            mark.fontSize = max(lineWidth * 5, 18) * scale
            recordUndo()
            annotations.append(mark)
            editingTextID = mark.id
            selectedID = mark.id
        case .counter:
            var mark = newMark(at: point)
            mark.number = (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1
            mark.fontSize = max(lineWidth * 4, 14) * scale
            commit(mark)
        default:
            draft = newMark(at: point)
        }
    }

    func pointerDragged(to point: CGPoint, constrained: Bool) {
        switch tool {
        case .select:
            guard let origin = dragOrigin, let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
            annotations[index].move(by: CGSize(width: point.x - origin.x, height: point.y - origin.y))
            dragOrigin = point
            hasUnsavedChanges = true
        case .crop:
            guard let origin = cropOrigin else { return }
            cropRect = CGRect(origin: origin, size: .zero)
                .union(CGRect(origin: clamp(point), size: .zero))
                .intersection(CGRect(origin: .zero, size: imageSize))
        default:
            guard var mark = draft else { return }
            if mark.tool.isFreehand {
                mark.points.append(point)
            } else {
                mark.end = constrained ? constrainedEnd(from: mark.start, to: point, tool: mark.tool) : point
            }
            draft = mark
        }
    }

    func pointerUp() {
        if tool == .crop, let crop = cropRect {
            let previous = Snapshot(annotations: annotations, cropRect: nil)
            if crop.width < 8 || crop.height < 8 {
                cropRect = nil
            } else {
                undoStack.append(previous)
                redoStack.removeAll()
                hasUnsavedChanges = true
            }
        }
        cropOrigin = nil
        dragOrigin = nil
        if let mark = draft {
            draft = nil
            if !mark.isNegligible { commit(mark) }
        }
    }

    // MARK: Editing

    func updateText(_ text: String, for id: Annotation.ID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].text = text
        hasUnsavedChanges = true
    }

    /// Ends text entry, removing the mark if nothing was typed.
    func finishTextEditing() {
        guard let id = editingTextID else { return }
        editingTextID = nil
        if let mark = annotations.first(where: { $0.id == id }), mark.isNegligible {
            annotations.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
        }
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        recordUndo()
        annotations.removeAll { $0.id == id }
        selectedID = nil
        editingTextID = nil
    }

    func resetCrop() {
        guard cropRect != nil else { return }
        recordUndo()
        cropRect = nil
    }

    func undo() {
        finishTextEditing()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(annotations: annotations, cropRect: cropRect))
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(annotations: annotations, cropRect: cropRect))
        restore(next)
    }

    func markSaved(to url: URL) {
        fileURL = url
        hasUnsavedChanges = false
    }

    // MARK: Helpers

    private func newMark(at point: CGPoint) -> Annotation {
        var mark = Annotation(tool: tool, at: point, color: color, lineWidth: lineWidth * scale)
        mark.isFilled = tool.supportsFill && fillsShapes
        if tool == .highlighter {
            mark.lineWidth = max(lineWidth * 4, 14) * scale
        }
        return mark
    }

    private func commit(_ mark: Annotation) {
        recordUndo()
        annotations.append(mark)
    }

    private func recordUndo() {
        undoStack.append(Snapshot(annotations: annotations, cropRect: cropRect))
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        hasUnsavedChanges = true
    }

    private func restore(_ snapshot: Snapshot) {
        annotations = snapshot.annotations
        cropRect = snapshot.cropRect
        if let id = selectedID, !annotations.contains(where: { $0.id == id }) {
            selectedID = nil
        }
        hasUnsavedChanges = true
    }

    private func restyleSelection(_ change: (inout Annotation) -> Void) {
        guard let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        recordUndo()
        change(&annotations[index])
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), imageSize.width), y: min(max(point.y, 0), imageSize.height))
    }

    /// With Shift held, lines snap to 45° and shapes become squares and circles.
    private func constrainedEnd(from start: CGPoint, to point: CGPoint, tool: AnnotationTool) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        switch tool {
        case .arrow, .line:
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        default:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
    }

    // MARK: Redaction

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func redacted(_ image: CGImage, tool: AnnotationTool, scale: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output: CIImage?
        switch tool {
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = input.clampedToExtent()
            filter.radius = Float(14 * scale)
            output = filter.outputImage
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = input.clampedToExtent()
            filter.scale = Float(12 * scale)
            filter.center = .zero
            output = filter.outputImage
        default:
            output = nil
        }
        guard let output else { return nil }
        let result = ciContext.createCGImage(output.cropped(to: input.extent), from: input.extent)
        if result == nil {
            Log.capture.error("Making the \(tool.rawValue, privacy: .public) layer failed")
        }
        return result
    }
}
