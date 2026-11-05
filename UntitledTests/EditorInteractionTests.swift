import CoreGraphics
import XCTest
@testable import Untitled

final class EditorInteractionTests: XCTestCase {
    func testHighlighterSnapsToTheNearestLineAndKeepsWholeTouchedWords() throws {
        let line = TextLine(
            rect: CGRect(x: 8, y: 20, width: 48, height: 10),
            words: [
                CGRect(x: 10, y: 20, width: 10, height: 10),
                CGRect(x: 24, y: 20, width: 12, height: 10),
                CGRect(x: 40, y: 20, width: 14, height: 10),
            ]
        )
        let otherLine = TextLine(
            rect: CGRect(x: 8, y: 40, width: 48, height: 10),
            words: [CGRect(x: 10, y: 40, width: 44, height: 10)]
        )
        let stroke = [
            CGPoint(x: 12, y: 24), CGPoint(x: 20, y: 25), CGPoint(x: 35, y: 26),
            CGPoint(x: 35, y: 26), CGPoint(x: 35, y: 34),
        ]

        let band = try XCTUnwrap(HighlightSnapping.band(for: stroke, lines: [otherLine, line]))

        XCTAssertEqual(band.start.x, 8.8, accuracy: 0.01)
        XCTAssertEqual(band.end.x, 37.2, accuracy: 0.01)
        XCTAssertEqual(band.start.y, 25, accuracy: 0.01)
        XCTAssertEqual(band.thickness, 11, accuracy: 0.01)
    }

    func testBlockHighlighterReturnsTextBandsFromTopToBottom() {
        let bottom = TextLine(
            rect: CGRect(x: 10, y: 40, width: 60, height: 10),
            words: [CGRect(x: 12, y: 40, width: 20, height: 10), CGRect(x: 36, y: 40, width: 20, height: 10)]
        )
        let top = TextLine(
            rect: CGRect(x: 10, y: 10, width: 60, height: 10),
            words: [CGRect(x: 12, y: 10, width: 20, height: 10), CGRect(x: 36, y: 10, width: 20, height: 10)]
        )

        let bands = HighlightSnapping.bands(in: CGRect(x: 11, y: 8, width: 50, height: 45), lines: [bottom, top])

        XCTAssertEqual(bands.map(\.start.y), [15, 45])
        XCTAssertEqual(bands.map(\.start.x), [10.8, 10.8])
        XCTAssertEqual(bands.map(\.end.x), [57.2, 57.2])
    }

