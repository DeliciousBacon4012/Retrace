import Foundation

/// How long clipboard history and captured-text history keep things. Forever unless you
/// choose otherwise; both offer the same choices, in the same order.
nonisolated enum HistoryRetention: String, CaseIterable, Identifiable, Sendable {
    case forever
    case week
    case twoWeeks
    case month
    case threeMonths
    case items50
    case items100
    case items250
    case items500

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forever: String(localized: "Forever")
        case .week: String(localized: "1 Week")
        case .twoWeeks: String(localized: "14 Days")
        case .month: String(localized: "30 Days")
        case .threeMonths: String(localized: "90 Days")
        case .items50: String(localized: "Last 50 Items")
        case .items100: String(localized: "Last 100 Items")
        case .items250: String(localized: "Last 250 Items")
        case .items500: String(localized: "Last 500 Items")
        }
    }

    /// Items older than this are removed.
    var maximumAge: TimeInterval? {
        let day: TimeInterval = 86_400
        switch self {
        case .week: return 7 * day
        case .twoWeeks: return 14 * day
        case .month: return 30 * day
        case .threeMonths: return 90 * day
        default: return nil
        }
    }

    /// Only this many of the newest items are kept.
    var maximumCount: Int? {
        switch self {
        case .items50: 50
        case .items100: 100
        case .items250: 250
        case .items500: 500
        default: nil
        }
    }

    /// Whether this choice is a time limit, for grouping in Settings.
    var isTimeLimit: Bool { maximumAge != nil }
}
