import Foundation

/// What a screenshot captures.
nonisolated enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    /// An area the person drags out.
    case area
    /// One window the person clicks.
    case window
    /// The whole display under the pointer.
    case screen

    var id: String { rawValue }
}
