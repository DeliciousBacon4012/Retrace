import AppKit
import Observation
import OSLog

/// Runs a screenshot from start to finish: permission check, selection, capture,
/// then the after-capture actions chosen in Settings (save, copy, Quick Access).
@Observable
final class CaptureCoordinator {
    private(set) var isCapturing = false

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let permissions: any PermissionProviding
    @ObservationIgnored private let capturer: any ScreenCapturing
    @ObservationIgnored private let storage: any CaptureStoring
    @ObservationIgnored private let clipboard: any ClipboardWriting
    @ObservationIgnored private let quickAccess: QuickAccessController
    @ObservationIgnored private let editor: EditorPresenter
    @ObservationIgnored private let overlay = SelectionOverlay()

    init(
        settings: SettingsStore,
        permissions: any PermissionProviding,
        capturer: any ScreenCapturing,
        storage: any CaptureStoring,
        clipboard: any ClipboardWriting,
        quickAccess: QuickAccessController,
        editor: EditorPresenter
    ) {
        self.settings = settings
        self.permissions = permissions
        self.capturer = capturer
        self.storage = storage
        self.clipboard = clipboard
        self.quickAccess = quickAccess
        self.editor = editor
    }

    func capture(_ mode: CaptureMode) async {
        guard !isCapturing else { return }
        guard permissions.screenRecordingStatus == .granted else {
            permissions.requestScreenRecordingAccess()
            ErrorPresenter.present(CaptureError.permissionDenied, recovery: String(localized: "Turn on Untitled in System Settings › Privacy & Security › Screen & System Audio Recording, then try again."))
            return
        }

        isCapturing = true
        defer { isCapturing = false }

        do {
            guard let result = try await takeImage(mode) else {
                Log.capture.info("Capture cancelled")
                return
            }
            finish(CapturedImage(image: result.image, scale: result.scale, date: .now))
        } catch {
            Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
    }

    /// Returns `nil` when the person cancels the selection.
    private func takeImage(_ mode: CaptureMode) async throws -> (image: CGImage, scale: CGFloat)? {
        switch mode {
        case .screen:
            guard let screen = NSScreen.underPointer, let displayID = screen.displayID else {
                throw CaptureError.displayNotFound
            }
            let captureScale = scale(for: screen)
            let image = try await capturer.captureDisplay(displayID, rect: nil, options: options(scale: captureScale))
            return (image, captureScale)

        case .area:
            guard case .area(let rect, let screen)? = await overlay.select(.area) else { return nil }
            guard let displayID = screen.displayID else { throw CaptureError.displayNotFound }
            let captureScale = scale(for: screen)
            let image = try await capturer.captureDisplay(
                displayID,
                rect: screen.topLeftRelativeRect(for: rect),
                options: options(scale: captureScale)
            )
            return (image, captureScale)

        case .window:
            let candidates = WindowList.onScreenWindows()
            guard case .window(let window)? = await overlay.select(.window(candidates)) else { return nil }
            let screen = NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main
            let windowScale = screen.map { self.scale(for: $0) } ?? 2
            let image = try await capturer.captureWindow(window.id, options: options(scale: windowScale))
            return (image, windowScale)
        }
    }

    private func scale(for screen: NSScreen) -> CGFloat {
        settings.downscalesRetina ? 1 : screen.backingScaleFactor
    }

    private func options(scale: CGFloat) -> CaptureOptions {
        CaptureOptions(
            showsCursor: settings.includesCursor,
            includesWindowShadow: settings.includesWindowShadow,
            scale: scale
        )
    }

    // MARK: After capture

    private func finish(_ capture: CapturedImage) {
        var capture = capture
        if settings.savesToFolder {
            capture.fileURL = save(capture)
        }
        if settings.copiesToClipboard {
            clipboard.copy(capture.nsImage)
        }
        if settings.playsSounds {
            CaptureSound.play()
        }
        if settings.opensEditor {
            editor.open(capture)
        } else if settings.showsQuickAccess {
            quickAccess.show(capture)
        }
    }

    /// Saves to the chosen folder, falling back to Pictures/Untitled if that fails.
    private func save(_ capture: CapturedImage) -> URL? {
        let options = settings.exportOptions(for: capture.scale)
        let format = options.format
        let data: Data
        do {
            data = try ImageEncoder.data(for: capture.image, options: options, pointScale: capture.scale)
        } catch {
            Log.capture.error("Encoding failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
            return nil
        }

        let preferred = settings.saveFolderURL
        do {
            return try storage.save(data, template: settings.filenameTemplate, date: capture.date, fileExtension: format.fileExtension, in: preferred)
        } catch {
            Log.capture.error("Saving to the chosen folder failed: \(error.localizedDescription, privacy: .public)")
        }

        let fallback = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Untitled", isDirectory: true)
        guard let fallback, fallback.standardizedFileURL != preferred.standardizedFileURL else {
            ErrorPresenter.present(String(localized: "The screenshot couldn't be saved."), recovery: String(localized: "Choose another folder in Settings › Output. It's still on the clipboard if copying is on."))
            return nil
        }
        do {
            let url = try storage.save(data, template: settings.filenameTemplate, date: capture.date, fileExtension: format.fileExtension, in: fallback)
            ErrorPresenter.present(String(localized: "Saved to Pictures › Untitled instead."), recovery: String(localized: "The chosen folder couldn't be written to. You can pick another one in Settings › Output."))
            return url
        } catch {
            ErrorPresenter.present(error)
            return nil
        }
    }
}
