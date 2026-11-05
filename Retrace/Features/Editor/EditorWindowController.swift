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
    @ObservationIgnored private let versions: CaptureVersions?
    @ObservationIgnored private var controllers: [EditorWindowController] = []
    /// The image open in the main window's Editor tab, if any.
    private(set) var tabSession: EditorSession?
    /// Set by the main window, so the menu bar's commands follow the tab in front.
    @ObservationIgnored var isEditorTabInFront = false {
        didSet { followKeyWindow(NSApp?.keyWindow) }
    }
    /// Files being decoded, so a double-click can't open one twice.
    @ObservationIgnored private var opening: Set<URL> = []
    @ObservationIgnored private var keyWindowObserver: (any NSObjectProtocol)?

    /// The editor whose window is key, for the menu bar's editor commands. `nil` while any
    /// other window, or one of the editor's own sheets, has focus.
    private(set) var active: EditorSession?

    init(settings: SettingsStore, clipboard: any ClipboardWriting, textHistory: TextHistory? = nil, versions: CaptureVersions? = nil) {
        self.settings = settings
        self.clipboard = clipboard
        self.textHistory = textHistory
        self.versions = versions
        keyWindowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated { self?.followKeyWindow(window) }
        }
    }

    /// Lets go of blur and pixelation layers that open editors aren't showing.
    func dropSpareCaches() {
        controllers.forEach { $0.editorDocument.dropSpareRedactionLayers() }
        tabSession?.document.dropSpareRedactionLayers()
    }

    /// Puts every tool back to its original look, here and in editors already open.
    func resetToolStyles() {
        controllers.forEach { $0.editorDocument.forgetToolStyles() }
        tabSession?.document.forgetToolStyles()
        EditorStyleStore().reset()
    }

    private func followKeyWindow(_ window: NSWindow?) {
        var editor = controllers.first { $0.window === window }?.session
        if editor == nil, isEditorTabInFront, window?.identifier?.rawValue.hasPrefix(WindowID.main) == true {
            editor = tabSession
        }
        if active !== editor { active = editor }
    }

    func open(_ capture: CapturedImage) {
        place(EditorDocument(
            image: capture.image,
            scale: capture.scale,
            fileURL: capture.fileURL,
            preferredSaveFolderURL: capture.preferredSaveFolderURL
        ))
    }

    /// Opens a saved image, decoding it in the background so the app keeps moving. Shows an
    /// alert if the file isn't a readable image.
    func open(fileAt url: URL, inNewWindow: Bool = false) {
        let path = url.standardizedFileURL
        if tabSession?.document.fileURL?.standardizedFileURL == path {
            MainWindowRouter.shared.requestTab(.editor)
            return
        }
        if let existing = controllers.first(where: { $0.editorDocument.fileURL?.standardizedFileURL == path }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        guard opening.insert(path).inserted else { return }
        Task {
            let loaded = await Self.loadImage(at: url)
            opening.remove(path)
            guard let (image, scale) = loaded else {
                Self.presentUnreadable()
                return
            }
            place(EditorDocument(image: image, scale: scale, fileURL: url), inNewWindow: inNewWindow)
        }
    }

    /// Opens a copy of an image as a new, unsaved capture, leaving the file itself alone.
    func openCopy(ofImageAt url: URL) {
        Task {
            guard let (image, scale) = await Self.loadImage(at: url) else {
                Self.presentUnreadable()
                return
            }
            place(EditorDocument(image: image, scale: scale, fileURL: nil))
        }
    }

    private static func presentUnreadable() {
        ErrorPresenter.present(String(localized: "This file can't be opened in the editor."), recovery: String(localized: "Only images can be annotated."))
    }

    nonisolated private static func loadImage(at url: URL) async -> (CGImage, CGFloat)? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  // Decodes now, here, rather than during the window's first draw.
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let dpi = properties?[kCGImagePropertyDPIWidth] as? Double ?? 144
            return (image, max(dpi / 72, 1))
        }.value
    }

    /// Puts an image where Settings says, unless the Editor tab has unsaved work. That's never
    /// replaced, so the new image gets a window of its own instead.
    private func place(_ document: EditorDocument, inNewWindow: Bool = false) {
        let wantsTab = !inNewWindow && EditorOpenPlacement.current == .tab
        guard wantsTab, tabSession?.document.hasUnsavedChanges != true else {
            presentWindow(makeSession(document))
            return
        }
        tabSession?.document.saveStylesNow()
        let session = makeSession(document)
        session.onClose = { [weak self] in self?.endTabSession() }
        tabSession = session
        followKeyWindow(NSApp.keyWindow)
        MainWindowRouter.shared.requestTab(.editor)
    }

    private func makeSession(_ document: EditorDocument) -> EditorSession {
        EditorSession(document: document, settings: settings, clipboard: clipboard, textHistory: textHistory, versions: versions)
    }

    private func presentWindow(_ session: EditorSession) {
        let controller = EditorWindowController(session: session) { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
            if self?.active === closed.session { self?.active = nil }
        }
        controllers.append(controller)
        controller.showWindow(nil)
        followKeyWindow(NSApp.keyWindow)
        NSApp.activate()
    }

    /// Closes the Editor tab's image, asking first if it has unsaved changes.
    func closeTabSession() {
        guard let tabSession, tabSession.confirmClose() else { return }
        endTabSession()
    }

    /// Moves the Editor tab's image into a window of its own, with its marks and history.
    func moveTabSessionToWindow() {
        guard let session = tabSession else { return }
        tabSession = nil
        if active === session { active = nil }
        presentWindow(session)
    }

    private func endTabSession() {
        tabSession?.document.saveStylesNow()
        if active === tabSession { active = nil }
        tabSession = nil
    }
}

/// One editor window.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let session: EditorSession
    var editorDocument: EditorDocument { session.document }
    private let onClose: (EditorWindowController) -> Void

    init(session: EditorSession, onClose: @escaping (EditorWindowController) -> Void) {
        self.session = session
        self.onClose = onClose

        let screen = NSScreen.underPointer ?? NSScreen.main ?? NSScreen.screens.first
        let size = Self.initialSize(for: session.document, on: screen)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        // The tools sit in the toolbar's middle, so the title would only crowd them.
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("")
        super.init(window: window)
        window.delegate = self
        session.onClose = { [weak self] in self?.close() }
        session.onSaved = { [weak self] in self?.updateTitle() }
        updateTitle()

        let hosting = NSHostingController(rootView: EditorView(document: session.document, actions: session.actions))
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

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        session.confirmClose()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        editorDocument.undoManager
    }

    func windowWillClose(_ notification: Notification) {
        editorDocument.saveStylesNow()
        onClose(self)
    }
}
