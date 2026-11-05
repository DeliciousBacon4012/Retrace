import XCTest
@testable import Untitled

final class CaptureLibraryTests: XCTestCase {
    @MainActor
    func testLibraryCombinesItemsFromConfiguredFolders() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetraceLibraryLocations-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let image = first.appendingPathComponent("capture.png")
        let movie = second.appendingPathComponent("recording.mov")
        let text = second.appendingPathComponent("notes.txt")
        try Data([1]).write(to: image)
        try Data([2]).write(to: movie)
        try Data([3]).write(to: text)

        let library = CaptureLibrary(folders: [first, second, first])
        library.reload()
        for _ in 0..<100 where library.isLoading {
            try await Task.sleep(for: .milliseconds(10))
        }

        let actualPaths = Set(library.items.map { $0.url.resolvingSymlinksInPath().path })
        let expectedPaths = Set([image, movie].map { $0.resolvingSymlinksInPath().path })
        XCTAssertEqual(actualPaths, expectedPaths)
        XCTAssertNil(library.loadError)
    }

    @MainActor
    func testLibraryQuickLookActsOnlyOnSelectedFiles() {
        let file = LibraryItem(
            url: URL(fileURLWithPath: "/tmp/capture.png"),
            date: .distantPast,
            kind: .image,
            byteCount: 1
        )
        let image = RecentItem.file(file)
        let text = RecentItem.text(TextSnippet(id: UUID(), text: "Copied text", date: .now))
        let items = [image, text]
        let viewModel = LibraryViewModel()

        viewModel.select(text)
        viewModel.togglePreview(in: items)
        XCTAssertNil(viewModel.previewURL, "A text-only selection must not preview an unrelated capture.")

        viewModel.selection.removeAll()
        viewModel.togglePreview(in: items)
        XCTAssertNil(viewModel.previewURL, "Quick Look should do nothing when the Library selection is empty.")

        viewModel.select(image)
        viewModel.togglePreview(in: items)
        XCTAssertEqual(viewModel.previewURL, file.url)

        viewModel.togglePreview(in: items)
        XCTAssertNil(viewModel.previewURL, "Space should close an open Quick Look preview.")
    }

    @MainActor
    func testLibrarySelectionToggleRangeAndContextTargets() {
        let items: [RecentItem] = (0..<4).map { index in
            .file(LibraryItem(
                url: URL(fileURLWithPath: "/tmp/capture-\(index).png"),
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                kind: .image,
                byteCount: 1
            ))
        }

        let toggleModel = LibraryViewModel()
        toggleModel.select(items[1])
        toggleModel.toggle(items[3])
        XCTAssertEqual(toggleModel.selection, Set([items[1].id, items[3].id]))
        toggleModel.toggle(items[3])
        XCTAssertEqual(toggleModel.selection, Set([items[1].id]))

        let rangeModel = LibraryViewModel()
        rangeModel.select(items[1])
        rangeModel.extendSelection(to: items[3], in: items)
        XCTAssertEqual(rangeModel.selection, Set([items[1].id, items[2].id, items[3].id]))

        let contextModel = LibraryViewModel()
        contextModel.select(items[0])
        contextModel.toggle(items[2])
        XCTAssertEqual(contextModel.targets(for: items[2], in: items), [items[0], items[2]])
        XCTAssertEqual(contextModel.targets(for: items[3], in: items), [items[3]])
    }

    @MainActor
    func testLibraryArrowNavigationAndShiftRangeSelection() {
        let items: [RecentItem] = (0..<5).map { index in
            .file(LibraryItem(
                url: URL(fileURLWithPath: "/tmp/navigation-\(index).png"),
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                kind: .image,
                byteCount: 1
            ))
        }
        let model = LibraryViewModel()

        XCTAssertEqual(model.moveSelection(by: 1, columns: 3, extendingSelection: false, in: items)?.id, items[0].id)
        XCTAssertEqual(model.moveSelection(by: 1, columns: 3, extendingSelection: false, in: items)?.id, items[1].id)
        XCTAssertEqual(model.moveSelection(by: 3, columns: 3, extendingSelection: true, in: items)?.id, items[4].id)
        XCTAssertEqual(model.selection, Set(items[1...4].map(\.id)))

        XCTAssertEqual(model.moveSelection(by: -3, columns: 3, extendingSelection: true, in: items)?.id, items[1].id)
        XCTAssertEqual(model.selection, Set([items[1].id]))
        XCTAssertNil(model.moveSelection(by: -3, columns: 3, extendingSelection: false, in: items))
        XCTAssertEqual(model.selection, Set([items[1].id]))

        model.clearSelection()
        XCTAssertEqual(model.moveSelection(by: -1, columns: 3, extendingSelection: false, in: items)?.id, items[4].id)
    }

    @MainActor
    func testLibrarySearchAndFiltersPreserveNewestFirstOrder() {
        let screenshot = LibraryItem(
            url: URL(fileURLWithPath: "/tmp/needle-screenshot.png"),
            date: Date(timeIntervalSince1970: 1),
            kind: .image,
            byteCount: 1
        )
        let recording = LibraryItem(
            url: URL(fileURLWithPath: "/tmp/needle-recording.mov"),
            date: Date(timeIntervalSince1970: 3),
            kind: .video,
            byteCount: 1
        )
        let snippet = TextSnippet(id: UUID(), text: "needle in copied text", date: Date(timeIntervalSince1970: 2))
        let model = LibraryViewModel()

        model.updateSources(files: [screenshot, recording], snippets: [snippet])
        XCTAssertEqual(model.visibleItems.map(\.id), [
            RecentItem.file(recording).id,
            RecentItem.text(snippet).id,
            RecentItem.file(screenshot).id,
        ])

        model.kindFilter = .screenshots
        XCTAssertEqual(model.visibleItems.map(\.id), [RecentItem.file(screenshot).id])

        model.kindFilter = .all
        model.searchText = "needle"
        XCTAssertEqual(model.visibleItems.count, 3)

        model.kindFilter = .text
        XCTAssertEqual(model.visibleItems.map(\.id), [RecentItem.text(snippet).id])

        model.searchText = "not present"
        XCTAssertTrue(model.visibleItems.isEmpty)

        model.select(.file(recording))
        model.updateSources(files: [screenshot], snippets: [snippet])
        XCTAssertTrue(model.selection.isEmpty)
    }
}
