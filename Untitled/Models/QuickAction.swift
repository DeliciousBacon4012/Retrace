import Foundation

/// A one-click action offered on the Home screen and in the menus.
nonisolated struct QuickAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbolName: String
    /// The screenshot this action takes, or `nil` if it is not a screenshot action.
    var captureMode: CaptureMode?

    static let all: [QuickAction] = [
        QuickAction(id: "captureArea", title: String(localized: "Capture Area"), symbolName: "rectangle.dashed", captureMode: .area),
        QuickAction(id: "captureWindow", title: String(localized: "Capture Window"), symbolName: "macwindow", captureMode: .window),
        QuickAction(id: "captureScreen", title: String(localized: "Capture Screen"), symbolName: "display", captureMode: .screen),
        QuickAction(id: "captureText", title: String(localized: "Capture Text"), symbolName: "text.viewfinder"),
        QuickAction(id: "recordScreen", title: String(localized: "Record Screen"), symbolName: "record.circle"),
        QuickAction(id: "saveReplay", title: String(localized: "Save Replay"), symbolName: "gobackward"),
    ]
}
