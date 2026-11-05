import CoreGraphics
import XCTest
@testable import Retrace

final class QuickAccessTests: XCTestCase {
    @MainActor
    func testQuickAccessAspectRatioPersistsAndSetsTheCardFrame() throws {
        let suiteName = "RetraceQuickAccessAspectRatioTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.quickAccessAspectRatio, .threeTwo)
        for ratio in QuickAccessAspectRatio.allCases {
            let size = settings.quickAccessSize.cardSize(for: ratio)
            XCTAssertEqual(size.width / size.height, ratio.widthOverHeight, accuracy: 0.01)
        }

        settings.quickAccessAspectRatio = .fourThree
        XCTAssertEqual(SettingsStore(defaults: defaults).quickAccessAspectRatio, .fourThree)

        settings.resetToDefaults()
        XCTAssertEqual(settings.quickAccessAspectRatio, .threeTwo)
    }

    func testQuickAccessStackGeometryPilesOlderCardsAndExpandsInOrder() {
        let cardSize = QuickAccessSize.medium.cardSize(for: .threeTwo)
        let geometry = StackGeometry(cardSize: cardSize)

        XCTAssertEqual(cardSize.width / cardSize.height, 1.5, accuracy: 0.01)
        XCTAssertEqual(geometry.placement(at: 0, count: 4, expanded: false).distance, 0)
        XCTAssertEqual(geometry.placement(at: 1, count: 4, expanded: false).distance, geometry.peek)
        XCTAssertEqual(geometry.placement(at: 2, count: 4, expanded: false).distance, geometry.peek * 2)
        XCTAssertEqual(geometry.placement(at: 3, count: 4, expanded: false).opacity, 0)

        let thirdFloor = geometry.placement(at: 2, count: 4, expanded: true)
        XCTAssertEqual(thirdFloor.distance, 2 * (cardSize.height + geometry.gap))
        XCTAssertEqual(thirdFloor.scale, 1)
        XCTAssertEqual(geometry.panelSize(count: 4, expanded: true).height,
                       4 * cardSize.height + 3 * geometry.gap + 2 * geometry.padding)
    }

    func testQuickAccessThumbnailRendererDownsamplesForRetinaWithoutChangingAspectRatio() throws {
        let image = try makeTestImage(width: 4_000, height: 2_000)
        let cardSize = CGSize(width: 340, height: 226)

        XCTAssertTrue(QuickAccessThumbnailRenderer.needsDownsampling(image, for: cardSize))
        let thumbnail = try XCTUnwrap(QuickAccessThumbnailRenderer.downsample(image, for: cardSize))
        XCTAssertEqual(thumbnail.width, 904)
        XCTAssertEqual(thumbnail.height, 452)
        XCTAssertEqual(CGFloat(thumbnail.width) / CGFloat(thumbnail.height), 2, accuracy: 0.01)
    }

    func testQuickAccessThumbnailRendererDoesNotUpscaleSmallImages() throws {
        let image = try makeTestImage(width: 200, height: 100)
        let cardSize = CGSize(width: 340, height: 226)

        XCTAssertFalse(QuickAccessThumbnailRenderer.needsDownsampling(image, for: cardSize))
        XCTAssertNil(QuickAccessThumbnailRenderer.downsample(image, for: cardSize))
    }

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
