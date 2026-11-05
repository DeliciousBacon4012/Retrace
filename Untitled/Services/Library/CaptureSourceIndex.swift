import Foundation
import OSLog

/// Stores capture-mode metadata locally so screenshots can be filtered without changing their
/// filenames or writing extra files beside captures. Files without metadata stay filterable as
/// images, including existing captures and images added outside retrace.
nonisolated final class CaptureSourceIndex: @unchecked Sendable {
    static let shared = CaptureSourceIndex()

    private let lock = NSLock()
    private let fileURL: URL?
    private var sources: [String: CaptureSource]

    init(fileURL: URL? = CaptureSourceIndex.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: CaptureSource].self, from: data) {
            sources = decoded
        } else {
            sources = [:]
        }
    }

    func source(for url: URL) -> CaptureSource? {
        lock.lock()
        defer { lock.unlock() }
        return sources[Self.key(for: url)]
    }

    func snapshot() -> [String: CaptureSource] {
        lock.lock()
        defer { lock.unlock() }
        return sources
    }

    func record(_ source: CaptureSource, for url: URL) {
        guard let fileURL else { return }
        lock.lock()
        defer { lock.unlock() }

        sources[Self.key(for: url)] = source
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(sources)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("Couldn't update capture source index: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func key(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let domain = Bundle.main.bundleIdentifier ?? "Untitled"
        return support.appending(path: domain, directoryHint: .isDirectory)
            .appending(path: "Library/CaptureSources.json")
    }
}
