import CoreGraphics
import XCTest
@testable import Untitled

final class VisionPrivacyTests: XCTestCase {
    func testPeopleRedactionRequestReturnsNoAreasForBlankImage() async throws {
        let image = try makeBlankImage()

        let areas = try await TextRecognizer.sensitiveAreas(in: image, kinds: [.people])

        XCTAssertTrue(areas.isEmpty)
    }

    func testAttentionCropIsNilOrReturnsAValidImageBoundedSuggestion() async throws {
        let image = try makeBlankImage()

        guard let crop = try await TextRecognizer.attentionCrop(in: image) else { return }

        XCTAssertTrue(crop.width.isFinite && crop.height.isFinite)
        XCTAssertGreaterThanOrEqual(crop.width, 8)
        XCTAssertGreaterThanOrEqual(crop.height, 8)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: image.width, height: image.height).contains(crop))
    }

    private func makeBlankImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 240,
            height: 160,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        return try XCTUnwrap(context.makeImage())
    }
}
