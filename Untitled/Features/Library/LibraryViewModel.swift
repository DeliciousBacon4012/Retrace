import Foundation
import Observation

/// Search, filtering, and selection for the Library tab.
@Observable
final class LibraryViewModel {
    enum KindFilter: String, CaseIterable, Identifiable {
        case all
        case screenshots
        case recordings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: String(localized: "All Captures")
            case .screenshots: String(localized: "Screenshots")
            case .recordings: String(localized: "Recordings")
            }
        }

        var symbolName: String {
            switch self {
            case .all: "square.grid.2x2"
            case .screenshots: "photo"
            case .recordings: "video"
            }
        }
    }

    var searchText = ""
    var kindFilter: KindFilter = .all
    var selection: Set<LibraryItem.ID> = []
    var previewURL: URL?

    func visibleItems(from items: [LibraryItem]) -> [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return items.filter { item in
            switch kindFilter {
            case .all: break
            case .screenshots: if item.kind != .image { return false }
            case .recordings: if item.kind != .video { return false }
            }
            return query.isEmpty || item.name.localizedStandardContains(query)
        }
    }

    func select(_ item: LibraryItem) {
        selection = [item.id]
    }

    func toggle(_ item: LibraryItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    func selectedItems(in items: [LibraryItem]) -> [LibraryItem] {
        items.filter { selection.contains($0.id) }
    }

    /// A context menu acts on the whole selection when the clicked item is part of it,
    /// and on just that item otherwise, like Finder.
    func targets(for item: LibraryItem, in items: [LibraryItem]) -> [LibraryItem] {
        selection.contains(item.id) ? selectedItems(in: items) : [item]
    }

    func togglePreview(in items: [LibraryItem]) {
        if previewURL != nil {
            previewURL = nil
        } else {
            previewURL = selectedItems(in: items).first?.url ?? items.first?.url
        }
    }

    func pruneSelection(keeping items: [LibraryItem]) {
        let ids = Set(items.map(\.id))
        selection.formIntersection(ids)
    }
}
