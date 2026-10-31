import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Opens annotation editor windows, one per image, and keeps them alive until closed.
final class EditorPresenter {
    private let settings: SettingsStore
    private let clipboard: any ClipboardWriting
    private var controllers: [EditorWindowController] = []

    init(settings: SettingsStore, clipboard: any ClipboardWriting) {
        self.settings = settings
        self.clipboard = clipboard
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
        let controller = EditorWindowController(document: document, settings: settings, clipboard: clipboard) { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        controller.showWindow(nil)
        NSApp.activate()
    }
}

/// One editor window.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let editorDocument: EditorDocument
    private let settings: SettingsStore
    private let clipboard: any ClipboardWriting
    private let onClose: (EditorWindowController) -> Void

    init(document: EditorDocument, settings: SettingsStore, clipboard: any ClipboardWriting, onClose: @escaping (EditorWindowController) -> Void) {
        self.editorDocument = document
        self.settings = settings
        self.clipboard = clipboard
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialSize(for: document)),
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
            copyText: { [weak self] text in self?.clipboard.copy(text: text) },
            exportFolder: settings.saveFolderURL,
            exportOptions: settings.exportOptions(for: document.scale),
            suggestedName: document.fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Screenshot")
        )
        let hosting = NSHostingController(rootView: EditorView(document: document, actions: actions))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.contentViewController = hosting
        window.setContentSize(Self.initialSize(for: document))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Big enough to show the image at its on-screen size, but never larger than most of the screen.
    private static func initialSize(for document: EditorDocument) -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let pointSize = NSSize(width: document.imageSize.width / document.scale, height: document.imageSize.height / document.scale)
        // Room for the canvas padding, the toolbar, and the inspector beside the image.
        let chrome = NSSize(width: 72 + 280, height: 120)
        return NSSize(
            width: min(max(pointSize.width + chrome.width, 1080), visible.width * 0.92),
            height: min(max(pointSize.height + chrome.height, 480), visible.height * 0.85)
        )
    }

    private func updateTitle() {
        window?.title = String(localized: "Editing")
        window?.subtitle = editorDocument.fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "New Screenshot")
        window?.representedURL = editorDocument.fileURL
    }

    // MARK: Actions

    private func copyImage() {
        guard let image = renderOrWarn() else { return }
        let size = NSSize(width: CGFloat(image.width) / editorDocument.scale, height: CGFloat(image.height) / editorDocument.scale)
        clipboard.copy(NSImage(cgImage: image, size: size))
    }

    /// Saves over the original file, or asks where to save if there isn't one.
    @discardableResult
    private func save() -> Bool {
        guard let url = editorDocument.fileURL ?? askForSaveLocation() else { return false }
        return write(to: url)
    }

    private func finish() {
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
        do {
            let data = try ImageEncoder.data(for: image, options: options, pointScale: editorDocument.scale)
            try data.write(to: url, options: .atomic)
            editorDocument.markSaved(to: url)
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
        onClose(self)
    }
}
