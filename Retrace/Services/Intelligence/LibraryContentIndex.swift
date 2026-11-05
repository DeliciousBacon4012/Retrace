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
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "contentIndex")

    /// Gives other apps room: Vision work on one image, then a pause.
    private static let pause: Duration = .milliseconds(150)

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: Bundle.main.bundleIdentifier ?? "Retrace", directoryHint: .isDirectory)
            .appending(path: "Library/ContentIndex.json")
    }

    init(fileURL: URL? = LibraryContentIndex.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
            indexedCount = decoded.count
        }
    }

    func entry(for url: URL) -> Entry? {
        entries[Self.key(url)]
    }

    /// True when `query` appears in the image's text or among what's recognized in it.
    func matches(_ url: URL, query: String) -> Bool {
        guard let entry = entry(for: url) else { return false }
        return entry.text.localizedStandardContains(query)
            || entry.labels.contains { $0.title.localizedStandardContains(query) }
    }

    /// The images most like `url`, closest first, leaving out `url` itself.
    func similar(to url: URL, among items: [URL], limit: Int = 24) -> [URL] {
        guard let print = entry(for: url)?.featurePrint else { return [] }
        return items
            .filter { $0.standardizedFileURL != url.standardizedFileURL }
            .compactMap { item -> (URL, Float)? in
                guard let other = entry(for: item)?.featurePrint,
                      let distance = ImageIntelligence.distance(between: print, and: other)
                else { return nil }
                return (item, distance)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Reads any image that's new or changed, one at a time, and forgets files that are gone.
    func update(with items: [LibraryItem]) {
        sweep?.cancel()
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
                guard !Task.isCancelled else { return }
                let entry = await Self.read(item)
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
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    func stop() {
        sweep?.cancel()
        sweep = nil
        isIndexing = false
    }

    nonisolated private static func read(_ item: LibraryItem) async -> Entry {
        let empty = Entry(modified: item.modified, labels: [], text: "", featurePrint: nil)
        // Reading a large screenshot blocks, so it stays off the main actor.
        let image = await Task.detached(priority: .background) {
            ImageIntelligence.downsampledImage(at: item.url)
        }.value
        guard let image else { return empty }
        async let labels = try? ImageIntelligence.labels(in: image)
        async let print = try? ImageIntelligence.featurePrint(of: image)
        async let content = try? TextRecognizer.recognize(image)
        let text = await content?.copiedText(preservingLineBreaks: false) ?? ""
        return await Entry(modified: item.modified, labels: labels ?? [], text: text, featurePrint: print ?? nil)
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            log.error("Couldn't save the content index: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
