import XCTest
@testable import Retrace

final class CaptureStorageTests: XCTestCase {
    func testCaptureStoragePreservesDataAndAvoidsOverwritingExistingFiles() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetraceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let storage = FileCaptureStorage()
        let payload = Data("capture-integrity".utf8)
        let date = Date(timeIntervalSince1970: 0)
        let first = try await storage.save(payload, template: "Integrity", date: date, fileExtension: "bin", in: folder)
        let second = try await storage.save(Data("second".utf8), template: "Integrity", date: date, fileExtension: "bin", in: folder)

        XCTAssertEqual(try Data(contentsOf: first), payload)
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "Integrity 2.bin")
    }
}
