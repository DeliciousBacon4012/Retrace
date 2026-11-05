import CoreGraphics
import XCTest
@testable import Retrace

final class ImageIntelligenceTests: XCTestCase {
    func testVisionBoxBecomesAPaddedTopLeftCrop() throws {
        let crop = try XCTUnwrap(ImageIntelligence.cropRect(
            forVisionBox: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25),
            in: CGSize(width: 1000, height: 1000),
            padding: 0
        ))
        XCTAssertEqual(crop, CGRect(x: 250, y: 250, width: 500, height: 250))
    }

    func testCropThatCoversTheWholeImageIsNoSuggestion() {
        XCTAssertNil(ImageIntelligence.cropRect(
            forVisionBox: CGRect(x: 0, y: 0, width: 1, height: 1),
            in: CGSize(width: 500, height: 500),
            padding: 0.18
        ))
    }

    func testLabelsReadAsWords() {
        XCTAssertEqual(ImageLabel(name: "outdoor_structure", confidence: 1).title, "Outdoor Structure")
    }

    func testVisionRunsOnASyntheticImage() async throws {
        let image = try makeImage(top: .init(gray: 0.1, alpha: 1), bottom: .init(gray: 0.9, alpha: 1))
        _ = try await ImageIntelligence.labels(in: image)
        for mode in SmartCropMode.allCases {
            _ = try await ImageIntelligence.suggestedCrop(in: image, mode: mode)
        }
    }

    func testFingerprintsCompareCloserForTheSameImage() async throws {
        let dark = try makeImage(top: .init(gray: 0, alpha: 1), bottom: .init(gray: 0.1, alpha: 1))
        let split = try makeImage(top: .init(red: 1, green: 0, blue: 0, alpha: 1), bottom: .init(red: 0, green: 0, blue: 1, alpha: 1))
        let first = try await XCTUnwrapAsync(try await ImageIntelligence.featurePrint(of: dark))
        let same = try await XCTUnwrapAsync(try await ImageIntelligence.featurePrint(of: dark))
        let other = try await XCTUnwrapAsync(try await ImageIntelligence.featurePrint(of: split))
        let near = try XCTUnwrap(ImageIntelligence.distance(between: first, and: same))
        let far = try XCTUnwrap(ImageIntelligence.distance(between: first, and: other))
        XCTAssertLessThan(near, far)
    }

    @MainActor
    func testIndexMatchesAndForgetsFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RetraceIndex-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let index = LibraryContentIndex(fileURL: folder.appending(path: "index.json"))
        XCTAssertFalse(index.matches(folder.appending(path: "none.png"), query: "x"))
        index.removeAll()
        XCTAssertEqual(index.indexedCount, 0)
    }

    private func XCTUnwrapAsync<T>(_ value: T?) async throws -> T { try XCTUnwrap(value) }

    private func makeImage(top: CGColor, bottom: CGColor) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(bottom)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 150))
        context.setFillColor(top)
        context.fill(CGRect(x: 0, y: 150, width: 400, height: 150))
        return try XCTUnwrap(context.makeImage())
    }
}
