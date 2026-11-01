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
    @ObservationIgnored private let toast = CaptureToastController()
    /// The last area selected, for Capture Previous Area.
    @ObservationIgnored private var lastArea: (rect: CGRect, screen: NSScreen)?

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

    /// Runs a screenshot quick action, including Capture Text.
    func run(_ action: QuickAction) async {
        if let mode = action.captureMode {
            await capture(mode)
        } else if action.capturesText {
            await captureText()
        } else if action.repeatsArea {
            await capturePreviousArea()
        }
    }

    /// Captures the same area as last time without selecting it again.
    func capturePreviousArea() async {
        guard let lastArea, NSScreen.screens.contains(lastArea.screen) else {
            await capture(.area)
            return
        }
        guard !isCapturing, hasPermission() else { return }
        isCapturing = true
        defer { isCapturing = false }
        do {
            guard let displayID = lastArea.screen.displayID else { throw CaptureError.displayNotFound }
            let captureScale = scale(for: lastArea.screen)
            let image = try await capturer.captureDisplay(
                displayID,
                rect: lastArea.screen.topLeftRelativeRect(for: lastArea.rect),
                options: options(scale: captureScale)
            )
            finish(CapturedImage(image: image, scale: captureScale, date: .now))
        } catch {
            Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
    }

    /// Opens the image on the clipboard in the editor, from any app.
    func openFromClipboard() {
        let pasteboard = NSPasteboard.general
        let image: NSImage?
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first,
           let fileImage = NSImage(contentsOf: url) {
            image = fileImage
        } else {
            image = NSImage(pasteboard: pasteboard)
        }
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            toast.show(.init(symbolName: "clipboard", title: String(localized: "No image on the clipboard"), detail: String(localized: "Copy an image, then try again.")))
            return
        }
        let scale = image.size.width > 0 ? max(CGFloat(cgImage.width) / image.size.width, 1) : 1
        editor.open(CapturedImage(image: cgImage, scale: scale, date: .now))
    }

    func capture(_ mode: CaptureMode) async {
        guard !isCapturing, hasPermission() else { return }

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

    /// Reads the text in a selected area, copies it, and shows what was copied.
    /// QR codes and barcodes are read too; a web link gets an Open button.
    func captureText() async {
        guard !isCapturing, hasPermission() else { return }
        isCapturing = true

        do {
            let image: CGImage
            do {
                // Capture buttons come back as soon as the area is taken; reading runs on its own.
                defer { isCapturing = false }
                guard let result = try await takeImage(.area) else { return }
                image = result.image
            }
            Log.capture.info("Reading text from a \(image.width, privacy: .public)×\(image.height, privacy: .public) area")
            let content = try await TextRecognizer.recognize(image)
            if settings.playsSounds {
                CaptureSound.play()
            }
            showTextResult(content)
        } catch {
            Log.capture.error("Text capture failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
    }

    private func showTextResult(_ content: RecognizedContent) {
        guard !content.isEmpty else {
            toast.show(.init(symbolName: "text.magnifyingglass", title: String(localized: "No text found"), detail: String(localized: "Try a larger or sharper area.")))
            return
        }
        let copied = content.lines.isEmpty ? content.codes.joined(separator: "\n") : content.text
        clipboard.copy(text: copied)

        let title: String
        if content.lines.isEmpty {
            title = String(localized: "Copied code contents")
        } else if content.lines.count == 1 {
            title = String(localized: "Copied 1 line")
        } else {
            title = String(localized: "Copied \(content.lines.count) lines")
        }
        let detail = copied.split(whereSeparator: \.isNewline).first.map(String.init)
        if let link = content.link {
            toast.show(.init(symbolName: "qrcode.viewfinder", title: title, detail: link.absoluteString, actionTitle: String(localized: "Open Link")) {
                NSWorkspace.shared.open(link)
            })
        } else {
            toast.show(.init(symbolName: "text.viewfinder", title: title, detail: detail))
        }
    }

    private func hasPermission() -> Bool {
        guard permissions.screenRecordingStatus == .granted else {
            permissions.requestScreenRecordingAccess()
            ErrorPresenter.present(CaptureError.permissionDenied, recovery: String(localized: "Turn on Untitled in System Settings › Privacy & Security › Screen & System Audio Recording, then try again."))
            return false
        }
        return true
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
            lastArea = (rect, screen)
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
    func save(_ capture: CapturedImage) -> URL? {
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
            ErrorPresenter.present(String(localized: "The screenshot couldn't be saved."), recovery: String(localized: "Choose another folder in Settings › Files & Privacy. It's still on the clipboard if copying is on."))
            return nil
        }
        do {
            let url = try storage.save(data, template: settings.filenameTemplate, date: capture.date, fileExtension: format.fileExtension, in: fallback)
            ErrorPresenter.present(String(localized: "Saved to Pictures › Untitled instead."), recovery: String(localized: "The chosen folder couldn't be written to. You can pick another one in Settings › Files & Privacy."))
            return url
        } catch {
            ErrorPresenter.present(error)
            return nil
        }
    }
}
