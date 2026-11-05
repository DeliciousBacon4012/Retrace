import CoreGraphics
import XCTest
@testable import Untitled

final class ImageEncodingPrivacyTests: XCTestCase {
    func testMetadataAuditRejectsUnreadableImageData() {
        XCTAssertThrowsError(try MetadataAudit.leftovers(in: Data([0xFF, 0x00, 0x7F])))
    }

    func testEncodedPrivacyCleanImagePassesMetadataAudit() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        for format in ImageFormat.writable {
            let options = ExportOptions(format: format, stripsMetadata: true)
            let data = try ImageEncoder.data(for: image, options: options)
            XCTAssertTrue(try MetadataAudit.leftovers(in: data).isEmpty, "\(format.title) should be metadata-clean")
        }
    }
}
