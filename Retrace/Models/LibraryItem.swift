import Foundation

/// A screenshot or recording found in the save folder.
nonisolated struct LibraryItem: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case image
        case video
    }

    let url: URL
    let date: Date
    /// When the file last changed, such as after an edit, so its thumbnail can follow.
    var modified: Date = .distantPast
    let kind: Kind
    let byteCount: Int
    var captureSource: CaptureSource? = nil

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}
