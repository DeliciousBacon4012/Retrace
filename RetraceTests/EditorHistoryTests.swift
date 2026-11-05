import CoreGraphics
import XCTest
@testable import Retrace

final class EditorHistoryTests: XCTestCase {
    @MainActor
    private func makeDocument() throws -> EditorDocument {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return EditorDocument(image: try XCTUnwrap(context.makeImage()), scale: 1, fileURL: nil)
    }

    @MainActor
    func testUndoAndRedoHistorySurvivesASaveAndRestore() throws {
        let original = try makeDocument()
        // Three edits, then one undone: two steps to undo and one to redo. In the app each edit
        // is its own event; here they're grouped by hand.
        original.undoManager.groupsByEvent = false
        for index in 0..<3 {
            original.undoManager.beginUndoGrouping()
            defer { original.undoManager.endUndoGrouping() }
            original.tool = .shape
            original.pointerDown(at: CGPoint(x: 10 + index * 20, y: 10), tolerance: 1, clickCount: 1, extending: false)
            original.pointerDragged(to: CGPoint(x: 18 + index * 20, y: 30), constrained: false, freehand: false)
            original.pointerUp()
        }
        original.undoManager.groupsByEvent = true
        XCTAssertEqual(original.annotations.count, 3)
        original.undo()
        XCTAssertEqual(original.annotations.count, 2)

        let data = try JSONEncoder().encode(original.savedEdits)
        let restored = try makeDocument()
        restored.restore(try JSONDecoder().decode(EditorDocument.SavedEdits.self, from: data))

        XCTAssertEqual(restored.annotations.count, 2)
        XCTAssertTrue(restored.canRedo)
        restored.redo()
        XCTAssertEqual(restored.annotations.count, 3)
        restored.undo()
        restored.undo()
        restored.undo()
        XCTAssertEqual(restored.annotations.count, 0)
        XCTAssertFalse(restored.canUndo)
    }
}
