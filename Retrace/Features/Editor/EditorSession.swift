import AppKit
import OSLog
import UniformTypeIdentifiers

/// Where images open.
nonisolated enum EditorOpenPlacement: String, CaseIterable, Identifiable, Sendable {
    case tab
    case window

    static let storageKey = "editorOpenPlacement"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tab: String(localized: "Editor Tab")
        case .window: String(localized: "New Window")
        }
    }

    static var current: EditorOpenPlacement {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .tab
    }
}

/// One open image and what can be done with it, wherever it's shown: the Editor tab or a window
/// of its own. It can move between the two and keep its marks and undo history.
final class EditorSession {
    let document: EditorDocument
    /// Called when the session has finished and whoever shows it should let go.
    var onClose: (() -> Void)?
    /// Called after a save, since the file's name may have changed.
    var onSaved: (() -> Void)?
    /// Called when the person cancels, so the session can be kept for reopening.
    var onDiscard: (() -> Void)?

    /// Where new images save, remembered between sessions. Several can be chosen.
    static let saveFoldersKey = "editorSaveFolders"

    private let settings: SettingsStore
    private let clipboard: any ClipboardWriting
    private let textHistory: TextHistory?
    private let versions: CaptureVersions?

    init(document: EditorDocument, settings: SettingsStore, clipboard: any ClipboardWriting, textHistory: TextHistory?, versions: CaptureVersions?) {
        self.document = document
        self.settings = settings
        self.clipboard = clipboard
        self.textHistory = textHistory
        self.versions = versions
    }

    private(set) lazy var actions = EditorActions(
        discard: { [weak self] in self?.discard() },
        close: { [weak self] in self?.onClose?() },
        saveAs: { [weak self] in self?.saveAs() },
        saveCopy: { [weak self] path in self?.saveCopy(to: path) },
        copy: { [weak self] in self?.copyImage() },
        copyImage: { [weak self] image in
            guard let self else { return }
            let size = NSSize(
                width: CGFloat(image.width) / self.document.scale,
                height: CGFloat(image.height) / self.document.scale
            )
            self.clipboard.copy(NSImage(cgImage: image, size: size))
        },
        save: { [weak self] in self?.save() },
        done: { [weak self] in self?.finish() },
        render: { [weak self] in self?.renderOrWarn() },
        copyText: { [weak self] text in
            self?.clipboard.copy(text: text)
            self?.textHistory?.add(text)
        },
        formatText: { [settings] content in
            content.copiedText(preservingLineBreaks: settings.keepsOCRLineBreaks)
        },
        exportFolder: document.preferredSaveFolderURL ?? settings.saveFolderURL,
        exportOptions: settings.exportOptions(for: document.scale),
        suggestedName: document.fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Screenshot")
    )

    func copyImage() {
        guard !document.isSaving, let image = renderOrWarn() else { return }
        let size = NSSize(width: CGFloat(image.width) / document.scale, height: CGFloat(image.height) / document.scale)
        clipboard.copy(NSImage(cgImage: image, size: size))
    }

    /// The save folders currently chosen, from those in Settings › Capture.
    var chosenSaveFolders: [String] {
        let stored = UserDefaults.standard.stringArray(forKey: Self.saveFoldersKey) ?? []
        let chosen = settings.saveFolderPaths.filter(stored.contains)
        return chosen.isEmpty ? [settings.saveFolderPath] : chosen
    }

    var availableSaveFolders: [String] { settings.saveFolderPaths }

    func folderName(_ path: String) -> String { settings.saveFolderDisplayName(for: path) }

    /// Adds or removes a folder. One always stays chosen.
    func setSaveFolder(_ path: String, chosen: Bool) {
        var folders = chosenSaveFolders
        if chosen {
            if !folders.contains(path) { folders.append(path) }
        } else if folders.count > 1 {
            folders.removeAll { $0 == path }
        }
        UserDefaults.standard.set(folders, forKey: Self.saveFoldersKey)
    }

    /// Closes without saving. The session is kept, so it can be reopened as it was.
    func discard() {
        document.finishTextEditing()
        onDiscard?()
    }

