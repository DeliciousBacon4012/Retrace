import XCTest
@testable import Retrace

final class RecordingTimerLogicTests: XCTestCase {
    func testElapsedTimeCountsNormallyBeforeBufferLimit() {
        let start = Date(timeIntervalSince1970: 1_000)
        let reading = RecordingTimerLogic.reading(
            since: start,
            now: start.addingTimeInterval(299),
            maximumDuration: 300
        )

        XCTAssertEqual(reading.displayedSeconds, 299)
        XCTAssertFalse(reading.reachedLimit)
        XCTAssertTrue(reading.pulseIsBright)
    }

    func testBufferTimerCapsAndPulsesAfterLimit() {
        let start = Date(timeIntervalSince1970: 1_000)
        let atLimit = RecordingTimerLogic.reading(
            since: start,
            now: start.addingTimeInterval(300),
            maximumDuration: 300
        )
        let halfSecondLater = RecordingTimerLogic.reading(
            since: start,
            now: start.addingTimeInterval(300.5),
            maximumDuration: 300
        )
        let later = RecordingTimerLogic.reading(
            since: start,
            now: start.addingTimeInterval(301),
            maximumDuration: 300
        )

        XCTAssertEqual(atLimit.displayedSeconds, 300)
        XCTAssertTrue(atLimit.reachedLimit)
        XCTAssertTrue(atLimit.pulseIsBright)
        XCTAssertEqual(halfSecondLater.displayedSeconds, 300)
        XCTAssertFalse(halfSecondLater.pulseIsBright)
        XCTAssertEqual(later.displayedSeconds, 300)
        XCTAssertTrue(later.reachedLimit)
        XCTAssertTrue(later.pulseIsBright)
    }

    func testUncappedRecordingKeepsCountingPastReplayDuration() {
        let start = Date(timeIntervalSince1970: 1_000)
        let reading = RecordingTimerLogic.reading(
            since: start,
            now: start.addingTimeInterval(3_661)
        )

        XCTAssertEqual(reading.displayedSeconds, 3_661)
        XCTAssertFalse(reading.reachedLimit)
    }
}
