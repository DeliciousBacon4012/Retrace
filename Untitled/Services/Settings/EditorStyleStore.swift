import Foundation
import Security
import OSLog

/// Remembers each editor tool's last style between launches. Sizes are stored in points,
/// so a style looks the same on Retina and non-Retina screenshots.
///
/// Styles live in the app's preferences on this Mac, which survive restarts and macOS updates.
/// When the app is signed with iCloud key-value storage, they also sync to the person's other
/// Macs, and the newest copy wins.
final class EditorStyleStore {
    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private let key = "editorToolStyles"
    private let dateKey = "editorToolStylesDate"
    /// 1 once saved colors have moved from the old vivid swatches to the pastel ones.
    private let paletteVersionKey = "editorToolStylesPaletteVersion"
    private let log = Logger(subsystem: Log.subsystem, category: "styles")

    init(defaults: UserDefaults = .standard, usesCloud: Bool = true) {
        self.defaults = defaults
        cloud = usesCloud && Self.hasCloudEntitlement ? NSUbiquitousKeyValueStore.default : nil
        if let cloud {
            cloud.synchronize()
            NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.adoptCloudCopyIfNewer() }
            }
            adoptCloudCopyIfNewer()
        }
    }

    func load(scale: CGFloat) -> [EditorTool: MarkStyle] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        var stored: [String: MarkStyle]
        do {
            stored = try JSONDecoder().decode([String: MarkStyle].self, from: data)
        } catch {
            log.error("Saved tool styles couldn't be read: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
        if defaults.integer(forKey: paletteVersionKey) < 1 {
            stored = movedToPastel(stored)
        }
        var styles: [EditorTool: MarkStyle] = [:]
        for (name, style) in stored {
            if let tool = EditorTool(rawValue: name) {
                styles[tool] = style.scaled(by: scale)
            }
        }
        return styles
    }

    func save(_ styles: [EditorTool: MarkStyle], scale: CGFloat) {
        let stored = Dictionary(uniqueKeysWithValues: styles.map { ($0.key.rawValue, $0.value.scaled(by: 1 / scale)) })
        write(stored)
    }

    /// Anything written by this version already uses the palette the person picked,
    /// so it never needs moving.
    private func write(_ stored: [String: MarkStyle]) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(1, forKey: paletteVersionKey)
        let now = Date().timeIntervalSince1970
        defaults.set(data, forKey: key)
        defaults.set(now, forKey: dateKey)
        cloud?.set(data, forKey: key)
        cloud?.set(now, forKey: dateKey)
    }

    /// Runs once: styles saved with the old vivid swatches move to the matching pastel,
    /// so the new look applies without resetting anything. Custom colors stay as they are.
    /// Picking a vivid color afterwards is the person's choice and is kept.
    private func movedToPastel(_ stored: [String: MarkStyle]) -> [String: MarkStyle] {
        var moved = stored
        for (name, style) in stored {
            if let pastel = EditorPalette.pastelReplacement(forLegacy: style.color) {
                moved[name]?.color = pastel
            }
        }
        if moved != stored {
            write(moved)
            log.info("Moved saved tool colors to the pastel palette")
        } else {
            defaults.set(1, forKey: paletteVersionKey)
        }
        return moved
    }

    func reset() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: dateKey)
        cloud?.removeObject(forKey: key)
        cloud?.removeObject(forKey: dateKey)
    }

    /// Takes the iCloud copy when another Mac saved more recently than this one.
    private func adoptCloudCopyIfNewer() {
        guard let cloud, let data = cloud.data(forKey: key) else { return }
        let cloudDate = cloud.double(forKey: dateKey)
        guard cloudDate > defaults.double(forKey: dateKey) else { return }
        defaults.set(data, forKey: key)
        defaults.set(cloudDate, forKey: dateKey)
        log.info("Using tool styles synced from iCloud")
    }

    /// iCloud key-value storage only works when the app is signed with its entitlement,
    /// which needs a paid developer account. Without it the store would silently do nothing.
    private static let hasCloudEntitlement: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-kvstore-identifier" as CFString, nil)
        return value != nil
    }()
}

nonisolated extension MarkStyle {
    /// The same style with every size multiplied, for moving between pixel densities.
    func scaled(by factor: CGFloat) -> MarkStyle {
        var style = self
        style.lineWidth *= factor
        style.shadowRadius *= factor
        style.cornerRadius *= factor
        style.fontSize *= factor
        return style
    }
}
