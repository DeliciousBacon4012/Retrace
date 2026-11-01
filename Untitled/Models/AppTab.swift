import Foundation

/// A page in the main window's sidebar: the capture home and recents first, then each
/// settings topic, so everything can be changed without opening a separate window.
nonisolated enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case capture
    case recents
    case general
    case captureSettings
    case afterCapture
    case editor
    case filesAndPrivacy
    case quickAccess
    case notifications
    case recording
    case replayBuffer
    case shortcuts
    case advanced

    var id: String { rawValue }

    static let primary: [AppTab] = [.capture, .recents]
    static let settings: [AppTab] = [
        .general, .captureSettings, .afterCapture, .editor, .filesAndPrivacy, .quickAccess,
        .notifications, .recording, .replayBuffer, .shortcuts, .advanced,
    ]

    var title: String {
        switch self {
        case .capture: String(localized: "Capture")
        case .recents: String(localized: "Recents")
        case .general: String(localized: "General")
        case .captureSettings: String(localized: "Capture")
        case .afterCapture: String(localized: "After Capture")
        case .editor: String(localized: "Editor")
        case .filesAndPrivacy: String(localized: "Files & Privacy")
        case .quickAccess: String(localized: "Quick Access")
        case .notifications: String(localized: "Notifications")
        case .recording: String(localized: "Recording")
        case .replayBuffer: String(localized: "Replay Buffer")
        case .shortcuts: String(localized: "Shortcuts")
        case .advanced: String(localized: "Advanced")
        }
    }

    var symbolName: String {
        switch self {
        case .capture: "camera.viewfinder"
        case .recents: "clock"
        case .general: "gearshape"
        case .captureSettings: "camera"
        case .afterCapture: "checklist"
        case .editor: "pencil.and.scribble"
        case .filesAndPrivacy: "lock.doc"
        case .quickAccess: "rectangle.stack"
        case .notifications: "bell.badge"
        case .recording: "record.circle"
        case .replayBuffer: "gobackward"
        case .shortcuts: "command"
        case .advanced: "slider.horizontal.3"
        }
    }
}
