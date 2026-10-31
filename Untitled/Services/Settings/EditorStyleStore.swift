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
        let stored: [String: MarkStyle]
        do {
            stored = try JSONDecoder().decode([String: MarkStyle].self, from: data)
        } catch {
            log.error("Saved tool styles couldn't be read: \(error.localizedDescription, privacy: .public)")
            return [:]
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
        guard let data = try? JSONEncoder().encode(stored) else { return }
        let now = Date().timeIntervalSince1970
        defaults.set(data, forKey: key)
        defaults.set(now, forKey: dateKey)
        cloud?.set(data, forKey: key)
        cloud?.set(now, forKey: dateKey)
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
