import XCTest
@testable import Retrace

final class SaveDestinationTests: XCTestCase {
    @MainActor
    func testLegacyDefaultFolderHasAnExplicitDisplayName() throws {
        let suiteName = "RetraceDefaultFolderNameTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.saveFolderDisplayName(for: settings.saveFolderPath), "Pictures › Retrace")
        XCTAssertEqual(URL(fileURLWithPath: settings.saveFolderPath).lastPathComponent, "Retrace")
    }

    @MainActor
    func testSaveLocationsNormalizePersistAndKeepOneDefault() throws {
        let suiteName = "RetraceSaveLocationsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetraceLocationA-\(UUID().uuidString)", isDirectory: true)
        let second = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetraceLocationB-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(defaults: defaults)
        let originalDefault = settings.saveFolderPath

        XCTAssertTrue(settings.addSaveFolder(first))
        XCTAssertFalse(settings.addSaveFolder(first.appendingPathComponent(".")))
        XCTAssertTrue(settings.addSaveFolder(second))
        settings.setDefaultSaveFolder(second.path)

        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.saveFolderPath, second.standardizedFileURL.path)
        XCTAssertTrue(reopened.saveFolderPaths.contains(first.standardizedFileURL.path))
        XCTAssertTrue(reopened.saveFolderPaths.contains(second.standardizedFileURL.path))

        reopened.removeSaveFolder(second.path)
        XCTAssertEqual(reopened.saveFolderPath, originalDefault)
        reopened.removeSaveFolder(first.path)
        XCTAssertEqual(reopened.saveFolderPaths, [originalDefault])
        XCTAssertEqual(reopened.saveFolderPath, originalDefault)
    }

    @MainActor
    func testCaptureDestinationOverrideFallsBackWhenLocationIsRemoved() throws {
        let suiteName = "RetraceCaptureDestinationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        let originalDefault = settings.saveFolderPath
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetraceCaptureDestination-\(UUID().uuidString)", isDirectory: true)
        XCTAssertTrue(settings.addSaveFolder(destination))

        XCTAssertNil(CaptureDestinationSelection.folder(for: settings.captureDestinationOverridePath, in: settings))
        XCTAssertEqual(CaptureDestinationSelection.activePath(for: settings.captureDestinationOverridePath, in: settings), originalDefault)

        settings.captureDestinationOverridePath = CaptureDestinationSelection.selection(
            for: destination.standardizedFileURL.path,
            defaultPath: settings.saveFolderPath
        )
        XCTAssertEqual(CaptureDestinationSelection.folder(for: settings.captureDestinationOverridePath, in: settings), destination.standardizedFileURL)
        XCTAssertEqual(settings.saveFolderPath, originalDefault)

        settings.removeSaveFolder(destination.path)
        XCTAssertNil(settings.captureDestinationOverridePath)
        XCTAssertNil(CaptureDestinationSelection.folder(for: settings.captureDestinationOverridePath, in: settings))
        XCTAssertEqual(settings.saveFolderPath, originalDefault)
        XCTAssertEqual(settings.saveFolderURL.path, originalDefault)
    }
}
