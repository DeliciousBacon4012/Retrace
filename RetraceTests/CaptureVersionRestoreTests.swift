import Foundation
import XCTest
@testable import Retrace

final class CaptureVersionRestoreTests: XCTestCase {
    @MainActor
    func testRestoreLeavesEditedCaptureInPlaceWhenOriginalIsMissing() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetraceRestoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = folder.appendingPathComponent("capture.png")
        let originalsFolder = folder.appendingPathComponent("originals", isDirectory: true)
        let editedData = Data("edited-image-data".utf8)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try editedData.write(to: source)

        let versions = CaptureVersions(folder: originalsFolder)
        try await versions.preserveOriginal(of: source)
        let original = try XCTUnwrap(versions.original(for: source))
        try FileManager.default.removeItem(at: original)

        XCTAssertThrowsError(try versions.restoreOriginal(of: source)) { error in
            guard let versionError = error as? CaptureVersionError,
                  case .originalMissing = versionError
            else {
                XCTFail("Expected the missing-original error, got \(error)")
                return
            }
        }
        XCTAssertEqual(try Data(contentsOf: source), editedData)
        XCTAssertFalse(versions.hasOriginal(for: source))
    }

    @MainActor
    func testMalformedIndexCannotTrashFilesOutsideOriginalsFolder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetraceVersionIndexTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let originalsFolder = folder.appendingPathComponent("originals", isDirectory: true)
        let sourceWithTraversalEntry = folder.appendingPathComponent("capture-a.png")
        let sourceWithSymlinkEntry = folder.appendingPathComponent("capture-b.png")
        let outsideFile = folder.appendingPathComponent("outside.txt")
        let symlink = originalsFolder.appendingPathComponent("redirect.txt")
        try FileManager.default.createDirectory(at: originalsFolder, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: sourceWithTraversalEntry)
        try Data("b".utf8).write(to: sourceWithSymlinkEntry)
        try Data("outside".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outsideFile)

        let unsafeEntries = [
            sourceWithTraversalEntry.standardizedFileURL.path: CaptureVersions.Entry(file: "../outside.txt", savedAt: .now),
            sourceWithSymlinkEntry.standardizedFileURL.path: CaptureVersions.Entry(file: "redirect.txt", savedAt: .now)
        ]
        let index = originalsFolder.appendingPathComponent("index.json")
        try JSONEncoder().encode(unsafeEntries).write(to: index)

        let versions = CaptureVersions(folder: originalsFolder)
        XCTAssertFalse(versions.hasOriginal(for: sourceWithTraversalEntry))
        XCTAssertFalse(versions.hasOriginal(for: sourceWithSymlinkEntry))
        versions.removeOriginal(of: sourceWithTraversalEntry)
        versions.removeOriginal(of: sourceWithSymlinkEntry)

        XCTAssertEqual(try Data(contentsOf: outsideFile), Data("outside".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlink.path))
    }
}
