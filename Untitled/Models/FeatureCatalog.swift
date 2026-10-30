import Foundation

/// The full list of planned features, shown in the Roadmap and on each area page.
///
/// Keep this in sync with the project plan. Flip `isAvailable` when a feature ships.
nonisolated enum FeatureCatalog {
    static let all: [Feature] = [
        // Screenshots
        Feature("capture.area", .capture, .core, String(localized: "Area capture with loupe and size readout")),
        Feature("capture.window", .capture, .core, String(localized: "Window capture with shadow and background options")),
        Feature("capture.screen", .capture, .core, String(localized: "Full screen and all-displays capture")),
        Feature("capture.repeat", .capture, .core, String(localized: "Repeat the last area")),
        Feature("capture.keys", .capture, .core, String(localized: "Keyboard controls while selecting")),
        Feature("capture.freeze", .capture, .core, String(localized: "Freeze the screen while selecting")),
        Feature("capture.timer", .capture, .next, String(localized: "Timed capture")),
        Feature("capture.snap", .capture, .next, String(localized: "Snap selection to windows and UI elements")),
        Feature("capture.presets", .capture, .next, String(localized: "Fixed-size and aspect-ratio presets")),
        Feature("capture.scrolling", .capture, .next, String(localized: "Scrolling capture")),
        Feature("capture.hideDesktop", .capture, .next, String(localized: "Hide desktop icons during capture")),
        Feature("capture.appWindows", .capture, .maybe, String(localized: "Capture every window of one app")),

        // Quick Access
        Feature("quick.thumbnail", .quickAccess, .core, String(localized: "Floating thumbnail after each capture")),
        Feature("quick.drag", .quickAccess, .core, String(localized: "Drag captures into any app")),
        Feature("quick.actions", .quickAccess, .core, String(localized: "Copy, save, annotate, pin, and delete buttons")),
        Feature("quick.autoClose", .quickAccess, .core, String(localized: "Auto-close after a delay")),
        Feature("quick.position", .quickAccess, .next, String(localized: "Choose overlay corner and size")),
        Feature("quick.share", .quickAccess, .next, String(localized: "Share sheet and AirDrop")),
        Feature("quick.restore", .quickAccess, .maybe, String(localized: "Restore the last closed capture")),

        // Clipboard
        Feature("clipboard.copy", .clipboard, .core, String(localized: "Copy to clipboard after capture")),
        Feature("clipboard.annotate", .clipboard, .core, String(localized: "Annotate the image on the clipboard")),
        Feature("clipboard.asFile", .clipboard, .core, String(localized: "Copy as image or as file")),
        Feature("clipboard.markdown", .clipboard, .next, String(localized: "Copy as Markdown or HTML")),
        Feature("clipboard.history", .clipboard, .maybe, String(localized: "Image clipboard history")),

        // Editor
        Feature("editor.tools", .editor, .core, String(localized: "Arrow, shapes, text, pen, highlighter, steps, blur, crop")),
        Feature("editor.inspector", .editor, .core, String(localized: "Inspector shows only the selected tool's options")),
        Feature("editor.editable", .editor, .core, String(localized: "Editable annotations with undo and redo")),
        Feature("editor.spotlight", .editor, .next, String(localized: "Spotlight, magnifier, and smart redact")),
        Feature("editor.background", .editor, .next, String(localized: "Padding, rounded corners, shadow, and backdrops")),
        Feature("editor.transform", .editor, .next, String(localized: "Rotate, flip, resize, and expand canvas")),
        Feature("editor.projects", .editor, .next, String(localized: "Save editable project files")),
        Feature("editor.combine", .editor, .maybe, String(localized: "Combine several captures")),
        Feature("editor.lift", .editor, .maybe, String(localized: "Remove the background from a subject")),

        // Recording
        Feature("record.sources", .recording, .core, String(localized: "Record an area, a window, or a display")),
        Feature("record.encoding", .recording, .core, String(localized: "H.264 or HEVC at 30 or 60 fps")),
        Feature("record.audio", .recording, .core, String(localized: "System audio and microphone")),
        Feature("record.controls", .recording, .core, String(localized: "Pause, resume, countdown, and menu bar timer")),
        Feature("record.crashSafe", .recording, .core, String(localized: "Crash-safe recordings")),
        Feature("record.trim", .recording, .next, String(localized: "Trim editor and GIF export")),
        Feature("record.clicks", .recording, .next, String(localized: "Show clicks and keystrokes")),
        Feature("record.webcam", .recording, .next, String(localized: "Webcam overlay")),
        Feature("record.presets", .recording, .next, String(localized: "Quality presets and limits")),
        Feature("record.highFPS", .recording, .maybe, String(localized: "120 fps on ProMotion displays")),

        // Replay Buffer
        Feature("replay.buffer", .replayBuffer, .core, String(localized: "Keep the last 15 seconds to 10 minutes")),
        Feature("replay.segments", .replayBuffer, .core, String(localized: "Rolling on-disk segments with flat memory use")),
        Feature("replay.caps", .replayBuffer, .core, String(localized: "Disk caps and low-space warnings")),
        Feature("replay.indicator", .replayBuffer, .core, String(localized: "Always-visible indicator while running")),
        Feature("replay.lengths", .replayBuffer, .next, String(localized: "Save a chosen length on demand")),
        Feature("replay.autoStart", .replayBuffer, .next, String(localized: "Start at login or when an app opens")),
        Feature("replay.pause", .replayBuffer, .next, String(localized: "Pause on battery, idle, or lock")),
        Feature("replay.markers", .replayBuffer, .maybe, String(localized: "Markers while the buffer runs")),

        // Library
        Feature("library.history", .library, .core, String(localized: "History of every capture and recording")),
        Feature("library.search", .library, .next, String(localized: "Search by text inside images")),
        Feature("library.filter", .library, .next, String(localized: "Filters, tags, and favorites")),
        Feature("library.cleanup", .library, .next, String(localized: "Auto-delete with a restorable trash")),

        // Shelf
        Feature("shelf.floating", .shelf, .next, String(localized: "Floating shelf at the screen edge")),
        Feature("shelf.zones", .shelf, .next, String(localized: "Custom drop zones")),
        Feature("shelf.menuBarDrop", .shelf, .next, String(localized: "Drop files on the menu bar icon")),
        Feature("shelf.convert", .shelf, .maybe, String(localized: "Convert and compress on drop")),

        // iCloud and Storage
        Feature("storage.folder", .storage, .core, String(localized: "Save folder and filename template")),
        Feature("storage.formats", .storage, .core, String(localized: "PNG, JPEG, HEIC, TIFF, and PDF")),
        Feature("storage.icloud", .storage, .next, String(localized: "Save to iCloud Drive")),
        Feature("storage.settingsSync", .storage, .next, String(localized: "Sync settings across Macs")),
        Feature("storage.uploads", .storage, .maybe, String(localized: "Custom upload destinations")),

        // Utilities
        Feature("util.ocr", .utilities, .next, String(localized: "Capture text from the screen")),
        Feature("util.pin", .utilities, .next, String(localized: "Pin a capture on top of other windows")),
        Feature("util.colorPicker", .utilities, .next, String(localized: "Color picker")),
        Feature("util.qr", .utilities, .maybe, String(localized: "QR and barcode reader")),
        Feature("util.ruler", .utilities, .maybe, String(localized: "Pixel ruler")),
        Feature("util.drawOnScreen", .utilities, .maybe, String(localized: "Draw on screen live")),
    ]

    static func features(in area: FeatureArea) -> [Feature] {
        all.filter { $0.area == area }
    }
}
