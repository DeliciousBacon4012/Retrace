import AppKit
import Observation
import OSLog

/// Runs a screenshot from start to finish: permission check, selection, capture,
/// then the after-capture actions chosen in Settings (save, copy, Quick Access).
nonisolated enum CaptureWindowID {
    /// AppKit can report sentinel or wider-than-32-bit numbers for windows such as menu bar items.
    /// Core Graphics window IDs are UInt32, so convert exactly and ignore values it cannot represent.
    static func fromAppKitWindowNumber(_ number: Int) -> CGWindowID? {
        guard let windowID = CGWindowID(exactly: number), windowID != kCGNullWindowID else {
            return nil
        }
        return windowID
    }
}

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
    @ObservationIgnored private let toast: CaptureToastController
    @ObservationIgnored private let textHistory: TextHistory
    /// The last area selected, for Capture Previous Area.
    @ObservationIgnored private var lastArea: (rect: CGRect, screen: NSScreen)?

    init(
        settings: SettingsStore,
        permissions: any PermissionProviding,
        capturer: any ScreenCapturing,
        storage: any CaptureStoring,
        clipboard: any ClipboardWriting,
        quickAccess: QuickAccessController,
        editor: EditorPresenter,
        toasts: CaptureToastController,
        textHistory: TextHistory
    ) {
        self.settings = settings
        self.permissions = permissions
        self.capturer = capturer
        self.storage = storage
        self.clipboard = clipboard
        self.quickAccess = quickAccess
        self.editor = editor
        toast = toasts
        self.textHistory = textHistory
    }

    /// Runs a screenshot quick action, including Capture Text.
    func run(_ action: QuickAction, savingTo folder: URL? = nil) async {
        if let mode = action.captureMode {
            await capture(mode, savingTo: folder)
        } else if action.capturesText {
            await captureText()
        } else if action.repeatsArea {
            await capturePreviousArea(savingTo: folder)
        }
    }

    /// Captures the same area as last time without selecting it again.
    func capturePreviousArea(savingTo folder: URL? = nil) async {
        guard let lastArea, NSScreen.screens.contains(lastArea.screen) else {
            await capture(.area, savingTo: folder)
            return
        }
        guard await claimCapture() else { return }
        defer { isCapturing = false }
        do {
            guard let displayID = lastArea.screen.displayID else { throw CaptureError.displayNotFound }
            let frame = try await capturer.captureDisplay(
                displayID,
                rect: lastArea.screen.topLeftRelativeRect(for: lastArea.rect),
                options: options()
            )
            await finish(CapturedImage(image: frame.image, scale: frame.scale, date: .now), savingTo: folder)
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
            toast.show(.init(kind: .error, symbolName: "clipboard", title: String(localized: "No image on the clipboard"), detail: String(localized: "Copy an image, then try again.")))
            return
        }
        let scale = image.size.width > 0 ? max(CGFloat(cgImage.width) / image.size.width, 1) : 1
        editor.open(CapturedImage(image: cgImage, scale: scale, date: .now))
    }

    func capture(_ mode: CaptureMode, savingTo folder: URL? = nil) async {
        guard await claimCapture() else { return }
        defer { isCapturing = false }

        do {
            guard let frame = try await takeImage(mode) else {
                Log.capture.info("Capture cancelled")
                return
            }
            await finish(CapturedImage(image: frame.image, scale: frame.scale, date: .now), savingTo: folder)
        } catch {
            Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
    }

    /// Reads the text in a selected area, copies it, and shows what was copied.
    /// QR codes and barcodes are read too; a web link gets an Open button.
    ///
    /// The area is read the way the editor reads it: at full resolution, without the
    /// pointer, with a few points of margin so letters at the edge stay whole, and
    /// enlarged first when it's only a line or two tall.
    func captureText() async {
        guard await claimCapture() else { return }

        do {
            let image: CGImage
            do {
                // Capture buttons come back as soon as the area is taken; reading runs on its own.
                defer { isCapturing = false }
                guard case .area(let rect, let screen)? = await overlay.select(.area) else { return }
                guard let displayID = screen.displayID else { throw CaptureError.displayNotFound }
                let padded = rect.insetBy(dx: -4, dy: -4).intersection(screen.frame)
                let frame = try await capturer.captureDisplay(
                    displayID,
                    rect: screen.topLeftRelativeRect(for: padded),
                    options: CaptureOptions(showsCursor: false, standardSize: false, excludedWindows: ownFloatingWindows())
                )
                image = frame.image
            }
            Log.capture.info("Reading text from a \(image.width, privacy: .public)×\(image.height, privacy: .public) area")
            let content = try await readText(in: image.upscaledForReading() ?? image)
            if settings.playsSounds {
                CaptureSound.play()
            }
            showTextResult(content)
        } catch {
            Log.capture.error("Text capture failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
    }

    /// Reads `image`, and says so if that takes longer than a moment, as a first read can.
    private func readText(in image: CGImage) async throws -> RecognizedContent {
        let notice = Task { [toast] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            toast.show(.init(
                kind: .textCopied,
                symbolName: "text.viewfinder",
                title: String(localized: "Reading text…"),
                detail: String(localized: "The first read after an update can take a minute."),
                staysUntilReplaced: true
            ))
        }
        defer { notice.cancel() }
        do {
            return try await TextRecognizer.recognize(image)
        } catch {
            toast.hide(animated: true)
            throw error
        }
    }

    /// Starts a capture unless one is running. A selection still on screen gives way to the
    /// new request, so pressing Capture Text during Capture Area switches to it instead of
    /// being ignored. A capture past its selection finishes first.
    private func claimCapture() async -> Bool {
        guard hasPermission() else { return false }
        if isCapturing, overlay.isSelecting {
            overlay.cancel()
            // The cancelled capture unwinds on the next turn of the main actor.
            for _ in 0..<50 where isCapturing {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        guard !isCapturing else {
            NSSound.beep()
            return false
        }
        isCapturing = true
        return true
    }

    private func showTextResult(_ content: RecognizedContent) {
        guard !content.isEmpty else {
            let shown = toast.show(.init(kind: .error, symbolName: "text.magnifyingglass", title: String(localized: "No text found"), detail: String(localized: "Try a larger or sharper area.")))
            if !shown { NSSound.beep() }
            return
        }
        let copied = content.copiedText(preservingLineBreaks: settings.keepsOCRLineBreaks)
        clipboard.copy(text: copied)
        textHistory.add(copied)

        let title: String
        if content.lines.isEmpty {
            title = String(localized: "Copied code contents")
        } else if content.lines.count == 1 {
            title = String(localized: "Copied 1 line")
        } else {
            title = String(localized: "Copied \(content.lines.count) lines")
        }
        let app = settings.plainTextApp
        let clipboard = clipboard
        var actions: [CaptureToastController.Action] = [
            .init(title: String(localized: "Open in \(PlainTextOpener.appName(for: app))"), systemImage: "doc.text") {
                PlainTextOpener.open(copied, in: app)
            },
            .init(title: String(localized: "Copy Again"), systemImage: "doc.on.doc") {
                clipboard.copy(text: copied)
            },
        ]
        if settings.textHistoryLimit > 0 {
            actions.append(.init(title: String(localized: "Show in Recents"), systemImage: "clock") {
                MainWindowRouter.shared.request(recentsFilter: .text)
            })
        }
        if let link = content.link {
            actions.insert(.init(title: String(localized: "Open Link"), systemImage: "safari") { NSWorkspace.shared.open(link) }, at: 0)
        }
        toast.show(.init(
            kind: .textCopied,
            symbolName: content.link == nil ? "text.viewfinder" : "qrcode.viewfinder",
            title: title,
            detail: copied,
            actions: actions
        ))
    }

    private func hasPermission() -> Bool {
        guard permissions.screenRecordingStatus == .granted else {
            toast.showScreenRecordingNeeded(then: String(localized: "Try again."))
            return false
        }
        return true
    }

    /// Returns `nil` when the person cancels the selection.
    private func takeImage(_ mode: CaptureMode) async throws -> CapturedFrame? {
        switch mode {
        case .screen:
            guard let screen = NSScreen.underPointer, let displayID = screen.displayID else {
                throw CaptureError.displayNotFound
            }
            return try await capturer.captureDisplay(displayID, rect: nil, options: options())

        case .area:
            guard case .area(let rect, let screen)? = await overlay.select(.area) else { return nil }
            lastArea = (rect, screen)
            guard let displayID = screen.displayID else { throw CaptureError.displayNotFound }
            return try await capturer.captureDisplay(
                displayID,
                rect: screen.topLeftRelativeRect(for: rect),
                options: options()
            )

        case .window:
            let candidates = WindowList.onScreenWindows()
            guard case .window(let window)? = await overlay.select(.window(candidates)) else { return nil }
            let frame = try await capturer.captureWindow(window.id, options: options())
            let style = WindowFrame.Style(
                padding: CGFloat(settings.windowPadding),
                shadow: settings.includesWindowShadow,
                background: settings.windowBackground
            )
            return CapturedFrame(image: WindowFrame.decorate(frame.image, scale: frame.scale, style: style), scale: frame.scale)
        }
    }

    private func options() -> CaptureOptions {
        CaptureOptions(
            showsCursor: settings.includesCursor,
            standardSize: settings.downscalesRetina,
            excludedWindows: ownFloatingWindows()
        )
    }

    /// retrace's panels and overlays (thumbnails, toasts, pins, the HUD) stay out of captures;
    /// its ordinary windows, like the editor and Recents, can be captured.
    private func ownFloatingWindows() -> Set<CGWindowID> {
        Set(NSApplication.shared.windows.lazy
            .filter { $0.isVisible && $0.level != .normal }
            .compactMap { CaptureWindowID.fromAppKitWindowNumber($0.windowNumber) })
    }

    // MARK: After capture

    private func finish(_ capture: CapturedImage, savingTo folder: URL? = nil) async {
        var capture = capture
        capture.preferredSaveFolderURL = folder ?? settings.saveFolderURL
        if settings.savesToFolder {
            capture.fileURL = await save(capture)
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
        } else {
            confirm(capture)
        }
    }

    /// With Quick Access and the editor both off, a toast is the only sign the capture worked.
    private func confirm(_ capture: CapturedImage) {
        let editor = editor
        let edit = CaptureToastController.Action(title: String(localized: "Edit"), systemImage: "pencil.and.outline") {
            editor.open(capture)
        }
        if let url = capture.fileURL {
            let title = settings.copiesToClipboard ? String(localized: "Saved and copied") : String(localized: "Saved")
            let showInFinder = CaptureToastController.Action(title: String(localized: "Show in Finder"), systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            toast.show(.init(kind: .saved, symbolName: "checkmark.circle", title: title, detail: url.lastPathComponent, actions: [showInFinder, edit]))
        } else if settings.copiesToClipboard {
            let save = CaptureToastController.Action(title: String(localized: "Save"), systemImage: "square.and.arrow.down") { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    var saved = capture
                    saved.fileURL = await self.save(capture)
                    if saved.fileURL != nil { self.confirm(saved) }
                }
            }
            toast.show(.init(kind: .imageCopied, symbolName: "doc.on.clipboard", title: String(localized: "Image copied"), actions: [edit, save]))
        }
    }

    /// Saves to the chosen folder, falling back to Pictures/Untitled if that fails.
    func save(_ capture: CapturedImage) async -> URL? {
        let options = settings.exportOptions(for: capture.scale)
        let format = options.format
        let data: Data
        do {
            data = try await ImageEncoder.encodeInBackground(capture.image, options: options, pointScale: capture.scale)
        } catch {
            Log.capture.error("Encoding failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
            return nil
        }

        let preferred = capture.preferredSaveFolderURL ?? settings.saveFolderURL
        do {
            return try await storage.save(data, template: settings.filenameTemplate, date: capture.date, fileExtension: format.fileExtension, in: preferred)
        } catch {
            Log.capture.error("Saving to the chosen folder failed: \(error.localizedDescription, privacy: .public)")
        }

        let fallback = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Untitled", isDirectory: true)
        guard let fallback, fallback.standardizedFileURL != preferred.standardizedFileURL else {
            ErrorPresenter.present(String(localized: "The screenshot couldn't be saved."), recovery: String(localized: "Choose another folder in Settings › Capture. It's still on the clipboard if copying is on."))
            return nil
        }
        do {
            let url = try await storage.save(data, template: settings.filenameTemplate, date: capture.date, fileExtension: format.fileExtension, in: fallback)
            ErrorPresenter.present(String(localized: "Saved to Pictures › Untitled instead."), recovery: String(localized: "The chosen folder couldn't be written to. You can pick another one in Settings › Capture."))
            return url
        } catch {
            ErrorPresenter.present(error)
            return nil
        }
    }
}
