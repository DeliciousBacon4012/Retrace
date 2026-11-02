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
    /// Saves Retina captures at standard size: one pixel per point.
    var standardSize: Bool
    /// Untitled's own floating windows to leave out (overlays, thumbnails, toasts), by window number.
    /// Its regular windows, like the editor, can be captured like any other app's.
    var excludedWindows: Set<CGWindowID> = []
}

/// A captured image and how many pixels it has per point.
struct CapturedFrame {
    let image: CGImage
    let scale: CGFloat
}

/// Takes still images of the screen.
protocol ScreenCapturing: AnyObject {
    /// Captures a whole display, or one area of it when `rect` is set.
    /// `rect` is in points, relative to the display's top-left corner.
    func captureDisplay(_ displayID: CGDirectDisplayID, rect: CGRect?, options: CaptureOptions) async throws -> CapturedFrame
    /// Captures one window by itself, without its shadow, at the display's full resolution.
    func captureWindow(_ windowID: CGWindowID, options: CaptureOptions) async throws -> CapturedFrame
}

/// Captures through ScreenCaptureKit at the display's native resolution (`.best`), so a
/// Retina screen gives two pixels per point unless standard size is asked for.
final class ScreenCaptureKitService: ScreenCapturing {
    func captureDisplay(_ displayID: CGDirectDisplayID, rect: CGRect?, options: CaptureOptions) async throws -> CapturedFrame {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let excluded = content.windows.filter { options.excludedWindows.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let scale = options.standardSize ? 1 : CGFloat(filter.pointPixelScale)

        let region = rect ?? CGRect(origin: .zero, size: filter.contentRect.size)
        let configuration = SCStreamConfiguration()
        configuration.captureResolution = .best
        if rect != nil {
            configuration.sourceRect = region
        }
        configuration.width = max(1, Int((region.width * scale).rounded()))
        configuration.height = max(1, Int((region.height * scale).rounded()))
        configuration.showsCursor = options.showsCursor
        configuration.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return CapturedFrame(image: image, scale: scale)
    }

    func captureWindow(_ windowID: CGWindowID, options: CaptureOptions) async throws -> CapturedFrame {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = options.standardSize ? 1 : CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.captureResolution = .best
        // The shadow is drawn afterwards (see WindowFrame), so the window keeps its full size here.
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.includeChildWindows = true
        configuration.showsCursor = options.showsCursor
        configuration.width = max(1, Int((filter.contentRect.width * scale).rounded()))
        configuration.height = max(1, Int((filter.contentRect.height * scale).rounded()))

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return CapturedFrame(image: image, scale: scale)
    }

    private func shareableContent() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }
        return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }
}
