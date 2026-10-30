import Foundation

/// When a planned feature is expected to land.
nonisolated enum FeatureTier: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Part of the first release.
    case core
    /// Planned soon after the first release.
    case next
    /// An optional idea that may or may not be built.
    case maybe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core: String(localized: "Core")
        case .next: String(localized: "Next")
        case .maybe: String(localized: "Maybe")
        }
    }
}
