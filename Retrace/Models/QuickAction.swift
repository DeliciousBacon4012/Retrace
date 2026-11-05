import Foundation

/// A one-click action offered on the Home screen and in the menus.
nonisolated struct QuickAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbolName: String
    /// The screenshot this action takes, or `nil` if it is not a screenshot action.
    var captureMode: CaptureMode?
    /// The recording this action starts or stops, or `nil` if it is not a recording action.
    var recordingMode: CaptureMode?

    /// Whether the action reads text from a selected area.
    var capturesText = false
    /// Whether the action captures the last selected area again.
    var repeatsArea = false
    /// Whether the action opens the clipboard's image in the editor.
    var opensClipboard = false

    /// Whether the action turns the replay buffer on or off.
    var togglesReplay = false
    /// Whether the action starts a screen recording, or discards the one running.
    var startsOrDiscardsRecording = false
    /// Whether the action stops the running recording and saves it.
    var savesRecording = false
    /// Whether the action saves the buffer's default length from Settings.
    var savesDefaultReplay = false

    /// Whether the action saves the replay buffer.
    var savesReplay = false
    /// For a Save Last action, how many seconds it saves. Nil saves the whole buffer.
    var saveLastSeconds: Int?

    /// Whether the action does anything yet.
    var isAvailable: Bool {
        captureMode != nil || capturesText || repeatsArea || opensClipboard || recordingMode != nil || savesReplay
            || togglesReplay || startsOrDiscardsRecording || savesRecording || savesDefaultReplay
    }

    /// Whether the action takes a screenshot of some kind.
    var isScreenshot: Bool { captureMode != nil || capturesText || repeatsArea }

    /// The screenshot actions, including Capture Text, for toolbars and the Capture page.
    static var screenshots: [QuickAction] { all.filter { $0.captureMode != nil || $0.capturesText } }
    static var recordings: [QuickAction] { all.filter { $0.recordingMode != nil } }

    static let all: [QuickAction] = [
        QuickAction(id: "captureArea", title: String(localized: "Capture Area"), symbolName: "rectangle.dashed", captureMode: .area),
        QuickAction(id: "capturePreviousArea", title: String(localized: "Capture Previous Area"), symbolName: "arrow.counterclockwise", repeatsArea: true),
        QuickAction(id: "captureWindow", title: String(localized: "Capture Window"), symbolName: "macwindow", captureMode: .window),
        QuickAction(id: "captureScreen", title: String(localized: "Capture Screen"), symbolName: "display", captureMode: .screen),
        QuickAction(id: "captureText", title: String(localized: "Capture Text"), symbolName: "text.viewfinder", capturesText: true),
        QuickAction(id: "recordArea", title: String(localized: "Record Area"), symbolName: "rectangle.dashed.badge.record", recordingMode: .area),
        QuickAction(id: "recordWindow", title: String(localized: "Record Window"), symbolName: "macwindow.badge.plus", recordingMode: .window),
        QuickAction(id: "recordScreen", title: String(localized: "Record Screen"), symbolName: "record.circle", recordingMode: .screen),
        QuickAction(id: "recordScreenOrDiscard", title: String(localized: "Start or Discard Screen Recording"), symbolName: "record.circle", startsOrDiscardsRecording: true),
        QuickAction(id: "saveRecording", title: String(localized: "Stop and Save Recording"), symbolName: "stop.circle", savesRecording: true),
        QuickAction(id: "toggleReplay", title: String(localized: "Turn Replay Buffer On or Off"), symbolName: "arrow.trianglehead.counterclockwise", togglesReplay: true),
        QuickAction(id: "saveReplayDefault", title: String(localized: "Save Replay (Default Length)"), symbolName: "gobackward", savesDefaultReplay: true),
        QuickAction(id: "saveReplay", title: String(localized: "Save Entire Buffer"), symbolName: "gobackward", savesReplay: true),
        QuickAction(id: "openClipboard", title: String(localized: "Open from Clipboard"), symbolName: "doc.on.clipboard", opensClipboard: true),
    ]

    /// Saves the last `seconds` of the replay buffer. One exists for each Save Last length,
    /// so each can have its own shortcut.
    static func saveLast(_ seconds: Int) -> QuickAction {
        let length = Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
        return QuickAction(id: "saveLast\(seconds)", title: String(localized: "Save Last \(length)"), symbolName: "gobackward", savesReplay: true, saveLastSeconds: seconds)
    }

    /// The action with `id`, including the Save Last lengths currently offered.
    static func withID(_ id: String, saveLastDurations: [Int]) -> QuickAction? {
        all.first { $0.id == id } ?? saveLastDurations.map(saveLast).first { $0.id == id }
    }
}
