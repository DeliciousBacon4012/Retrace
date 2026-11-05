import Foundation
import Observation
import OSLog

nonisolated enum CaptureVersionError: LocalizedError, Sendable {
    case storageUnavailable
    case originalMissing
    case preservationInProgress
    case historyUpdateFailedAfterRestore(String)

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            String(localized: "The original screenshot could not be preserved because its storage folder is unavailable.")
        case .originalMissing:
            String(localized: "The original screenshot could not be preserved because the source file is missing.")
        case .preservationInProgress:
            String(localized: "The original screenshot is already being preserved. Try saving again in a moment.")
        case .historyUpdateFailedAfterRestore(let reason):
            String(localized: "The original was restored, but its version history couldn't be updated: \(reason). A recovery copy remains available.")
        }
    }
}

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
    @ObservationIgnored private var preserving: Set<String> = []

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
        original(for: url) != nil
    }

    /// Where the original is kept, if this file was edited.
    func original(for url: URL) -> URL? {
        guard let folder, let entry = entries[Self.key(url)], Self.isSafeOriginalFilename(entry.file) else { return nil }
        let original = folder.appending(path: entry.file)
        return Self.isSafeOriginalFile(original, in: folder) ? original : nil
    }

    func editedDate(for url: URL) -> Date? {
        guard original(for: url) != nil else { return nil }
        return entries[Self.key(url)]?.savedAt
    }

    // MARK: Changing

    /// Copies the file aside before the editor first saves over it. Later saves keep that copy.
    func preserveOriginal(of url: URL) async throws {
        let key = Self.key(url)
        guard entries[key] == nil else { return }
        guard let folder else { throw CaptureVersionError.storageUnavailable }
        guard preserving.insert(key).inserted else { throw CaptureVersionError.preservationInProgress }
        defer { preserving.remove(key) }

        let name = UUID().uuidString + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
        let destination = folder.appending(path: name)
        do {
            try await Self.copyOriginal(at: url, to: destination, in: folder)
            entries[key] = Entry(file: name, savedAt: .now)
            do {
                try saveIndex()
            } catch {
                entries[key] = nil
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        } catch {
            log.error("Keeping the original failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @concurrent
    private static func copyOriginal(at source: URL, to destination: URL, in folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw CaptureVersionError.originalMissing
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    /// Puts the original back in place of the edited file. The edited version goes to the Trash.
    func restoreOriginal(of url: URL) throws {
        let key = Self.key(url)
        guard let entry = entries[key] else { return }
        guard let folder else { throw CaptureVersionError.storageUnavailable }
        let fileManager = FileManager.default
        let original = folder.appending(path: entry.file)
        guard Self.isSafeOriginalFilename(entry.file), Self.isSafeOriginalFile(original, in: folder) else {
            throw CaptureVersionError.originalMissing
        }

        let pathExtension = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
        let staged = url.deletingLastPathComponent()
            .appendingPathComponent(".retrace-restore-\(UUID().uuidString)\(pathExtension)")
        defer { try? fileManager.removeItem(at: staged) }
        try fileManager.copyItem(at: original, to: staged)

        var trashed: NSURL?
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.trashItem(at: url, resultingItemURL: &trashed)
        }
        do {
            try fileManager.moveItem(at: staged, to: url)
        } catch {
            if let trashedURL = trashed as URL? {
                do {
                    try fileManager.moveItem(at: trashedURL, to: url)
                } catch {
                    log.error("Restoring the edited capture from the Trash failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            throw error
        }

        entries[key] = nil
        do {
            try saveIndex()
        } catch {
            entries[key] = entry
            throw CaptureVersionError.historyUpdateFailedAfterRestore(error.localizedDescription)
        }
        do {
            try fileManager.trashItem(at: original, resultingItemURL: nil)
        } catch {
            log.error("Restored a capture but couldn't move its recovery copy to the Trash: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Moves the kept original to the Trash and forgets it.
    func removeOriginal(of url: URL) {
        guard let original = original(for: url) else { return }
        do {
            try FileManager.default.trashItem(at: original, resultingItemURL: nil)
            entries[Self.key(url)] = nil
            save()
        } catch {
            log.error("Moving an original to the Trash failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Follows the library: when an edited file is gone, its original goes to the Trash too.
    func prune(keeping existing: [URL]) {
        guard !entries.isEmpty else { return }
        let alive = Set(existing.map(Self.key))
        let gone = entries.keys.filter { !alive.contains($0) && !FileManager.default.fileExists(atPath: $0) }
        guard !gone.isEmpty else { return }
        for key in gone {
            if let folder, let entry = entries[key] {
                guard Self.isSafeOriginalFilename(entry.file) else {
                    entries[key] = nil
                    continue
                }
                let original = folder.appending(path: entry.file)
                if Self.isSafeOriginalFile(original, in: folder) {
                    do {
                        try FileManager.default.trashItem(at: original, resultingItemURL: nil)
                    } catch {
                        log.error("Moving an unused original to the Trash failed: \(error.localizedDescription, privacy: .public)")
                        continue
                    }
                }
            }
            entries[key] = nil
        }
        save()
    }

    // MARK: Storage

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    private static func isSafeTargetPath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        return URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false) == path
    }

    /// Index entries name files inside the originals folder, never arbitrary paths.
    private static func isSafeOriginalFilename(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\\")
            && URL(fileURLWithPath: name).lastPathComponent == name
    }

    /// Never acts on a symlink or a file outside the originals folder, even if the index is edited.
    private static func isSafeOriginalFile(_ url: URL, in folder: URL) -> Bool {
        guard url.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let type = attributes[.type] as? FileAttributeType
        else { return false }
        return type == .typeRegular
    }

    private func load() {
        guard let indexURL, let folder else { return }
        guard FileManager.default.fileExists(atPath: indexURL.path(percentEncoded: false)) else { return }
        do {
            let data = try Data(contentsOf: indexURL)
            let decoded = try JSONDecoder().decode([String: Entry].self, from: data)
            entries = decoded.filter { path, entry in
                guard Self.isSafeTargetPath(path), Self.isSafeOriginalFilename(entry.file) else { return false }
                return Self.isSafeOriginalFile(folder.appending(path: entry.file), in: folder)
            }
            if entries.count != decoded.count {
                log.error("Ignored \(decoded.count - self.entries.count, privacy: .public) invalid or missing original-version entries")
                save()
            }
        } catch {
            log.error("The originals list couldn't be read: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            try saveIndex()
        } catch {
            log.error("Saving the originals list failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveIndex() throws {
        guard let indexURL, let folder else { throw CaptureVersionError.storageUnavailable }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
    }
}
