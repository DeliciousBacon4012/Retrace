import XCTest
@testable import Retrace

final class LegacyDataMigratorTests: XCTestCase {
    private var root: URL!
    private var support: URL!
    private var pictures: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetraceMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        support = root.appending(path: "Application Support", directoryHint: .isDirectory)
        pictures = root.appending(path: "Pictures", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        suite = "RetraceMigrationTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func migrator(preferences: [String: Any]?) -> LegacyDataMigrator {
        LegacyDataMigrator(
            defaults: defaults,
            legacyPreferences: preferences,
            applicationSupport: support,
            pictures: pictures,
            fileManager: .default
        )
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func path(_ url: URL) -> String { url.standardizedFileURL.path(percentEncoded: false) }

    func testMovesEverythingAndUpdatesEveryPath() throws {
        let oldCaptures = pictures.appending(path: "Untitled", directoryHint: .isDirectory)
        let newCaptures = pictures.appending(path: "Retrace", directoryHint: .isDirectory)
        let capture = oldCaptures.appending(path: "Untitled shot.png")
        try write("pixels", to: capture)

        let oldData = support.appending(path: LegacyDataMigrator.legacyBundleIdentifier, directoryHint: .isDirectory)
        let newData = support.appending(path: LegacyDataMigrator.bundleIdentifier, directoryHint: .isDirectory)
        try write("{\"\(path(capture))\":\"area\"}", to: oldData.appending(path: "Library/CaptureSources.json"))
        try write("clip", to: oldData.appending(path: "Clipboard/History.json"))

        let originals = support.appending(path: "Untitled/Originals/index.json")
        try write("{\"\(path(capture))\":{\"file\":\"a.png\",\"savedAt\":1}}", to: originals)

        let oldRoot = path(oldCaptures).replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        migrator(preferences: [
            "saveFolderPath": oldRoot,
            "saveFolderPaths": [oldRoot, "/Volumes/Elsewhere"],
            "filenameTemplate": "Untitled {date} at {time}",
            "clipboardRetention": "forever",
            "NSWindow Frame main": "ignored"
        ]).run()

        let movedCapture = newCaptures.appending(path: "Untitled shot.png")
        XCTAssertEqual(try String(contentsOf: movedCapture, encoding: .utf8), "pixels")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(oldCaptures)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(oldData)))
        XCTAssertEqual(try String(contentsOf: newData.appending(path: "Clipboard/History.json"), encoding: .utf8), "clip")

        let newRoot = path(newCaptures).replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        XCTAssertEqual(defaults.string(forKey: "saveFolderPath"), newRoot)
        XCTAssertEqual(defaults.stringArray(forKey: "saveFolderPaths"), [newRoot, "/Volumes/Elsewhere"])
        XCTAssertEqual(defaults.string(forKey: "filenameTemplate"), "Retrace {date} at {time}")
        XCTAssertEqual(defaults.string(forKey: "clipboardRetention"), "forever")
        XCTAssertNil(defaults.object(forKey: "NSWindow Frame main"))

        let sources = try JSONDecoder().decode(
            [String: CaptureSource].self,
            from: Data(contentsOf: newData.appending(path: "Library/CaptureSources.json"))
        )
        XCTAssertEqual(sources[path(movedCapture)], .area)

        let versions = try JSONDecoder().decode(
            [String: CaptureVersions.Entry].self,
            from: Data(contentsOf: newData.appending(path: "Originals/index.json"))
        )
        XCTAssertEqual(versions[path(movedCapture)]?.file, "a.png")
    }

    func testNeverOverwritesAnExistingDestination() throws {
        let oldCaptures = pictures.appending(path: "Untitled", directoryHint: .isDirectory)
        let newCaptures = pictures.appending(path: "Retrace", directoryHint: .isDirectory)
        try write("old", to: oldCaptures.appending(path: "a.png"))
        try write("new", to: newCaptures.appending(path: "a.png"))
        let oldRoot = path(oldCaptures).replacingOccurrences(of: "/$", with: "", options: .regularExpression)

        migrator(preferences: ["saveFolderPath": oldRoot, "saveFolderPaths": [oldRoot]]).run()

        XCTAssertEqual(try String(contentsOf: oldCaptures.appending(path: "a.png"), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: newCaptures.appending(path: "a.png"), encoding: .utf8), "new")
        XCTAssertEqual(defaults.string(forKey: "saveFolderPath"), oldRoot, "Settings keep pointing at the folder that still holds the files.")
    }

    func testMovesOverAnEmptyDestination() throws {
        let oldCaptures = pictures.appending(path: "Untitled", directoryHint: .isDirectory)
        let newCaptures = pictures.appending(path: "Retrace", directoryHint: .isDirectory)
        try write("old", to: oldCaptures.appending(path: "a.png"))
        try FileManager.default.createDirectory(at: newCaptures, withIntermediateDirectories: true)

        migrator(preferences: nil).run()

        XCTAssertEqual(try String(contentsOf: newCaptures.appending(path: "a.png"), encoding: .utf8), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(oldCaptures)))
    }

    func testRunsOnlyOnceAndKeepsNewerValues() throws {
        defaults.set("mine", forKey: "filenameTemplate")
        migrator(preferences: ["filenameTemplate": "Untitled {date}", "imageFormat": "png"]).run()
        XCTAssertEqual(defaults.string(forKey: "filenameTemplate"), "mine")
        XCTAssertEqual(defaults.string(forKey: "imageFormat"), "png")

        defaults.removeObject(forKey: "imageFormat")
        migrator(preferences: ["imageFormat": "png"]).run()
        XCTAssertNil(defaults.object(forKey: "imageFormat"))
    }

    func testLeavesUnrelatedPathsAlone() {
        XCTAssertEqual(LegacyDataMigrator.replacingRoot(of: "/p/Untitled Stuff/a.png", from: "/p/Untitled", to: "/p/Retrace"), "/p/Untitled Stuff/a.png")
        XCTAssertEqual(LegacyDataMigrator.replacingRoot(of: "/p/Untitled/a.png", from: "/p/Untitled", to: "/p/Retrace"), "/p/Retrace/a.png")
        XCTAssertEqual(LegacyDataMigrator.replacingRoot(of: "/p/Untitled", from: "/p/Untitled", to: "/p/Retrace"), "/p/Retrace")
    }
}
