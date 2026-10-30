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

    /// Whether the action saves the replay buffer.
    var savesReplay = false

    /// Whether the action does anything yet.
    var isAvailable: Bool { captureMode != nil || recordingMode != nil || savesReplay }

    /// The screenshot actions that work today, for toolbars and the Capture tab.
    static var screenshots: [QuickAction] { all.filter { $0.captureMode != nil } }
    static var recordings: [QuickAction] { all.filter { $0.recordingMode != nil } }

    static let all: [QuickAction] = [
        QuickAction(id: "captureArea", title: String(localized: "Capture Area"), symbolName: "rectangle.dashed", captureMode: .area),
        QuickAction(id: "captureWindow", title: String(localized: "Capture Window"), symbolName: "macwindow", captureMode: .window),
        QuickAction(id: "captureScreen", title: String(localized: "Capture Screen"), symbolName: "display", captureMode: .screen),
        QuickAction(id: "captureText", title: String(localized: "Capture Text"), symbolName: "text.viewfinder"),
        QuickAction(id: "recordArea", title: String(localized: "Record Area"), symbolName: "rectangle.dashed.badge.record", recordingMode: .area),
        QuickAction(id: "recordWindow", title: String(localized: "Record Window"), symbolName: "macwindow.badge.plus", recordingMode: .window),
        QuickAction(id: "recordScreen", title: String(localized: "Record Screen"), symbolName: "record.circle", recordingMode: .screen),
        QuickAction(id: "saveReplay", title: String(localized: "Save Replay"), symbolName: "gobackward", savesReplay: true),
    ]
}
