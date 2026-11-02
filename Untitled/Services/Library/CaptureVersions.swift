import Foundation
import Observation
import OSLog

/// Keeps the untouched original of every capture saved over in the editor, so Recents can
/// show both versions and put the original back.
///
/// The edited image stays where it was, with the same name, so links and Finder still find
/// it. The original is copied once, the first time the file is saved over, into Application
/// Support. Nothing here is deleted on its own: originals go only when you restore or remove
/// them, or when the edited file is gone (then they move to the Trash).
@Observable
final class CaptureVersions {
    nonisolated struct Entry: Codable, Equatable, Sendable {
        /// The original's file name inside the originals folder.
        var file: String
        var savedAt: Date
    }

    /// Originals by the edited file's path.
    private(set) var entries: [String: Entry] = [:]

    @ObservationIgnored private let folder: URL?
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "versions")

    init(folder: URL? = CaptureVersions.defaultFolder) {
        self.folder = folder
        load()
    }

    static var defaultFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Untitled/Originals", directoryHint: .isDirectory)
    }

    private var indexURL: URL? { folder?.appending(path: "index.json") }

    // MARK: Reading

    func hasOriginal(for url: URL) -> Bool {
        entries[Self.key(url)] != nil
    }

    /// Where the original is kept, if this file was edited.
    func original(for url: URL) -> URL? {
        guard let folder, let entry = entries[Self.key(url)] else { return nil }
        return folder.appending(path: entry.file)
    }

    func editedDate(for url: URL) -> Date? {
        entries[Self.key(url)]?.savedAt
    }

    // MARK: Changing

    /// Copies the file aside before the editor first saves over it. Later saves keep that copy.
    func preserveOriginal(of url: URL) {
        let key = Self.key(url)
        guard let folder, entries[key] == nil, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        let name = UUID().uuidString + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: folder.appending(path: name))
            entries[key] = Entry(file: name, savedAt: .now)
            save()
        } catch {
            log.error("Keeping the original failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Puts the original back in place of the edited file. The edited version goes to the Trash.
    func restoreOriginal(of url: URL) throws {
        guard let original = original(for: url) else { return }
        var trashed: NSURL?
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        }
        try FileManager.default.moveItem(at: original, to: url)
        entries[Self.key(url)] = nil
        save()
    }

    /// Moves the kept original to the Trash and forgets it.
    func removeOriginal(of url: URL) {
        guard let original = original(for: url) else { return }
        try? FileManager.default.trashItem(at: original, resultingItemURL: nil)
        entries[Self.key(url)] = nil
        save()
    }

    /// Follows the library: when an edited file is gone, its original goes to the Trash too.
    func prune(keeping existing: [URL]) {
        guard !entries.isEmpty else { return }
        let alive = Set(existing.map(Self.key))
        let gone = entries.keys.filter { !alive.contains($0) && !FileManager.default.fileExists(atPath: $0) }
        guard !gone.isEmpty else { return }
        for key in gone {
            if let folder, let entry = entries[key] {
                try? FileManager.default.trashItem(at: folder.appending(path: entry.file), resultingItemURL: nil)
            }
            entries[key] = nil
        }
        save()
    }

    // MARK: Storage

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    private func load() {
        guard let indexURL, let data = try? Data(contentsOf: indexURL) else { return }
        entries = (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func save() {
        guard let indexURL, let folder else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
        } catch {
            log.error("Saving the originals list failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
