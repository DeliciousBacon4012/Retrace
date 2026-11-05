import Foundation
import Observation

/// Search, filtering, and selection for Recents.
@Observable
final class LibraryViewModel {
    enum Category: String, CaseIterable, Hashable, Identifiable {
        case clipboard
        case images
        case areaScreenshots
        case windowScreenshots
        case fullScreen
        case recordings
        case capturedText

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clipboard: String(localized: "Clipboard")
            case .images: String(localized: "Images")
            case .areaScreenshots: String(localized: "Area Screenshots")
            case .windowScreenshots: String(localized: "Window Screenshots")
            case .fullScreen: String(localized: "Full Screen")
            case .recordings: String(localized: "Recordings")
            case .capturedText: String(localized: "Captured Text")
            }
        }

        var symbolName: String {
            switch self {
            case .clipboard: "clipboard"
            case .images: "photo"
            case .areaScreenshots: "rectangle.dashed"
            case .windowScreenshots: "macwindow"
            case .fullScreen: "display"
            case .recordings: "record.circle"
            case .capturedText: "text.viewfinder"
            }
        }
    }

    enum SortOrder: String, CaseIterable, Hashable, Identifiable {
        case newestFirst
        case oldestFirst

        var id: String { rawValue }

        var title: String {
            switch self {
            case .newestFirst: String(localized: "Newest Added")
            case .oldestFirst: String(localized: "Oldest Added")
            }
        }
    }

    /// Preference key: a single click previews with Quick Look.
    static let quickLookOnClickKey = "recentsQuickLookOnClick"

    var searchText = "" {
        didSet {
            if searchText != oldValue { refreshVisibleItems() }
        }
    }
    var selectedCategories = Set(Category.allCases) {
        didSet { if selectedCategories != oldValue { refreshVisibleItems() } }
    }
    var sortOrder: SortOrder = .newestFirst {
        didSet { if sortOrder != oldValue { refreshVisibleItems() } }
    }
    var selection: Set<RecentItem.ID> = []
    var previewURL: URL?
    /// The date-sorted source changes only when captures or captured text change.
    @ObservationIgnored private var sourceItems: [RecentItem] = []
    /// Rebuilt for source, search, or filter changes; selection redraws can reuse this array.
    private(set) var visibleItems: [RecentItem] = []
    /// Where a Shift-click range starts: the item last clicked without Shift.
    @ObservationIgnored private var rangeAnchor: RecentItem.ID?
    /// The active item for arrow-key navigation, which can differ from a range anchor.
    @ObservationIgnored private var navigationCursor: RecentItem.ID?

    /// Refreshes the source list when a watched save folder or clipboard history changes.
    func updateSources(
        files: [LibraryItem],
        snippets: [TextSnippet],
        clipboardEntries: [ClipboardEntry] = []
    ) {
        sourceItems = RecentItem.merged(files: files, snippets: snippets, clipboardEntries: clipboardEntries)
        selection.formIntersection(sourceItems.map(\.id))
        if let rangeAnchor, !sourceItems.contains(where: { $0.id == rangeAnchor }) {
            self.rangeAnchor = nil
        }
        if let navigationCursor, !sourceItems.contains(where: { $0.id == navigationCursor }) {
            self.navigationCursor = nil
        }
        refreshVisibleItems()
    }

    /// Filters and sorts one merged set without rebuilding it on selection-only changes.
    /// Clipboard entries match their visible text or source app; files match their filename.
    private func refreshVisibleItems() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = sourceItems.filter { item in
            switch item {
            case .file(let file):
                let matchesCategory: Bool
                switch file.kind {
                case .image:
                    matchesCategory = selectedCategories.contains(.images)
                        || file.captureSource == .area && selectedCategories.contains(.areaScreenshots)
                        || file.captureSource == .window && selectedCategories.contains(.windowScreenshots)
                        || file.captureSource == .fullScreen && selectedCategories.contains(.fullScreen)
                case .video:
                    matchesCategory = selectedCategories.contains(.recordings)
                }
                guard matchesCategory else { return false }
                return query.isEmpty || file.name.localizedStandardContains(query)
            case .text(let snippet):
                guard selectedCategories.contains(.capturedText) else { return false }
                return query.isEmpty || snippet.text.localizedStandardContains(query)
            case .clipboard(let entry):
                guard selectedCategories.contains(.clipboard) else { return false }
                let text = entry.text ?? entry.appName ?? entry.id.uuidString
                return query.isEmpty || text.localizedStandardContains(query)
            }
        }
        visibleItems = filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .newestFirst: lhs.date > rhs.date
            case .oldestFirst: lhs.date < rhs.date
            }
        }
    }

    func select(_ item: RecentItem) {
        selection = [item.id]
        rangeAnchor = item.id
        navigationCursor = item.id
    }

    func toggle(_ item: RecentItem) {
        rangeAnchor = item.id
        navigationCursor = item.id
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    /// Selects everything from the last item clicked through `item`, like Finder.
    func extendSelection(to item: RecentItem, in items: [RecentItem]) {
        guard let start = items.firstIndex(where: { $0.id == rangeAnchor }),
              let end = items.firstIndex(where: { $0.id == item.id })
        else {
            select(item)
            return
        }
        selection = Set(items[min(start, end)...max(start, end)].map(\.id))
        navigationCursor = item.id
    }

    func selectAll(_ items: [RecentItem]) {
        selection = Set(items.map(\.id))
        rangeAnchor = items.first?.id
        navigationCursor = items.first?.id
    }

    func clearSelection() {
        selection.removeAll()
        rangeAnchor = nil
        navigationCursor = nil
    }

    /// Moves through the visible grid in row-major order; Shift extends from a stable anchor.
    /// A partial final row clamps vertical movement to its last item.
    @discardableResult
    func moveSelection(
        by offset: Int,
        columns: Int,
        extendingSelection: Bool,
        in items: [RecentItem]
    ) -> RecentItem? {
        guard !items.isEmpty, offset != 0 else { return nil }

        let currentIndex = navigationCursor.flatMap { cursor in
            items.firstIndex(where: { $0.id == cursor })
        }
        let targetIndex: Int

        if let currentIndex {
            let requestedIndex = currentIndex + offset
            if offset > 0, offset == columns {
                targetIndex = min(requestedIndex, items.count - 1)
            } else {
                guard items.indices.contains(requestedIndex) else { return nil }
                targetIndex = requestedIndex
            }
            guard targetIndex != currentIndex else { return nil }
        } else {
            targetIndex = offset > 0 ? 0 : items.count - 1
        }

        let target = items[targetIndex]
        guard extendingSelection else {
            select(target)
            return target
        }

        let anchorID = rangeAnchor ?? navigationCursor ?? target.id
        guard let anchorIndex = items.firstIndex(where: { $0.id == anchorID }) else {
            select(target)
            return target
        }
        selection = Set(items[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)].map(\.id))
        rangeAnchor = anchorID
        navigationCursor = target.id
        return target
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
    func togglePreview(
        in items: [RecentItem],
        imageURLForClipboardEntry: (ClipboardEntry) -> URL? = { _ in nil }
    ) {
        if previewURL != nil {
            previewURL = nil
            return
        }

        let selected = selectedItems(in: items)
        previewURL = selected.compactMap(\.file).first?.url
            ?? selected.compactMap(\.clipboardEntry).first.flatMap(imageURLForClipboardEntry)
    }

}
