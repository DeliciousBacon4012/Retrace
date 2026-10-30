import Foundation

import Observation

/// Filtering for the Roadmap table.
@Observable
final class RoadmapViewModel {
    var searchText = ""
    /// `nil` shows every tier.
    var tierFilter: FeatureTier?

    @ObservationIgnored private let features: [Feature]

    init(features: [Feature] = FeatureCatalog.all) {
        self.features = features
    }

    var filteredFeatures: [Feature] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return features.filter { feature in
            let matchesTier = tierFilter.map { feature.tier == $0 } ?? true
            let matchesQuery = query.isEmpty
                || feature.title.localizedCaseInsensitiveContains(query)
                || feature.area.title.localizedCaseInsensitiveContains(query)
            return matchesTier && matchesQuery
        }
    }
}
