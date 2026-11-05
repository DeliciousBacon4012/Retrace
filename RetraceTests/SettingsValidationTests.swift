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

    /// Test copies launch with `-keepsClipboardHistory 0`, which arrives as text.
    @MainActor
    func testLaunchArgumentTextReadsAsSwitchesAndNumbers() throws {
        let suiteName = "RetraceArgumentSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("0", forKey: "keepsClipboardHistory")
        defaults.set("NO", forKey: "playsSounds")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertFalse(settings.keepsClipboardHistory)
        XCTAssertFalse(settings.playsSounds)
    }

    /// Text history used to be a count, with zero meaning off.
    @MainActor
    func testFormerTextHistoryCountCarriesOver() throws {
        for (limit, keeps, retention) in [(0, false, HistoryRetention.forever), (25, true, .items50), (100, true, .items100), (250, true, .items250)] {
            let suiteName = "RetraceTextHistoryMigration-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(limit, forKey: "textHistoryLimit")

            let settings = SettingsStore(defaults: defaults)

            XCTAssertEqual(settings.keepsTextHistory, keeps, "limit \(limit)")
            XCTAssertEqual(settings.textHistoryRetention, retention, "limit \(limit)")
            XCTAssertNil(defaults.object(forKey: "textHistoryLimit"))
        }
    }
}
