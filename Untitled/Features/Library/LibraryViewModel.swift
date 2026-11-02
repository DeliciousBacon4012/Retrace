import Foundation
import Observation

/// Search, filtering, and selection for Recents.
@Observable
final class LibraryViewModel {
    enum KindFilter: String, CaseIterable, Identifiable {
        case all
        case screenshots
        case recordings
        case text

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: String(localized: "All")
            case .screenshots: String(localized: "Screenshots")
            case .recordings: String(localized: "Recordings")
            case .text: String(localized: "Text")
            }
        }
    }

    /// Settings key: a single click previews with Quick Look.
    static let quickLookOnClickKey = "recentsQuickLookOnClick"

    var searchText = ""
    var kindFilter: KindFilter = .all
    var selection: Set<RecentItem.ID> = []
    var previewURL: URL?

    /// Files and snippets that match the filter and search, newest first. Snippets match
    /// on their text, files on their name.
    func visibleItems(files: [LibraryItem], snippets: [TextSnippet]) -> [RecentItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let files = files.filter { item in
            switch kindFilter {
            case .all: true
            case .screenshots: item.kind == .image
            case .recordings: item.kind == .video
            case .text: false
            }
        }
        let snippets = kindFilter == .all || kindFilter == .text ? snippets : []
        return RecentItem.merged(
            files: query.isEmpty ? files : files.filter { $0.name.localizedStandardContains(query) },
            snippets: query.isEmpty ? snippets : snippets.filter { $0.text.localizedStandardContains(query) }
        )
    }

    func select(_ item: RecentItem) {
        selection = [item.id]
    }

    func toggle(_ item: RecentItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    func selectedItems(in items: [RecentItem]) -> [RecentItem] {
        items.filter { selection.contains($0.id) }
    }

    /// A context menu acts on the whole selection when the clicked item is part of it,
    /// and on just that item otherwise, like Finder.
    func targets(for item: RecentItem, in items: [RecentItem]) -> [RecentItem] {
        selection.contains(item.id) ? selectedItems(in: items) : [item]
    }

    /// Quick Look shows files only; text is already readable on its card.
    func togglePreview(in items: [RecentItem]) {
        if previewURL != nil {
            previewURL = nil
        } else {
            previewURL = selectedItems(in: items).compactMap(\.file).first?.url ?? items.compactMap(\.file).first?.url
        }
    }

    func pruneSelection(keeping items: [RecentItem]) {
        selection.formIntersection(items.map(\.id))
    }
}
