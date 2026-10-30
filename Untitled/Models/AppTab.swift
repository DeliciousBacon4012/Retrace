import Foundation

/// A tab in the main window. The system draws the tab bar, so it picks up
/// Liquid Glass and the person's accent color on its own.
nonisolated enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case capture
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: String(localized: "Capture")
        case .library: String(localized: "Library")
        }
    }

    var symbolName: String {
        switch self {
        case .capture: "camera.viewfinder"
        case .library: "photo.on.rectangle.angled"
        }
    }
}
