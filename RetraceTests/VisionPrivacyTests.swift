import CoreGraphics
import CoreImage
import CoreText
import XCTest
@testable import Retrace

final class VisionPrivacyTests: XCTestCase {
    func testVisionRecognizesTextFromAHighContrastImage() async throws {
        let image = try makeTextImage()

        let content = try await TextRecognizer.recognize(image)

        XCTAssertTrue(
            content.lines.contains { $0.text.localizedCaseInsensitiveContains("RETRACE") },
            "Vision should recognize the high-contrast sample text."
        )
    }

    func testForegroundMaskCompositesTheBackgroundAsTransparent() throws {
        let sourceContext = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        sourceContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        sourceContext.fill(CGRect(x: 0, y: 0, width: 2, height: 1))

        let maskContext = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        maskContext.setFillColor(gray: 1, alpha: 1)
        maskContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        maskContext.setFillColor(gray: 0, alpha: 1)
        maskContext.fill(CGRect(x: 1, y: 0, width: 1, height: 1))

        let subject = try TextRecognizer.composeForeground(
            try XCTUnwrap(sourceContext.makeImage()),
            mask: CIImage(cgImage: try XCTUnwrap(maskContext.makeImage()))
        )
        var pixels = [UInt8](repeating: 0, count: 8)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: 2,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(subject, in: CGRect(x: 0, y: 0, width: 2, height: 1))
        }

        XCTAssertGreaterThan(pixels[3], 240, "The foreground pixel stays opaque.")
        XCTAssertLessThan(pixels[7], 10, "The background pixel becomes transparent.")
    }

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

    private func makeTextImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 900,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 900, height: 200))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "RETRACE OCR CHECK 123", attributes: attributes))
        context.textPosition = CGPoint(x: 24, y: 76)
        CTLineDraw(line, context)
        return try XCTUnwrap(context.makeImage())
    }
}
