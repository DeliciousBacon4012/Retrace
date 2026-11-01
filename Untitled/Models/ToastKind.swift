import Foundation

/// The kinds of toast, each with its own time on screen, set in Settings › Notifications.
nonisolated enum ToastKind: String, CaseIterable, Identifiable, Sendable {
    case textCopied
    case imageCopied
    case saved
    case recordingSaved
    /// Something didn't work or found nothing, such as "No text found".
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .textCopied: String(localized: "Text copied")
        case .imageCopied: String(localized: "Image copied")
        case .saved: String(localized: "Saved")
        case .recordingSaved: String(localized: "Recording saved")
        case .error: String(localized: "Problems")
        }
    }

    /// Seconds on screen until changed. Text stays longest, since it's read.
    var defaultSeconds: Int {
        switch self {
        case .textCopied: 8
        case .imageCopied: 3
        case .saved: 3
        case .recordingSaved: 5
        case .error: 6
        }
    }

    /// The times offered in Settings. Zero keeps the toast until it's clicked.
    static let secondsChoices = [2, 3, 5, 8, 10, 15, 30, 0]

    static func label(forSeconds seconds: Int) -> String {
        guard seconds > 0 else { return String(localized: "Until dismissed") }
        return Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .abbreviated))
    }
}

/// Where toasts appear on the screen.
nonisolated enum ToastPosition: String, CaseIterable, Identifiable, Sendable {
    case topCenter
    case topRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topCenter: String(localized: "Top center")
        case .topRight: String(localized: "Top right")
        }
    }
}
