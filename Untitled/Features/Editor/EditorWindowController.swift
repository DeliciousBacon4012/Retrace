import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Opens annotation editor windows, one per image, and keeps them alive until closed.
@Observable
final class EditorPresenter {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let clipboard: any ClipboardWriting
    @ObservationIgnored private let textHistory: TextHistory?
    @ObservationIgnored private var controllers: [EditorWindowController] = []
    @ObservationIgnored private var keyWindowObserver: (any NSObjectProtocol)?

    /// The editor whose window is key, for the menu bar's editor commands. `nil` while any
    /// other window, or one of the editor's own sheets, has focus.
    private(set) var active: EditorWindowController?

    init(settings: SettingsStore, clipboard: any ClipboardWriting, textHistory: TextHistory? = nil) {
        self.settings = settings
        self.clipboard = clipboard
        self.textHistory = textHistory
        keyWindowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated { self?.followKeyWindow(window) }
        }
    }

    private func followKeyWindow(_ window: NSWindow?) {
        let editor = controllers.first { $0.window === window }
        if active !== editor { active = editor }
    }

    func open(_ capture: CapturedImage) {
        present(EditorDocument(image: capture.image, scale: capture.scale, fileURL: capture.fileURL))
    }

    /// Opens a saved image. Shows an alert if the file isn't a readable image.
    func open(fileAt url: URL) {
        if let existing = controllers.first(where: { $0.editorDocument.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            ErrorPresenter.present(String(localized: "This file can't be opened in the editor."), recovery: String(localized: "Only images can be annotated."))
            return
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? Double ?? 144
        present(EditorDocument(image: image, scale: max(dpi / 72, 1), fileURL: url))
    }

    private func present(_ document: EditorDocument) {
        let controller = EditorWindowController(document: document, settings: settings, clipboard: clipboard, textHistory: textHistory) { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
            if self?.active === closed { self?.active = nil }
        }
        controllers.append(controller)
        controller.showWindow(nil)
        followKeyWindow(NSApp.keyWindow)
        NSApp.activate()
    }
}

/// One editor window.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let editorDocument: EditorDocument
    private let settings: SettingsStore
    private let clipboard: any ClipboardWriting
    private let textHistory: TextHistory?
    private let onClose: (EditorWindowController) -> Void

    init(document: EditorDocument, settings: SettingsStore, clipboard: any ClipboardWriting, textHistory: TextHistory?, onClose: @escaping (EditorWindowController) -> Void) {
        self.editorDocument = document
        self.settings = settings
        self.clipboard = clipboard
        self.textHistory = textHistory
        self.onClose = onClose

        let screen = NSScreen.underPointer ?? NSScreen.main ?? NSScreen.screens.first
        let size = Self.initialSize(for: document, on: screen)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("")
        super.init(window: window)
        window.delegate = self
        updateTitle()

        let actions = EditorActions(
            copy: { [weak self] in self?.copyImage() },
            save: { [weak self] in self?.save() },
            done: { [weak self] in self?.finish() },
            render: { [weak self] in self?.renderOrWarn() },
            copyText: { [weak self] text in
                self?.clipboard.copy(text: text)
                self?.textHistory?.add(text)
            },
            exportFolder: settings.saveFolderURL,
            exportOptions: settings.exportOptions(for: document.scale),
            suggestedName: document.fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Screenshot")
        )
        let hosting = NSHostingController(rootView: EditorView(document: document, actions: actions))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.contentViewController = hosting
        // The hosting controller may have resized the window to its content; put it back,
        // centered on the screen the person is working on rather than the main one.
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        window.setFrame(window.frameRect(forContentRect: NSRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )), display: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Just big enough to show the image at 100 %. When that won't fit in 90 % of the screen,
    /// the largest window that does, shaped to the image so no space is wasted around it.
    static func initialSize(for document: EditorDocument, on screen: NSScreen?) -> NSSize {
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let image = NSSize(width: document.imageSize.width / document.scale, height: document.imageSize.height / document.scale)
        let showsInspector = UserDefaults.standard.object(forKey: "editorShowsInspector") as? Bool ?? true
        // The canvas keeps 36 pt around the image; the toolbar sits above it and the zoom bar
        // floats at the bottom; the inspector, when shown, keeps its own column clear.
        let chrome = NSSize(
            width: 72 + (showsInspector ? EditorInspector.width + Design.spacingL * 2 : 0),
            height: 72 + 52 + 40
        )
        let limit = NSSize(width: visible.width * 0.9, height: visible.height * 0.9)
        let shrink = min(
            1,
            (limit.width - chrome.width) / max(image.width, 1),
            (limit.height - chrome.height) / max(image.height, 1)
        )
        let minimum = EditorView.minimumSize
        return NSSize(
            width: min(max((image.width * max(shrink, 0) + chrome.width).rounded(), minimum.width), limit.width),
            height: min(max((image.height * max(shrink, 0) + chrome.height).rounded(), minimum.height), limit.height)
        )
    }

    private func updateTitle() {
        window?.title = String(localized: "Editing")
        window?.subtitle = editorDocument.fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "New Screenshot")
        window?.representedURL = editorDocument.fileURL
    }

    // MARK: Actions

    func copyImage() {
        guard let image = renderOrWarn() else { return }
        let size = NSSize(width: CGFloat(image.width) / editorDocument.scale, height: CGFloat(image.height) / editorDocument.scale)
        clipboard.copy(NSImage(cgImage: image, size: size))
    }

    /// Saves over the original file, or asks where to save if there isn't one.
    @discardableResult
    func save() -> Bool {
        guard let url = editorDocument.fileURL ?? askForSaveLocation() else { return false }
        return write(to: url)
    }

    func finish() {
        guard editorDocument.hasUnsavedChanges || editorDocument.fileURL == nil else {
            copyImage()
            close()
            return
        }
        copyImage()
        if save() {
            close()
        }
    }

    private func write(to url: URL) -> Bool {
        guard let image = renderOrWarn() else { return false }
        let type = UTType(filenameExtension: url.pathExtension)
        var options = settings.exportOptions(for: editorDocument.scale)
        options.format = ImageFormat.allCases.first { type?.conforms(to: $0.utType) == true } ?? .png
        options.scalePercent = 100
        let redacts = editorDocument.hasRedactions
        if redacts { options.stripsMetadata = true }
        do {
            let data = try ImageEncoder.data(for: image, options: options, pointScale: editorDocument.scale)
            try data.write(to: url, options: .atomic)
            editorDocument.markSaved(to: url)
            // The original capture may still be on the clipboard. Swap in the covered version.
            if redacts, clipboard.holdsOurImage {
                let size = NSSize(width: CGFloat(image.width) / editorDocument.scale, height: CGFloat(image.height) / editorDocument.scale)
                clipboard.copy(NSImage(cgImage: image, size: size))
            }
            updateTitle()
            Log.capture.info("Saved edited image")
            return true
        } catch {
            Log.capture.error("Saving the edited image failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
            return false
        }
    }

    private func askForSaveLocation() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [settings.imageFormat.utType]
        panel.directoryURL = settings.saveFolderURL
        panel.nameFieldStringValue = String(localized: "Screenshot") + "." + settings.imageFormat.fileExtension
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func renderOrWarn() -> CGImage? {
        editorDocument.finishTextEditing()
        guard let image = AnnotationRenderer.export(editorDocument) else {
            ErrorPresenter.present(String(localized: "The edited image couldn't be created."), recovery: String(localized: "Try again, or undo the last change."))
            return nil
        }
        return image
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard editorDocument.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save changes to this screenshot?")
        alert.informativeText = String(localized: "Your marks will be lost if you don't save them.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Don't Save")).hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        editorDocument.undoManager
    }

    func windowWillClose(_ notification: Notification) {
        editorDocument.saveStylesNow()
        onClose(self)
    }
}
