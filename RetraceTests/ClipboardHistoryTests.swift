import XCTest
@testable import Retrace

final class ClipboardHistoryTests: XCTestCase {
    func testClearingClipboardHistoryInvalidatesPendingImages() {
        var generation = ClipboardHistoryGeneration()
        let pendingToken = generation.value
        XCTAssertTrue(generation.accepts(pendingToken, isEnabled: true))

        generation.invalidate()

        XCTAssertFalse(generation.accepts(pendingToken, isEnabled: true))
        XCTAssertTrue(generation.accepts(generation.value, isEnabled: true))
    }

    func testPausingClipboardHistoryRejectsPendingImageEvenAfterResume() {
        var generation = ClipboardHistoryGeneration()
        let pendingToken = generation.value
        XCTAssertFalse(generation.accepts(pendingToken, isEnabled: false))

        generation.invalidate()
        generation.invalidate()

        XCTAssertFalse(generation.accepts(pendingToken, isEnabled: true))
        XCTAssertTrue(generation.accepts(generation.value, isEnabled: true))
    }

    func testClipboardImageBoundsAllowNormalAndMaximumSupportedImages() {
        XCTAssertTrue(ClipboardImageBounds.permits(width: 1_920, height: 1_080))
        XCTAssertTrue(ClipboardImageBounds.permits(width: 10_000, height: 4_000))
    }

    func testClipboardImageBoundsRejectInvalidDimensionsAndOversizedPixels() {
        XCTAssertFalse(ClipboardImageBounds.permits(width: 0, height: 100))
        XCTAssertFalse(ClipboardImageBounds.permits(width: 100, height: -1))
        XCTAssertFalse(ClipboardImageBounds.permits(width: 10_001, height: 4_000))
        XCTAssertFalse(ClipboardImageBounds.permits(width: 16_385, height: 1))
    }

    @MainActor
    func testHistoryRetentionDefaultsToThirtyDaysAndHonorsStoredChoice() throws {
        let suiteName = "RetraceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let freshSettings = SettingsStore(defaults: defaults)
        XCTAssertEqual(freshSettings.clipboardRetention, .forever)

        freshSettings.clipboardRetention = .month
        let reopenedSettings = SettingsStore(defaults: defaults)
        XCTAssertEqual(reopenedSettings.clipboardRetention, .month)

        reopenedSettings.resetToDefaults()
        XCTAssertEqual(reopenedSettings.clipboardRetention, .forever)
    }
}
