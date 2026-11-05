import Foundation

/// One Library item from saved captures, clipboard history, or Capture Text.
nonisolated enum RecentItem: Identifiable, Hashable, Sendable {
    case file(LibraryItem)
    case text(TextSnippet)
    case clipboard(ClipboardEntry)

    enum ID: Hashable, Sendable {
        case file(URL)
        case text(UUID)
        case clipboard(UUID)

        /// A string form for saving a selection between launches.
        var storageKey: String {
            switch self {
            case .file(let url): "file:" + url.standardizedFileURL.path
            case .text(let id): "text:" + id.uuidString
            case .clipboard(let id): "clip:" + id.uuidString
            }
        }

        init?(storageKey: String) {
            let parts = storageKey.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            switch parts[0] {
            case "file": self = .file(URL(fileURLWithPath: parts[1]))
            case "text": guard let id = UUID(uuidString: parts[1]) else { return nil }; self = .text(id)
            case "clip": guard let id = UUID(uuidString: parts[1]) else { return nil }; self = .clipboard(id)
            default: return nil
            }
        }
    }

    var id: ID {
        switch self {
        case .file(let item): .file(item.url.standardizedFileURL)
        case .text(let snippet): .text(snippet.id)
        case .clipboard(let entry): .clipboard(entry.id)
        }
    }

    var date: Date {
        switch self {
        case .file(let item): item.date
        case .text(let snippet): snippet.date
        case .clipboard(let entry): entry.date
        }
    }

    var file: LibraryItem? {
        if case .file(let item) = self { item } else { nil }
    }

    var snippet: TextSnippet? {
        if case .text(let snippet) = self { snippet } else { nil }
    }

    var clipboardEntry: ClipboardEntry? {
        if case .clipboard(let entry) = self { entry } else { nil }
    }

    /// Captures and both kinds of clipboard history, newest first.
    static func merged(
        files: [LibraryItem],
        snippets: [TextSnippet],
        clipboardEntries: [ClipboardEntry] = []
    ) -> [RecentItem] {
        (files.map(RecentItem.file) + snippets.map(RecentItem.text) + clipboardEntries.map(RecentItem.clipboard))
            .sorted { $0.date > $1.date }
    }
}
