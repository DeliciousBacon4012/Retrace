import CoreMedia
import XCTest
@testable import Retrace

final class RecordingPolicyTests: XCTestCase {
    func testRecordingStartupCancelsBeforeCaptureWhenStopWasRequested() {
        XCTAssertTrue(RecordingStartupPolicy.shouldCancelBeforeStartCapture(stopRequested: true, taskCancelled: false))
        XCTAssertTrue(RecordingStartupPolicy.shouldCancelBeforeStartCapture(stopRequested: false, taskCancelled: true))
        XCTAssertFalse(RecordingStartupPolicy.shouldCancelBeforeStartCapture(stopRequested: false, taskCancelled: false))
    }

    func testRecordingStartupStopsAfterCaptureWhenStopArrivesInFlight() {
        XCTAssertTrue(RecordingStartupPolicy.shouldStopAfterStart(
            stopRequested: true,
            taskCancelled: false,
            outputAlreadyCompleted: false
        ))
        XCTAssertTrue(RecordingStartupPolicy.shouldStopAfterStart(
            stopRequested: false,
            taskCancelled: true,
            outputAlreadyCompleted: false
        ))
        XCTAssertTrue(RecordingStartupPolicy.shouldStopAfterStart(
            stopRequested: false,
            taskCancelled: false,
            outputAlreadyCompleted: true
        ))
        XCTAssertFalse(RecordingStartupPolicy.shouldStopAfterStart(
            stopRequested: false,
            taskCancelled: false,
            outputAlreadyCompleted: false
        ))
    }

    func testRecordingOutputRequiresExistingNonemptyFileAndPositiveDuration() {
        XCTAssertTrue(RecordingOutputValidation.isUsable(
            fileExists: true,
            byteCount: 128,
            duration: CMTime(value: 1, timescale: 1)
        ))
        XCTAssertFalse(RecordingOutputValidation.isUsable(
            fileExists: false,
            byteCount: 128,
            duration: CMTime(value: 1, timescale: 1)
        ))
        XCTAssertFalse(RecordingOutputValidation.isUsable(
            fileExists: true,
            byteCount: 0,
            duration: CMTime(value: 1, timescale: 1)
        ))
        XCTAssertFalse(RecordingOutputValidation.isUsable(
            fileExists: true,
            byteCount: 128,
            duration: .zero
        ))
        XCTAssertFalse(RecordingOutputValidation.isUsable(
            fileExists: true,
            byteCount: 128,
            duration: .invalid
        ))
    }
}
