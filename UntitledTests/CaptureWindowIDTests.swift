import AppKit
import XCTest
@testable import Untitled

final class CaptureWindowIDTests: XCTestCase {
    func testAcceptsRepresentableWindowNumbers() {
        XCTAssertEqual(CaptureWindowID.fromAppKitWindowNumber(1), CGWindowID(1))
        XCTAssertEqual(
            CaptureWindowID.fromAppKitWindowNumber(Int(CGWindowID.max)),
            CGWindowID.max
        )
    }

    func testRejectsUnrepresentableAndNullWindowNumbers() {
        XCTAssertNil(CaptureWindowID.fromAppKitWindowNumber(-1))
        XCTAssertNil(CaptureWindowID.fromAppKitWindowNumber(0))
        XCTAssertNil(CaptureWindowID.fromAppKitWindowNumber(Int(CGWindowID.max) + 1))
    }
}
