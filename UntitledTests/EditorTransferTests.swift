import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Untitled

final class EditorTransferTests: XCTestCase {
    func testEditorImageTransferProducesAValidPNG() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 3,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        let image = try XCTUnwrap(context.makeImage())

        let data = try EditorImageTransfer(image: image).pngData()
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        XCTAssertEqual(decoded.width, 3)
        XCTAssertEqual(decoded.height, 2)
    }

    func testEditorImageTransferReportsMissingImage() {
        XCTAssertThrowsError(try EditorImageTransfer(image: nil).pngData()) { error in
            XCTAssertEqual(error as? EditorImageTransfer.ExportError, .imageUnavailable)
        }
    }
}
