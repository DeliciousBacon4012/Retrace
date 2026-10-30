import Foundation

/// One planned or shipped capability of the app.
nonisolated struct Feature: Identifiable, Hashable, Sendable {
    let id: String
    let area: FeatureArea
    let tier: FeatureTier
    let title: String
    let isAvailable: Bool

    init(_ id: String, _ area: FeatureArea, _ tier: FeatureTier, _ title: String, isAvailable: Bool = false) {
        self.id = id
        self.area = area
        self.tier = tier
        self.title = title
        self.isAvailable = isAvailable
    }
}
