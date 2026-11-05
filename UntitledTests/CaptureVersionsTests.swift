import XCTest
@testable import Untitled

final class CaptureVersionsTests: XCTestCase {
    @MainActor
    func testCaptureVersionsPreservesOriginalBeforeEditedFileIsWritten() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetraceVersionsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = folder.appendingPathComponent("capture.png")
        let originalsFolder = folder.appendingPathComponent("originals", isDirectory: true)
        let originalData = Data("original-image-data".utf8)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try originalData.write(to: source)

        let versions = CaptureVersions(folder: originalsFolder)
        try await versions.preserveOriginal(of: source)

        XCTAssertTrue(versions.hasOriginal(for: source))
        let preserved = try XCTUnwrap(versions.original(for: source))
        XCTAssertEqual(try Data(contentsOf: preserved), originalData)

        try Data("edited-image-data".utf8).write(to: source)
        try await versions.preserveOriginal(of: source)

        XCTAssertEqual(try Data(contentsOf: preserved), originalData)
        XCTAssertEqual(try Data(contentsOf: source), Data("edited-image-data".utf8))
    }

    @MainActor
    func testCaptureVersionsDoesNotApproveSaveWhenIndexCannotBeWritten() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetraceVersionIndexTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = folder.appendingPathComponent("capture.png")
        let originalsFolder = folder.appendingPathComponent("originals", isDirectory: true)
        let originalData = Data("original-image-data".utf8)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try originalData.write(to: source)
        try FileManager.default.createDirectory(at: originalsFolder.appendingPathComponent("index.json", isDirectory: true), withIntermediateDirectories: true)

        let versions = CaptureVersions(folder: originalsFolder)
        var preservationError: Error?
        do {
            try await versions.preserveOriginal(of: source)
        } catch {
            preservationError = error
        }

        XCTAssertNotNil(preservationError)
        XCTAssertFalse(versions.hasOriginal(for: source))
        XCTAssertEqual(try Data(contentsOf: source), originalData)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: originalsFolder.path).sorted(), ["index.json"])
    }
}
