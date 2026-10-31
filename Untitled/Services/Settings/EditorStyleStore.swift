import Foundation

/// Remembers each editor tool's last style between launches. Sizes are stored in points,
/// so a style looks the same on Retina and non-Retina screenshots.
final class EditorStyleStore {
    private let defaults: UserDefaults
    private let key = "editorToolStyles"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(scale: CGFloat) -> [EditorTool: MarkStyle] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: MarkStyle].self, from: data)
        else { return [:] }
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
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
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
