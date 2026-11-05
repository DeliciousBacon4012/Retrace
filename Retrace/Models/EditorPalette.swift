import Foundation

/// The swatches the editor offers. Both palettes have the same twelve slots in the same
/// order, so number keys and muscle memory carry over when switching.
nonisolated enum EditorPalette: String, CaseIterable, Identifiable, Sendable {
    case pastel
    case vivid
    case custom

    /// The preference that stores the choice.
    static let storageKey = "editorPalette"
    static let customColorsStorageKey = "editorCustomPaletteColors"
    static let customColorCount = 12

    static var defaultCustomColors: [RGBAColor] { pastel.colors }
    static let defaultCustomColorsData: Data = {
        (try? JSONEncoder().encode(defaultCustomColors)) ?? Data()
    }()

    var id: Self { self }

    var title: String {
        switch self {
        case .pastel: String(localized: "Pastel")
        case .vivid: String(localized: "Vivid")
        case .custom: String(localized: "Custom")
        }
    }

    var colors: [RGBAColor] {
        switch self {
        case .pastel:
            [.coral, .apricot, .butter, .pistachio, .mint, .aqua,
             .sky, .periwinkle, .lilac, .blush, .white, .ink]
        case .vivid:
            [.vividRed, .vividOrange, .vividYellow, .vividGreen, .vividMint, .vividCyan,
             .vividBlue, .vividIndigo, .vividPurple, .vividPink, .white, .black]
        case .custom:
            Self.defaultCustomColors
        }
    }

    func colors(custom: [RGBAColor]) -> [RGBAColor] {
        self == .custom ? Self.validatedCustomColors(custom) : colors
    }

    /// Names for help tags and VoiceOver, in the same order as `colors`.
    var names: [String] {
        switch self {
        case .pastel:
            [String(localized: "Coral"), String(localized: "Apricot"), String(localized: "Butter"),
             String(localized: "Pistachio"), String(localized: "Mint"), String(localized: "Aqua"),
             String(localized: "Sky"), String(localized: "Periwinkle"), String(localized: "Lilac"),
             String(localized: "Blush"), String(localized: "White"), String(localized: "Ink")]
        case .vivid:
            [String(localized: "Red"), String(localized: "Orange"), String(localized: "Yellow"),
             String(localized: "Green"), String(localized: "Mint"), String(localized: "Cyan"),
             String(localized: "Blue"), String(localized: "Indigo"), String(localized: "Purple"),
             String(localized: "Pink"), String(localized: "White"), String(localized: "Black")]
        case .custom:
            (1...Self.customColorCount).map { String(localized: "Color \($0)") }
        }
    }

    /// The color for a number key: 1–9 pick the first nine swatches, 0 the tenth.
    func color(forDigit digit: Int) -> RGBAColor? {
        guard (0...9).contains(digit) else { return nil }
        let index = digit == 0 ? 9 : digit - 1
        return colors[index]
    }

    func color(forDigit digit: Int, customColors: [RGBAColor]) -> RGBAColor? {
        guard (0...9).contains(digit) else { return nil }
        let index = digit == 0 ? 9 : digit - 1
        return colors(custom: customColors)[index]
    }

    static func customColors(from data: Data?) -> [RGBAColor] {
        guard let data,
              let colors = try? JSONDecoder().decode([RGBAColor].self, from: data) else {
            return defaultCustomColors
        }
        return validatedCustomColors(colors)
    }

    private static func validatedCustomColors(_ colors: [RGBAColor]) -> [RGBAColor] {
        guard colors.count == customColorCount,
              colors.allSatisfy({ color in
                  [color.red, color.green, color.blue, color.opacity].allSatisfy { $0.isFinite && (0...1).contains($0) }
              }) else {
            return defaultCustomColors
        }
        return colors
    }

    /// The key that picks the swatch at `index`, if it has one.
    static func digit(forSwatchAt index: Int) -> Int? {
        switch index {
        case 0..<9: index + 1
        case 9: 0
        default: nil
        }
    }

    /// The pastel that replaces one of the colors offered before the pastel palette existed.
    /// Custom colors are left alone.
    static func pastelReplacement(forLegacy color: RGBAColor) -> RGBAColor? {
        let legacy = Self.vivid.colors
        guard let index = legacy.firstIndex(where: { $0.sameHue(as: color) }) else { return nil }
        let replacement = Self.pastel.colors[index]
        return replacement.sameHue(as: color) ? nil : replacement.withOpacity(of: color)
    }
}
