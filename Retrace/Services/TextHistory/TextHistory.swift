import Foundation
import Observation
import OSLog

/// Every snippet Capture Text copied, newest first, kept between launches for as long as
/// Settings › Clipboard says.
///
/// It's stored as JSON in Retrace's Application Support folder, never in the save folder:
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
        followRetention()
    }

    /// Application Support/<bundle ID>/Text History.json, so a development build keeps its own.
    static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = Bundle.main.bundleIdentifier ?? "Retrace"
        return support.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("Text History.json")
    }

    /// Keeps `text` as the newest snippet. The same text captured again moves to the top
    /// instead of appearing twice.
    func add(_ text: String) {
        guard settings.keepsTextHistory,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        snippets.removeAll { $0.text == text }
        snippets.insert(TextSnippet(id: UUID(), text: text, date: .now), at: 0)
        applyRetention()
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

    // MARK: Retention

    /// A shorter limit applies right away, as it does for clipboard history. Turning history
    /// off pauses it and keeps what's there.
    private func followRetention() {
        withObservationTracking {
            _ = settings.textHistoryRetention
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.applyRetention() { self.save() }
                self.followRetention()
            }
        }
    }

    /// Removes what the limit no longer keeps. Returns whether anything went.
    @discardableResult
    private func applyRetention() -> Bool {
        let retention = settings.textHistoryRetention
        let before = snippets.count
        if let age = retention.maximumAge {
            let cutoff = Date.now.addingTimeInterval(-age)
            snippets.removeAll { $0.date < cutoff }
        }
        if let count = retention.maximumCount, snippets.count > count {
            snippets.removeLast(snippets.count - count)
        }
        return snippets.count != before
    }

    // MARK: Storage

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        do {
            let decoded = try JSONDecoder().decode([TextSnippet].self, from: Data(contentsOf: fileURL))
            snippets = decoded.sorted { $0.date > $1.date }
            if applyRetention() { save() }
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
