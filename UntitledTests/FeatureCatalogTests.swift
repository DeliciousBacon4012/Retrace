import XCTest
@testable import Untitled

final class FeatureCatalogTests: XCTestCase {
    func testAvailableFeaturesAreMarkedAsCore() {
        XCTAssertTrue(FeatureCatalog.all.filter(\.isAvailable).allSatisfy { $0.tier == .core })
    }
}
