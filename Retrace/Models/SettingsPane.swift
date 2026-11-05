import Foundation

/// A Settings destination that gathers one related group of preferences.
nonisolated enum SettingsPane: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general
    case capture
    case quickAccess
    case clipboard
    case editor
    case recording
    case shortcuts
    case advanced

    var id: String { rawValue }

    /// The selected category is remembered so Settings reopens there.
    static let storageKey = "settingsPane"

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .capture: String(localized: "Capture")
        case .quickAccess: String(localized: "Overlays")
        case .clipboard: String(localized: "Clipboard")
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
        case .clipboard: "clipboard"
        case .editor: "pencil.and.scribble"
        case .recording: "record.circle"
        case .shortcuts: "command"
        case .advanced: "slider.horizontal.3"
        }
    }
}
