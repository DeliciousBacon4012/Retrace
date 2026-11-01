import Foundation
import Observation
import OSLog

/// Every snippet Capture Text copied, newest first, kept between launches up to the
/// number set in Settings › Advanced.
///
/// It's stored as JSON in Untitled's Application Support folder, never in the save folder:
/// copied text can be private, and it isn't a file anyone chose to save.
@Observable
final class TextHistory {
    private(set) var snippets: [TextSnippet] = []

    @ObservationIgnored private let settings: SettingsStore
    /// Where the history is kept. Without one it lasts only while the app runs.
    @ObservationIgnored private let fileURL: URL?

    init(settings: SettingsStore, fileURL: URL?) {
        self.settings = settings
        self.fileURL = fileURL
        load()
        followLimit()
    }

    /// Application Support/<bundle ID>/Text History.json, so a development build keeps its own.
    static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = Bundle.main.bundleIdentifier ?? "Untitled"
        return support.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("Text History.json")
    }

    /// Keeps `text` as the newest snippet. The same text captured again moves to the top
    /// instead of appearing twice.
    func add(_ text: String) {
        guard settings.textHistoryLimit > 0,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        snippets.removeAll { $0.text == text }
        snippets.insert(TextSnippet(id: UUID(), text: text, date: .now), at: 0)
        trimToLimit()
        save()
    }

    func remove(_ ids: Set<TextSnippet.ID>) {
        guard !ids.isEmpty else { return }
        snippets.removeAll { ids.contains($0.id) }
        save()
    }

    func removeAll() {
        snippets = []
        save()
    }

    // MARK: Limit

    /// Lowering the limit, or turning history off, removes the oldest snippets right away.
    private func followLimit() {
        withObservationTracking {
            _ = settings.textHistoryLimit
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if trimToLimit() { save() }
                followLimit()
            }
        }
    }

    /// Returns whether anything was removed.
    @discardableResult
    private func trimToLimit() -> Bool {
        let limit = max(settings.textHistoryLimit, 0)
        guard snippets.count > limit else { return false }
        snippets.removeLast(snippets.count - limit)
        return true
    }

    // MARK: Storage

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        do {
            let decoded = try JSONDecoder().decode([TextSnippet].self, from: Data(contentsOf: fileURL))
            snippets = decoded.sorted { $0.date > $1.date }
            if trimToLimit() { save() }
        } catch {
            Log.app.error("Text history was unreadable and starts empty: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            if snippets.isEmpty {
                // Nothing kept means nothing left on disk either.
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snippets).write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("Saving text history failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