    @MainActor
    func testMovingSelectedAnnotationsKeepsTheGestureTargetsAndUndoRestoresThem() {
        let context = CGContext(
            data: nil,
            width: 1_024,
            height: 1_024,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!

        var style = MarkStyle.defaults(for: .arrow, scale: 1)
        style.route = .straight

        var first = Annotation(tool: .arrow, at: CGPoint(x: 10, y: 10), style: style)
        first.end = CGPoint(x: 20, y: 20)
        var second = Annotation(tool: .arrow, at: CGPoint(x: 40, y: 10), style: style)
        second.end = CGPoint(x: 50, y: 20)
        var untouched = Annotation(tool: .arrow, at: CGPoint(x: 80, y: 10), style: style)
        untouched.end = CGPoint(x: 90, y: 20)

        let distractors = (0..<128).map { index in
            var mark = Annotation(
                tool: .arrow,
                at: CGPoint(x: 200 + index * 4, y: 200),
                style: style
            )
            mark.end = CGPoint(x: 202 + index * 4, y: 202)
            return mark
        }
        let original = [first, second, untouched] + distractors
        let document = EditorDocument(image: image, scale: 1, fileURL: nil, annotations: original)

        document.select(first.id)
        document.pointerDown(at: CGPoint(x: 45, y: 15), tolerance: 1, clickCount: 1, extending: true)
        document.pointerUp()
        XCTAssertEqual(document.selectedIDs, Set([first.id, second.id]))

        document.pointerDown(at: CGPoint(x: 15, y: 15), tolerance: 1, clickCount: 1)
        document.pointerDragged(to: CGPoint(x: 20, y: 23), constrained: false)
        document.pointerUp()

        XCTAssertEqual(document.annotations[0].start, CGPoint(x: 15, y: 18))
        XCTAssertEqual(document.annotations[1].start, CGPoint(x: 45, y: 18))
        XCTAssertEqual(document.annotations.dropFirst(2), original.dropFirst(2))

        document.undo()
        XCTAssertEqual(document.annotations, original)
    }

    @MainActor
    func testReshapingSelectedAnnotationKeepsTheGestureTargetAndUndoRestoresIt() {
        let context = CGContext(
            data: nil,
            width: 1_024,
            height: 1_024,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!

        var style = MarkStyle.defaults(for: .arrow, scale: 1)
        style.route = .straight
        var selected = Annotation(tool: .arrow, at: CGPoint(x: 10, y: 10), style: style)
        selected.end = CGPoint(x: 20, y: 20)
        let distractors = (0..<128).map { index in
            var mark = Annotation(
                tool: .arrow,
                at: CGPoint(x: 200 + index * 4, y: 200),
                style: style
            )
            mark.end = CGPoint(x: 202 + index * 4, y: 202)
            return mark
        }
        let original = [selected] + distractors
        let document = EditorDocument(image: image, scale: 1, fileURL: nil, annotations: original)

        document.select(selected.id)
        document.pointerDown(at: selected.start, tolerance: 1, clickCount: 1)
        document.pointerDragged(to: CGPoint(x: 6, y: 8), constrained: false)
        document.pointerUp()

        XCTAssertEqual(document.annotations[0].start, CGPoint(x: 6, y: 8))
        XCTAssertEqual(document.annotations[0].end, selected.end)
        XCTAssertEqual(document.annotations.dropFirst(), original.dropFirst())

        document.undo()
        XCTAssertEqual(document.annotations, original)
    }

    func testCustomEditorPalettePersistsAndNumberKeysUseItsColors() throws {
        let colors = (0..<EditorPalette.customColorCount).map { index in
            RGBAColor(red: Double(index) / 11, green: 0.25, blue: 0.75)
        }
        let data = try JSONEncoder().encode(colors)
        let restored = EditorPalette.customColors(from: data)

        XCTAssertEqual(restored, colors)
        XCTAssertEqual(EditorPalette.custom.color(forDigit: 1, customColors: restored), colors[0])
        XCTAssertEqual(EditorPalette.custom.color(forDigit: 0, customColors: restored), colors[9])
        XCTAssertNil(EditorPalette.custom.color(forDigit: 11, customColors: restored))
    }

    func testInvalidCustomEditorPaletteUsesTheDefaultColors() throws {
        let wrongCount = try JSONEncoder().encode([RGBAColor](repeating: .coral, count: 2))
        let invalidComponent = try JSONEncoder().encode(
            [RGBAColor](repeating: RGBAColor(red: 2, green: 0, blue: 0), count: EditorPalette.customColorCount)
        )

        XCTAssertEqual(EditorPalette.customColors(from: wrongCount), EditorPalette.defaultCustomColors)
        XCTAssertEqual(EditorPalette.customColors(from: invalidComponent), EditorPalette.defaultCustomColors)
        XCTAssertEqual(EditorPalette.customColors(from: Data([0xFF])), EditorPalette.defaultCustomColors)
    }

    @MainActor
    func testZoomScrubFollowsDominantAxisWithoutDiagonalCancellation() {
        XCTAssertEqual(ZoomScrub.distance(for: CGSize(width: 80, height: 80)), 80)
        XCTAssertEqual(ZoomScrub.distance(for: CGSize(width: -80, height: 80)), -80)
        XCTAssertEqual(ZoomScrub.distance(for: CGSize(width: 30, height: -90)), 90)
        XCTAssertEqual(ZoomScrub.distance(for: CGSize(width: 10, height: 90)), -90)
        XCTAssertEqual(ZoomScrub.distance(for: CGSize(width: -90, height: -10)), -90)
    }
}
