import Foundation

/// A screenshot or recording found in the save folder.
nonisolated struct LibraryItem: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case image
        case video
    }

    let url: URL
    let date: Date
    let kind: Kind
    let byteCount: Int

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}
