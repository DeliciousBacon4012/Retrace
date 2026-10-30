import Foundation

/// A top-level area of the app. Each area gets a sidebar row and groups related features.
nonisolated enum FeatureArea: String, CaseIterable, Identifiable, Hashable, Sendable {
    case capture
    case quickAccess
    case clipboard
    case editor
    case recording
    case replayBuffer
    case library
    case shelf
    case storage
    case utilities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: String(localized: "Screenshots")
        case .quickAccess: String(localized: "Quick Access")
        case .clipboard: String(localized: "Clipboard")
        case .editor: String(localized: "Editor")
        case .recording: String(localized: "Recording")
        case .replayBuffer: String(localized: "Replay Buffer")
        case .library: String(localized: "Library")
        case .shelf: String(localized: "Shelf")
        case .storage: String(localized: "iCloud and Storage")
        case .utilities: String(localized: "Utilities")
        }
    }

    var symbolName: String {
        switch self {
        case .capture: "camera.viewfinder"
        case .quickAccess: "rectangle.stack"
        case .clipboard: "doc.on.clipboard"
        case .editor: "pencil.and.outline"
        case .recording: "record.circle"
        case .replayBuffer: "gobackward"
        case .library: "photo.on.rectangle.angled"
        case .shelf: "tray.and.arrow.down"
        case .storage: "icloud"
        case .utilities: "wrench.and.screwdriver"
        }
    }

    var summary: String {
        switch self {
        case .capture:
            String(localized: "Capture an area, a window, or the whole screen with pixel-exact selection.")
        case .quickAccess:
            String(localized: "A small floating thumbnail after every capture, ready to drag, copy, or edit.")
        case .clipboard:
            String(localized: "Copy every capture to the clipboard and open images straight from it.")
        case .editor:
            String(localized: "Annotate with arrows, shapes, text, blur, and more, without the clutter.")
        case .recording:
            String(localized: "Record the screen with system audio and microphone, hardware encoded.")
        case .replayBuffer:
            String(localized: "Keep the last few minutes in the background and save them with one shortcut.")
        case .library:
            String(localized: "Every capture and recording in one place, searchable by the text inside.")
        case .shelf:
            String(localized: "Drop zones and a floating shelf for moving files where they need to go.")
        case .storage:
            String(localized: "Save to any folder or to iCloud Drive, in the format you choose.")
        case .utilities:
            String(localized: "Capture text, pin images to the screen, pick colors, and more.")
        }
    }
}
