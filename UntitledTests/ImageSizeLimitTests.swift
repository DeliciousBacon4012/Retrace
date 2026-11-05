import CoreGraphics
import XCTest
@testable import Untitled

final class ImageSizeLimitTests: XCTestCase {
    func testRejectsSizeLimitThatCannotFitTheImage() throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let options = ExportOptions(format: .jpeg, quality: 0.05, maximumBytes: 1, stripsMetadata: true)

        XCTAssertThrowsError(try ImageEncoder.data(for: image, options: options)) { error in
            guard let encodingError = error as? ImageEncoder.EncodingError,
                  case .sizeLimitCannotBeMet = encodingError
            else {
                XCTFail("Expected an explicit size-limit error, got \(error)")
                return
            }
        }
    }

    func testRejectsNonpositiveSizeLimit() throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let options = ExportOptions(format: .jpeg, maximumBytes: 0, stripsMetadata: true)

        XCTAssertThrowsError(try ImageEncoder.data(for: image, options: options)) { error in
            guard let encodingError = error as? ImageEncoder.EncodingError,
                  case .invalidSizeLimit = encodingError
            else {
                XCTFail("Expected an explicit invalid-size error, got \(error)")
                return
            }
        }
    }
}
