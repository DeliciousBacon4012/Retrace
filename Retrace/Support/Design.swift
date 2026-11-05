import AppKit
import SwiftUI

/// Shared spacing, corner radii, and motion, so every screen lines up and moves the same way.
enum Design {
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 14
    static let radiusL: CGFloat = 20
}

extension Animation {
    /// Direct feedback such as selection and toggles: quick and settled, no overshoot.
    static let response = Animation.snappy(duration: 0.28)
    /// Panels and cards arriving: a soft spring with a little give.
    static let panel = Animation.smooth(duration: 0.42, extraBounce: 0.08)
    /// Something the user just made, like a new mark: a lively pop.
    static let pop = Animation.bouncy(duration: 0.38, extraBounce: 0.12)
}

/// Trackpad feedback, using Apple's patterns for the Mac. Silent without a Force Touch trackpad.
enum Haptics {
    /// Something dragged lined up or reached its limit: a zoom stop, a docked panel.
    static func alignment() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    /// Anything else worth feeling, like landing on a page or flicking a thumbnail away.
    static func generic() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
}
