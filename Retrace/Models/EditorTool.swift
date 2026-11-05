import Foundation

/// The editor's tools, in toolbar order. Tools with variants (arrow routes, shape kinds,
/// redaction types) keep the chosen variant in their style.
nonisolated enum EditorTool: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case select
    case arrow
    case shape
    case pen
    case highlighter
    case text
    case counter
    case redact
    case spotlight
    case crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: String(localized: "Select")
        case .arrow: String(localized: "Arrow")
        case .shape: String(localized: "Shape")
        case .pen: String(localized: "Pen")
        case .highlighter: String(localized: "Highlighter")
        case .text: String(localized: "Text")
        case .counter: String(localized: "Step Counter")
        case .redact: String(localized: "Redact")
        case .spotlight: String(localized: "Spotlight")
        case .crop: String(localized: "Crop")
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .shape: "square.on.circle"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .redact: "eye.slash"
        case .spotlight: "flashlight.on.fill"
        case .crop: "crop"
        }
    }

    /// The single key that picks this tool, shown in its tooltip.
    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .shape: "r"
        case .pen: "p"
        case .highlighter: "h"
        case .text: "t"
        case .counter: "n"
        case .redact: "b"
        case .spotlight: "l"
        case .crop: "c"
        }
    }

    var isFreehand: Bool { self == .pen || self == .highlighter }
    /// Tools that draw a new mark, as opposed to selecting or cropping.
    var draws: Bool { self != .select && self != .crop }
    /// Tools whose marks are a box you can resize from its corners and edges.
    var isBoxShaped: Bool { self == .shape || self == .redact || self == .spotlight }
}