    /// Saves over the original file, or into the chosen folders if there isn't one. No dialog.
    func save() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await saveDocument()
        }
    }

    func finish() {
        Task { @MainActor [weak self] in
            guard let self, !document.isSaving else { return }
            guard document.hasUnsavedChanges || document.fileURL == nil else {
                copyImage()
                onClose?()
                return
            }
            copyImage()
            if await saveDocument() { onClose?() }
        }
    }

    /// Whether the session can close right now, asking about unsaved changes first. Choosing Save
    /// answers false and closes by itself once the file is written.
    func confirmClose() -> Bool {
        guard !document.isSaving else { return false }
        guard document.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save changes to this screenshot?")
        alert.informativeText = String(localized: "Your marks will be lost if you don't save them.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Don't Save")).hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor [weak self] in
                guard let self, await saveDocument() else { return }
                onClose?()
            }
            return false
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func saveDocument() async -> Bool {
        guard !document.isSaving else { return false }
        if let url = document.fileURL { return await write(to: url) }
        return await saveToChosenFolders()
    }

    /// Asks where to save, for a one-off location.
    func saveAs() {
        Task { @MainActor [weak self] in
            guard let self, let url = askForSaveLocation() else { return }
            _ = await write(to: url)
        }
    }

    /// Saves a copy in one folder, leaving the image's own file as it is.
    func saveCopy(to path: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await writeNew(into: [path], becomesDocumentFile: false)
        }
    }

    private func saveToChosenFolders() async -> Bool {
        await writeNew(into: chosenSaveFolders, becomesDocumentFile: true)
    }

    /// Encodes once and writes a new file in each folder. The first becomes the image's file,
    /// so the next save goes back to it.
    private func writeNew(into folders: [String], becomesDocumentFile: Bool) async -> Bool {
        guard !folders.isEmpty, !document.isSaving, let image = renderOrWarn(), document.beginSaving() else { return false }
        defer { document.finishSaving() }
        var options = settings.exportOptions(for: document.scale)
        options.scalePercent = 100
        if document.hasRedactions { options.stripsMetadata = true }
        do {
            let data = try await ImageEncoder.encodeInBackground(image, options: options, pointScale: document.scale)
            let storage = FileCaptureStorage()
            var first: URL?
            for path in folders {
                let url = try await storage.save(
                    data,
                    template: settings.filenameTemplate,
                    date: .now,
                    fileExtension: options.format.fileExtension,
                    in: URL(fileURLWithPath: path, isDirectory: true)
                )
                if first == nil { first = url }
            }
            if becomesDocumentFile, let first { document.markSaved(to: first) }
            onSaved?()
            Log.capture.info("Saved edited image to \(folders.count, privacy: .public) folders")
            return true
        } catch {
            Log.capture.error("Saving the edited image failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
            return false
        }
    }

    private func write(to url: URL) async -> Bool {
        guard !document.isSaving, let image = renderOrWarn(), document.beginSaving() else { return false }
        defer { document.finishSaving() }
        let type = UTType(filenameExtension: url.pathExtension)
        var options = settings.exportOptions(for: document.scale)
        options.format = ImageFormat.allCases.first { type?.conforms(to: $0.utType) == true } ?? .png
        options.scalePercent = 100
        let redacts = document.hasRedactions
        if redacts { options.stripsMetadata = true }
        do {
            let data = try await ImageEncoder.encodeInBackground(image, options: options, pointScale: document.scale)
            // Saving over the capture it came from keeps the untouched original for Library.
            if url.standardizedFileURL == document.fileURL?.standardizedFileURL {
                try await versions?.preserveOriginal(of: url)
            }
            try await ImageEncoder.writeInBackground(data, to: url)
            document.markSaved(to: url)
            // The original capture may still be on the clipboard. Swap in the covered version.
            if redacts, clipboard.holdsOurImage {
                let size = NSSize(width: CGFloat(image.width) / document.scale, height: CGFloat(image.height) / document.scale)
                clipboard.copy(NSImage(cgImage: image, size: size))
            }
            onSaved?()
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
        panel.directoryURL = document.preferredSaveFolderURL ?? settings.saveFolderURL
        panel.nameFieldStringValue = String(localized: "Screenshot") + "." + settings.imageFormat.fileExtension
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func renderOrWarn() -> CGImage? {
        guard !document.isSaving else { return nil }
        document.finishTextEditing()
        do {
            return try AnnotationRenderer.export(document)
        } catch {
            let localized = error as? LocalizedError
            let message = localized?.errorDescription ?? String(localized: "The edited image couldn't be created.")
            let recovery = localized?.recoverySuggestion ?? String(localized: "Try again, or undo the last change.")
            Log.capture.error("Edited image rendering failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(message, recovery: recovery)
            return nil
        }
    }
}
