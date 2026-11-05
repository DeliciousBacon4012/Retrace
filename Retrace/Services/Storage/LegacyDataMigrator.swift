import Foundation
import OSLog

/// Carries everything saved under the app's old name, Untitled, over to Retrace once.
///
/// Files are moved rather than copied, so clipboard history can't linger in a second place,
/// and nothing is overwritten: if a destination already exists, the old data stays where it
/// is and the settings keep pointing at it.
nonisolated struct LegacyDataMigrator {
    static let bundleIdentifier = "io.github.deliciousbacon4012.Retrace"
    static let legacyBundleIdentifier = "io.github.deliciousbacon4012.Untitled"
    static let completedKey = "legacyDataMigrationCompleted"

    private static let legacyFolderName = "Untitled"
    private static let folderName = "Retrace"

    let defaults: UserDefaults
    /// The old app's saved preferences, if any.
    let legacyPreferences: [String: Any]?
    let applicationSupport: URL
    let pictures: URL
    let fileManager: FileManager

    private let log = Logger(subsystem: Log.subsystem, category: "migration")

    /// Runs for the real app only. Development builds and hosted tests have their own bundle
    /// identifiers and must never touch the person's data.
    static func runIfNeeded() {
        guard Bundle.main.bundleIdentifier == bundleIdentifier,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }

        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
        else { return }

        LegacyDataMigrator(
            defaults: .standard,
            legacyPreferences: UserDefaults.standard.persistentDomain(forName: legacyBundleIdentifier),
            applicationSupport: applicationSupport,
            pictures: pictures,
            fileManager: fileManager
        ).run()
    }

    func run() {
        guard !defaults.bool(forKey: Self.completedKey) else { return }

        copyPreferences()
        moveApplicationSupport()
        moveCaptures()
        renameFilenameTemplate()

        defaults.set(true, forKey: Self.completedKey)
    }

    // MARK: Steps

    /// Values already saved under the new name win. Window positions and other state AppKit
    /// keeps for itself are left behind.
    private func copyPreferences() {
        guard let legacyPreferences else { return }
        for (key, value) in legacyPreferences where defaults.object(forKey: key) == nil {
            guard !key.hasPrefix("NS"), !key.hasPrefix("Apple"), !key.hasPrefix("com_apple") else { continue }
            defaults.set(value, forKey: key)
        }
    }

    private func moveApplicationSupport() {
        let destination = applicationSupport.appending(path: Self.bundleIdentifier, directoryHint: .isDirectory)
        move(
            applicationSupport.appending(path: Self.legacyBundleIdentifier, directoryHint: .isDirectory),
            to: destination
        )

        // Originals of edited captures used to live in their own folder.
        let legacyParent = applicationSupport.appending(path: Self.legacyFolderName, directoryHint: .isDirectory)
        let originals = legacyParent.appending(path: "Originals", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: originals.path(percentEncoded: false)) else { return }
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            log.error("Couldn't prepare the data folder: \(error.localizedDescription, privacy: .public)")
            return
        }
        move(originals, to: destination.appending(path: "Originals", directoryHint: .isDirectory))
        try? removeIfEmpty(legacyParent)
    }

    /// Moves Pictures/Untitled to Pictures/Retrace and updates everything that remembers a path
    /// inside it. If Pictures/Retrace already exists, the old folder stays in use.
    private func moveCaptures() {
        let source = pictures.appending(path: Self.legacyFolderName, directoryHint: .isDirectory)
        let destination = pictures.appending(path: Self.folderName, directoryHint: .isDirectory)

        if fileManager.fileExists(atPath: source.path(percentEncoded: false)) {
            guard move(source, to: destination) else { return }
        }

        let oldRoot = source.standardizedFileURL.path(percentEncoded: false).trimmingTrailingSlash
        let newRoot = destination.standardizedFileURL.path(percentEncoded: false).trimmingTrailingSlash

        if let path = defaults.string(forKey: "saveFolderPath") {
            defaults.set(Self.replacingRoot(of: path, from: oldRoot, to: newRoot), forKey: "saveFolderPath")
        }
        if let paths = defaults.stringArray(forKey: "saveFolderPaths") {
            defaults.set(paths.map { Self.replacingRoot(of: $0, from: oldRoot, to: newRoot) }, forKey: "saveFolderPaths")
        }

        let dataFolder = applicationSupport.appending(path: Self.bundleIdentifier, directoryHint: .isDirectory)
        rewriteIndexKeys(at: dataFolder.appending(path: "Library/CaptureSources.json"), from: oldRoot, to: newRoot)
        rewriteIndexKeys(at: dataFolder.appending(path: "Originals/index.json"), from: oldRoot, to: newRoot)
    }

    /// New captures take the new name; a template the person wrote themselves is left alone.
    private func renameFilenameTemplate() {
        guard let template = defaults.string(forKey: "filenameTemplate"),
              template.hasPrefix(Self.legacyFolderName + " ")
        else { return }
        defaults.set(Self.folderName + template.dropFirst(Self.legacyFolderName.count), forKey: "filenameTemplate")
    }

    // MARK: Helpers

    /// Returns true when `source` ended up at `destination`. Never overwrites.
    @discardableResult
    private func move(_ source: URL, to destination: URL) -> Bool {
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { return false }
        // An empty folder holds nothing to overwrite. The Library creates its folder on launch,
        // so one can be waiting here already.
        try? removeIfEmpty(destination)
        guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            log.notice("Left \(source.lastPathComponent, privacy: .public) in place because its new location already has files.")
            return false
        }
        do {
            try fileManager.moveItem(at: source, to: destination)
            return true
        } catch {
            log.error("Couldn't move \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Removes a folder only if nothing but Finder's .DS_Store is inside, so no data is lost.
    private func removeIfEmpty(_ folder: URL) throws {
        let contents = try fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        if contents.allSatisfy({ $0 == ".DS_Store" }) {
            try fileManager.removeItem(at: folder)
        }
    }

    /// The indexes are dictionaries keyed by absolute file path.
    private func rewriteIndexKeys(at url: URL, from oldRoot: String, to newRoot: String) {
        guard let data = try? Data(contentsOf: url),
              let index = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }

        var rewritten: [String: Any] = [:]
        for (key, value) in index {
            rewritten[Self.replacingRoot(of: key, from: oldRoot, to: newRoot)] = value
        }
        do {
            try JSONSerialization.data(withJSONObject: rewritten).write(to: url, options: .atomic)
        } catch {
            log.error("Couldn't update \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func replacingRoot(of path: String, from oldRoot: String, to newRoot: String) -> String {
        if path == oldRoot { return newRoot }
        guard path.hasPrefix(oldRoot + "/") else { return path }
        return newRoot + path.dropFirst(oldRoot.count)
    }
}

private extension String {
    nonisolated var trimmingTrailingSlash: String {
        count > 1 && hasSuffix("/") ? String(dropLast()) : self
    }
}
