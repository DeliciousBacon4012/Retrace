import Foundation
import Observation
import OSLog

/// What Retrace has learned about each image in the Library: what's in it, the text it shows,
/// and how it looks. It's built slowly in the background, kept on this Mac, and only reads
/// files; turning it off deletes the index.
@Observable
final class LibraryContentIndex {
    nonisolated struct Entry: Codable, Sendable {
        var modified: Date
        var labels: [ImageLabel]
        var text: String
        var featurePrint: Data?
    }

    /// Images read so far, for Settings.
    private(set) var indexedCount = 0
    private(set) var isIndexing = false
    /// Changes whenever search results could change.
    private(set) var version = 0

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var sweep: Task<Void, Never>?
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var latestItems: [LibraryItem] = []
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "contentIndex")
    @ObservationIgnored private let saveQueue = DispatchQueue(label: "Retrace.ContentIndex.save", qos: .background)

    /// Gives other apps room: Vision work on one image, then a pause.
    private static let pause: Duration = .milliseconds(150)

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: Bundle.main.bundleIdentifier ?? "Retrace", directoryHint: .isDirectory)
            .appending(path: "Library/ContentIndex.json")
    }

    init(fileURL: URL? = LibraryContentIndex.defaultFileURL) {
        self.fileURL = fileURL
        guard let fileURL else { return }
        // Off the main thread, so a large index can't slow launch.
        Task { [weak self] in
            let decoded = await Task.detached(priority: .utility) { () -> [String: Entry]? in
                guard let data = try? Data(contentsOf: fileURL) else { return nil }
                return try? JSONDecoder().decode([String: Entry].self, from: data)
            }.value
            guard let self else { return }
            // What's been learned since launch is newer than what's on disk. A first launch has
            // no file yet, and still counts as loaded.
            self.entries.merge(decoded ?? [:]) { current, _ in current }
            self.indexedCount = self.entries.count
            self.isLoaded = true
            self.update(with: self.latestItems)
        }
    }

    func entry(for url: URL) -> Entry? {
        entries[Self.key(url)]
    }

    /// Paths of images whose text or recognized content contains `query`. Works on a copy off
    /// the main thread, so typing stays smooth however large the Library is.
    func search(_ query: String) async -> Set<String> {
        let entries = entries
        return await Task.detached(priority: .userInitiated) {
            var found = Set<String>()
            for (path, entry) in entries {
                if Task.isCancelled { return [] }
                if entry.text.localizedStandardContains(query)
                    || entry.labels.contains(where: { $0.title.localizedStandardContains(query) }) {
                    found.insert(path)
                }
            }
            return found
        }.value
    }

    /// The images most like `url`, closest first, leaving out `url` itself.
    func similar(to url: URL, among items: [URL], limit: Int = 24) async -> [URL] {
        guard let print = entry(for: url)?.featurePrint else { return [] }
        let entries = entries
        return await Task.detached(priority: .userInitiated) {
            items
                .filter { $0.standardizedFileURL != url.standardizedFileURL }
                .compactMap { item -> (URL, Float)? in
                    guard let other = entries[Self.key(item)]?.featurePrint,
                          let distance = ImageIntelligence.distance(between: print, and: other)
                    else { return nil }
                    return (item, distance)
                }
                .sorted { $0.1 < $1.1 }
                .prefix(limit)
                .map(\.0)
        }.value
    }

    /// Reads any image that's new or changed, one at a time, and forgets files that are gone.
    func update(with items: [LibraryItem]) {
        sweep?.cancel()
        latestItems = items
        // Waits for the saved index, or it would read everything again.
        guard isLoaded || fileURL == nil else { return }
        let images = items.filter { $0.kind == .image }
        let keep = Set(images.map { Self.key($0.url) })
        let before = entries.count
        entries = entries.filter { keep.contains($0.key) }
        var changed = entries.count != before
        indexedCount = entries.count

        let pending = images.filter { item in
            guard let entry = entries[Self.key(item.url)] else { return true }
            return entry.modified < item.modified
        }
        guard !pending.isEmpty else {
            if changed { save() }
            return
        }
        isIndexing = true
        sweep = Task(priority: .background) { [weak self] in
            for item in pending {
                // This work can always wait, so it stops while the Mac is short on power or hot.
                while Self.shouldWait {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                }
                guard !Task.isCancelled else { return }
                let entry = await ImageIntelligence.indexEntry(for: item)
                guard !Task.isCancelled, let self else { return }
                self.entries[Self.key(item.url)] = entry
                self.indexedCount = self.entries.count
                self.version += 1
                changed = true
                try? await Task.sleep(for: Self.pause)
            }
            guard let self else { return }
            self.isIndexing = false
            if changed { self.save() }
        }
    }

    /// Stops and deletes everything learned so far.
    func removeAll() {
        sweep?.cancel()
        sweep = nil
        isIndexing = false
        entries = [:]
        indexedCount = 0
        version += 1
        if let fileURL {
            saveQueue.async { try? FileManager.default.removeItem(at: fileURL) }
        }
    }

    func stop() {
        sweep?.cancel()
        sweep = nil
        isIndexing = false
    }

    nonisolated private static var shouldWait: Bool {
        let process = ProcessInfo.processInfo
        return process.isLowPowerModeEnabled
            || process.thermalState == .serious
            || process.thermalState == .critical
    }

    private func save() {
        guard let fileURL else { return }
        let entries = entries
        let log = log
        saveQueue.async {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
            } catch {
                log.error("Couldn't save the content index: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
