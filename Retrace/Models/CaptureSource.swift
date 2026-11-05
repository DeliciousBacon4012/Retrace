import Foundation

/// The capture mode for a saved screenshot. Older files and images copied into a Library
/// location may have no source value and remain available under Images.
nonisolated enum CaptureSource: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case area
    case window
    case fullScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: String(localized: "Area Screenshots")
        case .window: String(localized: "Window Screenshots")
        case .fullScreen: String(localized: "Full Screen")
        }
    }

    static func screenshot(for mode: CaptureMode) -> CaptureSource {
        switch mode {
        case .area: .area
        case .window: .window
        case .screen: .fullScreen
        }
    }
}
