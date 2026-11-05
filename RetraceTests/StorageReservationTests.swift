import XCTest
@testable import Retrace

final class StorageReservationTests: XCTestCase {
    func testConcurrentReservationsReturnDistinctURLs() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Retrace-reservations-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = FileCaptureStorage()
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        async let first = storage.reserveURL(
            template: "Retrace {date} at {time}",
            date: date,
            fileExtension: "mov",
            in: folder
        )
        async let second = storage.reserveURL(
            template: "Retrace {date} at {time}",
            date: date,
            fileExtension: "mov",
            in: folder
        )
        let urls = try await [first, second]

        XCTAssertEqual(Set(urls.map(\.path)).count, 2)
        XCTAssertTrue(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }
}
