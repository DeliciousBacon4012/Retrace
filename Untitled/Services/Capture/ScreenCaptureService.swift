import AppKit
import OSLog
import ScreenCaptureKit

/// Why a capture could not finish.
nonisolated enum CaptureError: LocalizedError, Sendable {
    case permissionDenied
    case displayNotFound
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            String(localized: "Untitled doesn't have Screen Recording access yet.")
        case .displayNotFound:
            String(localized: "That display is no longer connected.")
        case .windowNotFound:
            String(localized: "That window closed before it could be captured.")
        }
    }
}

/// How a capture should look.
nonisolated struct CaptureOptions: Sendable {
    var showsCursor: Bool
    var includesWindowShadow: Bool
    /// Pixels per point. 1 saves Retina captures at standard size.
    var scale: CGFloat
}

/// Takes still images of the screen.
protocol ScreenCapturing: AnyObject {
    /// Captures a whole display, or one area of it when `rect` is set.
    /// `rect` is in points, relative to the display's top-left corner.
    func captureDisplay(_ displayID: CGDirectDisplayID, rect: CGRect?, options: CaptureOptions) async throws -> CGImage
    func captureWindow(_ windowID: CGWindowID, options: CaptureOptions) async throws -> CGImage
}

/// Captures through ScreenCaptureKit. Untitled's own windows (overlays, thumbnails)
/// are always left out of display captures.
final class ScreenCaptureKitService: ScreenCapturing {
    func captureDisplay(_ displayID: CGDirectDisplayID, rect: CGRect?, options: CaptureOptions) async throws -> CGImage {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownProcess }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let region = rect ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let configuration = SCStreamConfiguration()
        if rect != nil {
            configuration.sourceRect = region
        }
        configuration.width = max(1, Int((region.width * options.scale).rounded()))
        configuration.height = max(1, Int((region.height * options.scale).rounded()))
        configuration.showsCursor = options.showsCursor

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    func captureWindow(_ windowID: CGWindowID, options: CaptureOptions) async throws -> CGImage {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.ignoreShadowsSingleWindow = !options.includesWindowShadow
        configuration.showsCursor = options.showsCursor
        configuration.width = max(1, Int((filter.contentRect.width * options.scale).rounded()))
        configuration.height = max(1, Int((filter.contentRect.height * options.scale).rounded()))

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func shareableContent() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }
        return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }
}
