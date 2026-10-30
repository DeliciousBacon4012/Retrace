import Foundation

/// A tab in the main window's tab bar.
nonisolated enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case capture
    case record
    case library
    case roadmap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .capture: String(localized: "Capture")
        case .record: String(localized: "Record")
        case .library: String(localized: "Library")
        case .roadmap: String(localized: "Roadmap")
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house"
        case .capture: "camera.viewfinder"
        case .record: "record.circle"
        case .library: "photo.on.rectangle.angled"
        case .roadmap: "map"
        }
    }

    /// The feature areas shown on this tab's page.
    var areas: [FeatureArea] {
        switch self {
        case .home, .roadmap: []
        case .capture: [.capture, .quickAccess, .clipboard, .editor]
        case .record: [.recording, .replayBuffer]
        case .library: [.library, .shelf, .storage, .utilities]
        }
    }
}
