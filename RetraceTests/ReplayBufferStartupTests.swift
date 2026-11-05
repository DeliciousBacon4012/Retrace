import XCTest
@testable import Retrace

final class ReplayBufferStartupTests: XCTestCase {
    func testStopInvalidatesPendingStartupBeforeNewSessionStarts() {
        var generation = ReplayBufferGeneration()
        let pending = generation.begin()
        XCTAssertTrue(generation.accepts(pending))

        generation.invalidate()

        XCTAssertFalse(generation.accepts(pending))
        let current = generation.begin()
        XCTAssertTrue(generation.accepts(current))
        XCTAssertFalse(generation.accepts(pending))
    }
}
