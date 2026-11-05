import XCTest
@testable import Retrace

final class SettingsValidationTests: XCTestCase {
    @MainActor
    func testMalformedPersistedSettingsFallBackToSupportedValues() throws {
        let suiteName = "RetraceMalformedSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Double.nan, forKey: "imageQuality")
        defaults.set(Int.max, forKey: "framesPerSecond")
        defaults.set(-1, forKey: "recordingCountdownSeconds")
        defaults.set(Int.max, forKey: "overlayAutoCloseSeconds")
        defaults.set(0, forKey: "replayBufferSeconds")
        defaults.set(-1, forKey: "replayDiskLimitGB")
        defaults.set("yes", forKey: "keepsOCRLineBreaks")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.imageQuality, 0.85)
        XCTAssertEqual(settings.framesPerSecond, 60)
        XCTAssertEqual(settings.recordingCountdownSeconds, 3)
        XCTAssertEqual(settings.overlayAutoCloseSeconds, 0)
        XCTAssertEqual(settings.replayBufferSeconds, 60)
        XCTAssertEqual(settings.replayDiskLimitGB, 4)
        XCTAssertTrue(settings.keepsOCRLineBreaks)
        XCTAssertEqual(defaults.double(forKey: "imageQuality"), 0.85)
        XCTAssertEqual(defaults.integer(forKey: "framesPerSecond"), 60)
    }
}
