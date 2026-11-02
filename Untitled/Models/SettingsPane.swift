import Foundation

/// A tab of the Settings window. Each one gathers related topics, so the toolbar stays short.
nonisolated enum SettingsPane: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general
    case capture
    case quickAccess
    case notifications
    case editor
    case recording
    case shortcuts
    case advanced

    var id: String { rawValue }

    /// Where the open tab is remembered, so Settings reopens on it.
    static let storageKey = "settingsPane"

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .capture: String(localized: "Capture")
        case .quickAccess: String(localized: "Quick Access")
        case .notifications: String(localized: "Notifications")
        case .editor: String(localized: "Editor")
        case .recording: String(localized: "Recording")
        case .shortcuts: String(localized: "Shortcuts")
        case .advanced: String(localized: "Advanced")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .quickAccess: "rectangle.stack"
        case .notifications: "bell.badge"
        case .editor: "pencil.and.scribble"
        case .recording: "record.circle"
        case .shortcuts: "command"
        case .advanced: "slider.horizontal.3"
        }
    }
}
