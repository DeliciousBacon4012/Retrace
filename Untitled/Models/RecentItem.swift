import Foundation

/// One thing in Recents: a screenshot or recording in the save folder, or captured text.
nonisolated enum RecentItem: Identifiable, Hashable, Sendable {
    case file(LibraryItem)
    case text(TextSnippet)

    enum ID: Hashable, Sendable {
        case file(URL)
        case text(UUID)
    }

    var id: ID {
        switch self {
        case .file(let item): .file(item.url)
        case .text(let snippet): .text(snippet.id)
        }
    }

    var date: Date {
        switch self {
        case .file(let item): item.date
        case .text(let snippet): snippet.date
        }
    }

    var file: LibraryItem? {
        if case .file(let item) = self { item } else { nil }
    }

    var snippet: TextSnippet? {
        if case .text(let snippet) = self { snippet } else { nil }
    }

    /// Files and snippets together, newest first.
    static func merged(files: [LibraryItem], snippets: [TextSnippet]) -> [RecentItem] {
        (files.map(RecentItem.file) + snippets.map(RecentItem.text)).sorted { $0.date > $1.date }
    }
}
