import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers

/// The captures in the save folder, kept up to date as files are added, renamed, or removed.
///
/// The folder itself is the source of truth, so captures moved or deleted in Finder
/// disappear here too, and nothing is lost if the app quits.
@Observable
final class CaptureLibrary {
    private(set) var items: [LibraryItem] = []
    private(set) var isLoading = false
    /// Set when the folder can't be read, such as when it was deleted or is on an unplugged disk.
    private(set) var loadError: String?
    private(set) var folder: URL

    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(folder: URL) {
        self.folder = folder
    }

    func start() {
        watch()
        reload()
    }

    /// Points the library at another folder, such as after the save location changes.
    func setFolder(_ url: URL) {
        guard url.standardizedFileURL != folder.standardizedFileURL else { return }
        folder = url
        items = []
        watch()
        reload()
    }

    func reload() {
        loadTask?.cancel()
        let folder = folder
        isLoading = items.isEmpty
        loadTask = Task {
            let result = await Self.scan(folder)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let found):
                items = found
                loadError = nil
            case .failure(let error):
                items = []
                loadError = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Moves files to the Trash, so they can still be put back from there.
    func moveToTrash(_ selection: [LibraryItem]) async {
        guard !selection.isEmpty else { return }
        do {
            _ = try await NSWorkspace.shared.recycle(selection.map(\.url))
        } catch {
            Log.app.error("Moving to Trash failed: \(error.localizedDescription, privacy: .public)")
            ErrorPresenter.present(error)
        }
        reload()
    }

    private func watch() {
        watcher = FolderWatcher(url: folder) { [weak self] in
            self?.reload()
        }
    }

    /// Reads the folder off the main thread. Only images and movies are listed.
    @concurrent
    nonisolated private static func scan(_ folder: URL) async -> Result<[LibraryItem], any Error> {
        let keys: [URLResourceKey] = [.contentTypeKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            let items = urls.compactMap { url -> LibraryItem? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let type = values.contentType
                else { return nil }
                let kind: LibraryItem.Kind
                if type.conforms(to: .image) {
                    kind = .image
                } else if type.conforms(to: .movie) {
                    kind = .video
                } else {
                    return nil
                }
                let date = values.creationDate ?? values.contentModificationDate ?? .distantPast
                return LibraryItem(url: url, date: date, kind: kind, byteCount: values.fileSize ?? 0)
            }
            return .success(items.sorted { $0.date > $1.date })
        } catch {
            return .failure(error)
        }
    }
}

/// Calls back on the main queue when a folder's contents change.
nonisolated final class FolderWatcher: @unchecked Sendable {
    private let source: (any DispatchSourceFileSystemObject)?
    private var pending: DispatchWorkItem?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else {
            source = nil
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        self.source = source
        source.setEventHandler { [weak self] in
            // Saving a file fires several events in a row; wait for them to settle.
            self?.pending?.cancel()
            let work = DispatchWorkItem {
                MainActor.assumeIsolated { onChange() }
            }
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }
}
