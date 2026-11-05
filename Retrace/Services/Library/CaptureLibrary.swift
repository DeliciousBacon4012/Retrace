import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers

/// The captures in the configured save folders, kept up to date as files are added, renamed, or removed.
///
/// The folder itself is the source of truth, so captures moved or deleted in Finder
/// disappear here too, and nothing is lost if the app quits.
@Observable
final class CaptureLibrary {
    private(set) var items: [LibraryItem] = []
    private(set) var isLoading = false
    /// Set when the folder can't be read, such as when it was deleted or is on an unplugged disk.
    private(set) var loadError: String?
    private(set) var folders: [URL]

    @ObservationIgnored private let sourceIndex: CaptureSourceIndex

    @ObservationIgnored private var watchers: [String: FolderWatcher] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(folder: URL, sourceIndex: CaptureSourceIndex = .shared) {
        self.sourceIndex = sourceIndex
        folders = [folder]
    }

    init(folders: [URL], sourceIndex: CaptureSourceIndex = .shared) {
        self.sourceIndex = sourceIndex
        self.folders = Self.normalized(folders)
    }

    #if DEBUG
    func setPreviewItems(_ items: [LibraryItem]) {
        loadTask?.cancel()
        self.items = items
        loadError = nil
        isLoading = false
    }
    #endif

    func start() {
        watch()
        reload()
    }

    /// Points the library at the configured folders without losing their combined ordering.
    func setFolders(_ urls: [URL]) {
        let updated = Self.normalized(urls)
        guard updated.map(\.path) != folders.map(\.path) else { return }
        folders = updated
        items = []
        watch()
        reload()
    }

    func reload() {
        loadTask?.cancel()
        let folders = folders
        let sources = sourceIndex.snapshot()
        isLoading = items.isEmpty
        loadTask = Task {
            let result = await Self.scan(folders, sources: sources)
            guard !Task.isCancelled else { return }
            if watch() {
                reload()
                return
            }
            items = result.items
            loadError = result.items.isEmpty ? result.errors.first : nil
            if !result.items.isEmpty, !result.errors.isEmpty {
                Log.app.error("Couldn't read \(result.errors.count, privacy: .public) Library location(s)")
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

    @discardableResult
    private func watch() -> Bool {
        var addedWatcher = false
        let paths = Set(folders.map(\.path))
        watchers = watchers.filter { paths.contains($0.key) }
        for folder in folders where watchers[folder.path]?.isWatching != true {
            watchers[folder.path] = FolderWatcher(url: folder) { [weak self] in
                self?.reload()
            }
            addedWatcher = watchers[folder.path]?.isWatching == true || addedWatcher
        }
        return addedWatcher
    }

    private static func normalized(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            return seen.insert(standardized.path).inserted ? standardized : nil
        }
    }

    /// Reads all configured folders off the main thread. A missing folder doesn't stop
    /// other locations from appearing; the first unreadable location is shown if none work.
    @concurrent
    nonisolated private static func scan(
        _ folders: [URL],
        sources: [String: CaptureSource]
    ) async -> (items: [LibraryItem], errors: [String]) {
        let keys: [URLResourceKey] = [.contentTypeKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var found: [LibraryItem] = []
        var errors: [String] = []
        for folder in folders {
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
                    return LibraryItem(
                        url: url,
                        date: date,
                        modified: values.contentModificationDate ?? date,
                        kind: kind,
                        byteCount: values.fileSize ?? 0,
                        captureSource: sources[CaptureSourceIndex.key(for: url)]
                    )
                }
                found.append(contentsOf: items)
            } catch {
                errors.append("\(folder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (found.sorted { $0.date > $1.date }, errors)
    }
}

/// Calls back on the main queue when a folder's contents change.
nonisolated final class FolderWatcher: @unchecked Sendable {
    private let source: (any DispatchSourceFileSystemObject)?
    private var pending: DispatchWorkItem?

    var isWatching: Bool { source != nil }

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
