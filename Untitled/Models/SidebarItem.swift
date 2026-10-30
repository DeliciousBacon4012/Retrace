import Foundation

/// A row in the main window's sidebar.
nonisolated enum SidebarItem: Hashable, Identifiable, Sendable {
    case home
    case area(FeatureArea)
    case roadmap

    var id: String {
        switch self {
        case .home: "home"
        case .area(let area): "area.\(area.rawValue)"
        case .roadmap: "roadmap"
        }
    }
}
