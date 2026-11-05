import CoreGraphics
import SwiftUI
import XCTest
@testable import Retrace

final class RedactionRendererTests: XCTestCase {
    @MainActor
    func testPreviewCoversMissingBlurAndMosaicLayersWithOpaqueColor() throws {
        let source = try makeImage(width: 12, height: 12, color: .white)
        for redaction in [Redaction.blur, .pixelate] {
            var style = MarkStyle.defaults(for: .redact, scale: 1)
            style.redaction = redaction
            style.color = RGBAColor(red: 0, green: 0, blue: 0, opacity: 0.05)

            var mark = Annotation(tool: .redact, at: CGPoint(x: 2, y: 2), style: style)
            mark.end = CGPoint(x: 10, y: 10)

            let renderer = ImageRenderer(content:
                Canvas { context, _ in
                    AnnotationRenderer.draw(
                        image: source,
                        annotations: [mark],
                        redacted: { _, _ in nil },
                        in: &context
                    )
                }
                .frame(width: 12, height: 12)
            )
            renderer.scale = 1

            let rendered = try XCTUnwrap(renderer.cgImage)
            let center = try pixel(at: CGPoint(x: 6, y: 6), in: rendered)
            XCTAssertLessThan(center.red, 80, "\(redaction) fallback should hide the bright source")
            XCTAssertLessThan(center.green, 80, "\(redaction) fallback must be opaque")
            XCTAssertLessThan(center.blue, 80, "\(redaction) fallback must be opaque")
        }
    }

    @MainActor
    func testExportFailsClosedWhenAnyBlurOrMosaicLayerIsUnavailable() throws {
        let source = try makeImage(width: 12, height: 12, color: .white)
        for redaction in [Redaction.blur, .pixelate] {
            var style = MarkStyle.defaults(for: .redact, scale: 1)
            style.redaction = redaction
            var mark = Annotation(tool: .redact, at: CGPoint(x: 2, y: 2), style: style)
            mark.end = CGPoint(x: 10, y: 10)
            let document = EditorDocument(image: source, scale: 1, fileURL: nil, annotations: [mark])

            XCTAssertThrowsError(try AnnotationRenderer.export(document, redacted: { _, _ in nil })) { error in
                XCTAssertEqual(error as? AnnotationRenderer.ExportFailure, .redactionUnavailable(redaction))
            }
        }
    }

    private func makeImage(width: Int, height: Int, color: CGColor) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    @MainActor
    private func pixel(at point: CGPoint, in image: CGImage) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }

        let index = (Int(point.y) * image.width + Int(point.x)) * 4
        return (pixels[index], pixels[index + 1], pixels[index + 2])
    }
}
