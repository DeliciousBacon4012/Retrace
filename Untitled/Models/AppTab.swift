import Foundation

/// A page in the main window's sidebar: the capture home and recents first, then each
/// settings topic, so everything can be changed without opening a separate window.
nonisolated enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case capture
    case recents
    case general
    case captureOptions
    case output
    case quickAccess
    case recording
    case shortcuts
    case advanced

    var id: String { rawValue }

    static let primary: [AppTab] = [.capture, .recents]
    static let settings: [AppTab] = [.general, .captureOptions, .output, .quickAccess, .recording, .shortcuts, .advanced]

    var title: String {
        switch self {
        case .capture: String(localized: "Capture")
        case .recents: String(localized: "Recents")
        case .general: String(localized: "General")
        case .captureOptions: String(localized: "After Capture")
        case .output: String(localized: "Format and Output")
        case .quickAccess: String(localized: "Quick Access")
        case .recording: String(localized: "Recording")
        case .shortcuts: String(localized: "Shortcuts")
        case .advanced: String(localized: "Advanced")
        }
    }

    var symbolName: String {
        switch self {
        case .capture: "camera.viewfinder"
        case .recents: "clock"
        case .general: "gearshape"
        case .captureOptions: "checklist"
        case .output: "doc.badge.gearshape"
        case .quickAccess: "rectangle.stack"
        case .recording: "record.circle"
        case .shortcuts: "command"
        case .advanced: "slider.horizontal.3"
        }
    }
}
