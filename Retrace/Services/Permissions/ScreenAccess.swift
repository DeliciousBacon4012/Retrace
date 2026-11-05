import CoreGraphics
import Foundation
import os
import ScreenCaptureKit

/// Whether Retrace may capture the screen.
///
/// `CGPreflightScreenCaptureAccess` alone isn't enough: on recent macOS it can keep answering
/// no for the life of the process even after access is granted, while ScreenCaptureKit itself
/// works. So a successful ScreenCaptureKit query also counts, and is remembered.
nonisolated enum ScreenAccess {
    private static let confirmedThisLaunch = OSAllocatedUnfairLock(initialState: false)
    private static let rememberedKey = "screenAccessConfirmed"

    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess() || confirmedThisLaunch.withLock { $0 }
    }

    /// Whether access worked at some point before, so it's worth checking quietly at launch.
    static var wasConfirmedBefore: Bool {
        UserDefaults.standard.bool(forKey: rememberedKey)
    }

    /// Asks ScreenCaptureKit directly. If access was never granted, macOS may show its own prompt,
    /// so call this when the person acts, or at launch only if access worked before.
    static func confirm() async -> Bool {
        if isGranted { return true }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard !content.displays.isEmpty else { return false }
            confirmedThisLaunch.withLock { $0 = true }
            UserDefaults.standard.set(true, forKey: rememberedKey)
            Log.permissions.info("ScreenCaptureKit confirmed access on \(content.displays.count, privacy: .public) displays")
            return true
        } catch {
            Log.permissions.info("ScreenCaptureKit check failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
