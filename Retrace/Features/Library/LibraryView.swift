import AppKit
import QuickLook
import SwiftUI

/// Every screenshot and recording in the save folder, and the text Capture Text copied,
/// newest first. The main window's Library section shows these items.
///
/// Click selects, or previews captures with Quick Look when enabled in Library options.
/// Double-click opens: images in the editor, recordings in their app, text in the text app.
struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel

    @Environment(AppDependencies.self) private var dependencies
    @AppStorage(LibraryViewModel.quickLookOnClickKey) private var quickLookOnClick = false
    /// The Library item just copied, which briefly shows confirmation.
    @State private var copiedItem: RecentItem.ID?
    @FocusState private var isGridFocused: Bool
    /// The item under the pointer, kept out of view state so moving it doesn't redraw the grid.
    @State private var gridInteraction = GridInteractionState()
    @State private var interactionMonitor: Any?

    /// Pinch the grid to change this, as in Photos.
    @AppStorage("libraryThumbnailSize") private var thumbnailSize = 160.0
    @State private var pinchStart: Double?
    /// The rectangle being dragged out on empty space, and what was selected before it began.
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<RecentItem.ID> = []

    private static let thumbnailSizes = 110.0...360.0
    private nonisolated static let gridSpace = "libraryGrid"
    private static let gridSpacing: CGFloat = 20
    private static let gridInset: CGFloat = 28

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize * 1.6), spacing: Self.gridSpacing)]
    }

    private func columnCount(width: CGFloat) -> Int {
        max(1, Int((width - Self.gridInset * 2 + Self.gridSpacing) / (thumbnailSize + Self.gridSpacing)))
    }

    var body: some View {
        let library = dependencies.library
        let history = dependencies.textHistory
        let clipboardHistory = dependencies.clipboardHistory
        let items = viewModel.visibleItems

        ScrollViewReader { scrollProxy in
            GeometryReader { geometry in
                ZStack {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(items) { item in
                                cell(for: item)
                                    .id(item.id)
                                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.gridSpace)) } action: {
                                        gridInteraction.frames[item.id] = $0
                                    }
                                    .onHover { gridInteraction.pointerItem = $0 ? item : (gridInteraction.pointerItem?.id == item.id ? nil : gridInteraction.pointerItem) }
                                    .onTapGesture { click(item, in: items) }
                                    .onDrag { itemProvider(for: item) }
                                    .contextMenu { contextMenu(for: item, in: items) }
                            }
                        }
                        .padding(.horizontal, Self.gridInset)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                        .background {
                            Color.clear
                                .contentShape(.rect)
                                .gesture(marqueeGesture(in: items))
                        }
                        .overlay(alignment: .topLeading) { marqueeOverlay }
                        .coordinateSpace(.named(Self.gridSpace))
                    }
                    .simultaneousGesture(pinchGesture)
                    .contentShape(.rect)
                    .onTapGesture {
                        viewModel.clearSelection()
                        isGridFocused = true
                    }
                    .quickLookPreview($viewModel.previewURL, in: previewURLs(for: items))
                    .overlay { emptyState(library: library, history: history, isEmpty: items.isEmpty) }
                    .onChange(of: library.items) {
                        updateSources()
                        if !library.isLoading, library.loadError == nil {
                            dependencies.versions.prune(keeping: library.items.map(\.url))
                        }
                    }
                    .onChange(of: history.snippets) {
                        updateSources()
                    }
                    .onChange(of: clipboardHistory.entries) {
                        updateSources()
                    }
                    .onAppear {
                        updateSources()
                        applyPendingFilter()
                        gridInteraction.columnCount = columnCount(width: geometry.size.width)
                        isGridFocused = true
                        gridInteraction.isFocused = true
                        installEventMonitor(scrollProxy: scrollProxy)
                    }
                    .onDisappear(perform: removeEventMonitor)
                    .onChange(of: MainWindowRouter.shared.pendingLibraryCategories) { applyPendingFilter() }
                    .task(id: copiedItem) {
                        guard copiedItem != nil else { return }
                        try? await Task.sleep(for: .seconds(1.2))
                        guard !Task.isCancelled else { return }
                        copiedItem = nil
                    }
                }
                .focusable()
                .focused($isGridFocused)
                .focusEffectDisabled()
                .onKeyPress(.space) {
                    viewModel.togglePreview(in: items, imageURLForClipboardEntry: clipboardHistory.imageURL(for:))
                    return .handled
                }
                .onKeyPress(.return) {
                    guard let item = viewModel.selectedItems(in: items).first else { return .ignored }
                    open(item)
                    return .handled
                }
                .onCommand(#selector(NSResponder.selectAll(_:))) { viewModel.selectAll(items) }
                .onDeleteCommand {
                    delete(viewModel.selectedItems(in: items))
                }
                .onExitCommand { viewModel.clearSelection() }
                .onChange(of: geometry.size.width) { _, width in
                    gridInteraction.columnCount = columnCount(width: width)
                }
                .onChange(of: thumbnailSize) {
                    gridInteraction.frames.removeAll()
                    gridInteraction.columnCount = columnCount(width: geometry.size.width)
                }
                .onChange(of: isGridFocused) { _, isFocused in
                    gridInteraction.isFocused = isFocused
                }
            }
        }
    }

    /// Drag on empty space to select, as in Finder. Shift or ⌘ adds to what's selected. Dragging
    /// from a thumbnail still drags it out of the app.
    private func marqueeGesture(in items: [RecentItem]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.gridSpace))
            .onChanged { value in
                if marquee == nil {
                    isGridFocused = true
                    let adds = !NSEvent.modifierFlags.intersection([.shift, .command]).isEmpty
                    marqueeBase = adds ? viewModel.selection : []
                }
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                marquee = rect
                let touched = items.lazy
                    .filter { gridInteraction.frames[$0.id]?.intersects(rect) == true }
                    .map(\.id)
                let selection = marqueeBase.union(touched)
                if selection != viewModel.selection { viewModel.selection = selection }
            }
            .onEnded { _ in
                marquee = nil
                marqueeBase = []
            }
    }

    @ViewBuilder
    private var marqueeOverlay: some View {
        if let marquee {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor.opacity(0.14))
                .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
                .frame(width: marquee.width, height: marquee.height)
                .offset(x: marquee.minX, y: marquee.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Pinch to resize the thumbnails. A tap on the trackpad marks each end of the range.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? thumbnailSize
                pinchStart = start
                let proposed = start * value.magnification
                let size = min(max(proposed, Self.thumbnailSizes.lowerBound), Self.thumbnailSizes.upperBound)
                if size != thumbnailSize {
                    if size == Self.thumbnailSizes.lowerBound || size == Self.thumbnailSizes.upperBound { Haptics.alignment() }
                    thumbnailSize = size
                }
            }
            .onEnded { _ in pinchStart = nil }
    }

    @ViewBuilder
    private func cell(for item: RecentItem) -> some View {
        switch item {
        case .file(let file):
            LibraryCell(
                item: file,
                original: dependencies.versions.original(for: file.url),
                isSelected: viewModel.selection.contains(item.id),
                openInEditor: { dependencies.editor.open(fileAt: $0) },
                showQuickLook: { viewModel.previewURL = $0 }
            )
        case .text(let snippet):
            TextCard(snippet: snippet, isSelected: viewModel.selection.contains(item.id), isCopied: copiedItem == item.id)
        case .clipboard(let entry):
            ClipboardCard(
                entry: entry,
                imageURL: dependencies.clipboardHistory.imageURL(for: entry),
                isSelected: viewModel.selection.contains(item.id),
                isCopied: copiedItem == item.id
            )
        }
    }

    @ViewBuilder
    private func emptyState(library: CaptureLibrary, history: TextHistory, isEmpty: Bool) -> some View {
        let savedCaptureCategories: Set<LibraryViewModel.Category> = [
            .images, .areaScreenshots, .windowScreenshots, .fullScreen, .recordings,
        ]
        let showsSavedCaptures = !viewModel.selectedCategories.isDisjoint(with: savedCaptureCategories)
        if isEmpty, viewModel.selectedCategories.isEmpty {
            ContentUnavailableView {
                Label("No Filters Selected", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Choose a filter to show Library items.")
            } actions: {
                Button("Show All") { viewModel.selectedCategories = Set(LibraryViewModel.Category.allCases) }
            }
        } else if isEmpty, showsSavedCaptures, library.isLoading {
            ProgressView()
        } else if isEmpty, showsSavedCaptures, let error = library.loadError {
            ContentUnavailableView {
                Label("Can't Open a Library Location", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Choose Another Folder…") {
                    let settings = dependencies.settings
                    if let folder = FolderPicker.chooseFolder(startingAt: settings.saveFolderURL) {
                        settings.addSaveFolder(folder)
                        settings.setDefaultSaveFolder(folder.path)
                    }
                }
            }
        } else if isEmpty, !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else if isEmpty, viewModel.selectedCategories == [.capturedText] {
            ContentUnavailableView {
                Label("No Text Yet", systemImage: "text.viewfinder")
            } description: {
                if dependencies.settings.textHistoryLimit > 0 {
                    Text("Text you copy with Capture Text appears here.")
                } else {
                    Text("Text history is off. Turn it on in Settings › Advanced.")
                }
            }
        } else if isEmpty, viewModel.selectedCategories == [.clipboard], !dependencies.settings.keepsClipboardHistory {
            ContentUnavailableView {
                Label("Clipboard History Is Off", systemImage: "clipboard")
            } description: {
                Text("Turn it on in Settings to keep copied text and images here.")
            }
        } else if isEmpty, viewModel.selectedCategories == [.clipboard] {
            ContentUnavailableView {
                Label("Nothing Copied Yet", systemImage: "clipboard")
            } description: {
                Text("Text and images you copy in any app appear here.")
            }
        } else if isEmpty {
            ContentUnavailableView {
                Label("Nothing to Show", systemImage: "square.grid.2x2")
            } description: {
                Text("Try another filter or capture something new.")
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: RecentItem, in items: [RecentItem]) -> some View {
        let targets = viewModel.targets(for: item, in: items)
        switch item {
        case .file(let file):
            let files = targets.compactMap(\.file)
            if file.kind == .image {
                Button("Open in Editor") { files.forEach { dependencies.editor.open(fileAt: $0.url) } }
            }
            Button(file.kind == .image ? "Open in Default App" : "Open") { files.forEach { NSWorkspace.shared.open($0.url) } }
            Button("Quick Look") { viewModel.previewURL = file.url }
            if dependencies.versions.hasOriginal(for: file.url) {
                Button("Restore Original") { restoreOriginal(of: file.url) }
                    .disabled(files.count > 1)
            }
            Divider()
            Button("Copy") {
                if files.count == 1 {
                    dependencies.clipboard.copyFile(at: file.url)
                } else {
                    dependencies.clipboard.copyFiles(at: files.map(\.url))
                }
            }
            if file.kind == .image {
                Button("Pin to Screen") { files.forEach { dependencies.pins.pin(fileAt: $0.url) } }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url)) }
            ShareLink(items: files.map(\.url)) { Text("Share…") }
            Divider()
            Button("Select All") { viewModel.selectAll(items) }
            Divider()
            Button("Move to Trash", role: .destructive) { delete(targets.filter { $0.file != nil }) }
        case .text(let snippet):
            let app = dependencies.settings.plainTextApp
            Button("Open in \(PlainTextOpener.appName(for: app))") { PlainTextOpener.open(snippet.text, in: app) }
                .disabled(targets.count > 1)
            Button("Copy") { copy(snippet) }
                .disabled(targets.count > 1)
            Divider()
            Button("Select All") { viewModel.selectAll(items) }
            Divider()
            Button("Delete", role: .destructive) { delete(targets.filter { $0.snippet != nil }) }
        case .clipboard(let entry):
            let entries = targets.compactMap(\.clipboardEntry)
            if let url = dependencies.clipboardHistory.imageURL(for: entry) {
                Button("Open in Editor") { dependencies.editor.openCopy(ofImageAt: url) }
                Button("Quick Look") { viewModel.previewURL = url }
            } else if let text = entry.text {
                let app = dependencies.settings.plainTextApp
                Button("Open in \(PlainTextOpener.appName(for: app))") {
                    PlainTextOpener.open(text, in: app)
                }
            }
            Button("Copy") { dependencies.clipboardHistory.copy(entry) }
                .disabled(entries.count != 1)
            Divider()
            Button("Delete", role: .destructive) {
                dependencies.clipboardHistory.remove(Set(entries.map(\.id)))
            }
        }
    }

    /// Files go to the Trash, where they can be put back; text is removed from history.
    private func delete(_ items: [RecentItem]) {
        dependencies.textHistory.remove(Set(items.compactMap(\.snippet).map(\.id)))
        dependencies.clipboardHistory.remove(Set(items.compactMap(\.clipboardEntry).map(\.id)))
        let files = items.compactMap(\.file)
        if !files.isEmpty {
            Task { await dependencies.library.moveToTrash(files) }
        }
    }

    /// A right-click selects the item under it, so it's clear what the menu acts on. An item
    /// that's already selected keeps the selection, and the menu acts on all of it.
    private func installEventMonitor(scrollProxy: ScrollViewProxy) {
        guard interactionMonitor == nil else { return }
        let clipboardHistory = dependencies.clipboardHistory
        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown, .keyDown, .pressure]) { [viewModel, gridInteraction] event in
            // A force click shows Quick Look, as it does in Finder.
            if event.type == .pressure {
                defer { gridInteraction.pressureStage = event.stage }
                guard event.stage == 2, gridInteraction.pressureStage < 2, let item = gridInteraction.pointerItem,
                      let url = item.file?.url ?? item.clipboardEntry.flatMap(clipboardHistory.imageURL(for:))
                else { return event }
                viewModel.select(item)
                viewModel.previewURL = url
                return event
            }

            if event.type == .keyDown {
                // ScrollView uses arrow keys to scroll, so handle them only while the Library grid has focus.
                guard gridInteraction.isFocused,
                      NSApp.keyWindow === event.window,
                      !(NSApp.keyWindow?.firstResponder is NSTextView),
                      !(NSApp.keyWindow?.firstResponder is NSTextField),
                      event.modifierFlags.intersection([.command, .option, .control]).isEmpty
                else { return event }

                let offset: Int
                // AppKit virtual key codes for the four arrow keys.
                switch event.keyCode {
                case 123: offset = -1
                case 124: offset = 1
                case 125: offset = gridInteraction.columnCount
                case 126: offset = -gridInteraction.columnCount
                default: return event
                }

                guard let item = viewModel.moveSelection(
                    by: offset,
                    columns: gridInteraction.columnCount,
                    extendingSelection: event.modifierFlags.contains(.shift),
                    in: viewModel.visibleItems
                ) else { return event }
                scrollProxy.scrollTo(item.id, anchor: .center)
                return nil
            }

            if event.type == .rightMouseDown || event.modifierFlags.contains(.control),
               let item = gridInteraction.pointerItem, !viewModel.selection.contains(item.id) {
                viewModel.select(item)
            }
            return event
        }
    }

    private func removeEventMonitor() {
        if let interactionMonitor {
            NSEvent.removeMonitor(interactionMonitor)
        }
        interactionMonitor = nil
    }

    /// One gesture for single and double clicks, so a click never waits to see if another follows.
    private func click(_ item: RecentItem, in items: [RecentItem]) {
        isGridFocused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            viewModel.toggle(item)
        } else if flags.contains(.shift) {
            viewModel.extendSelection(to: item, in: items)
        } else if NSApp.currentEvent?.clickCount == 2 {
            open(item)
        } else {
            viewModel.select(item)
            switch item {
            case .file(let file):
                // An open preview follows the selection, as in Finder.
                if quickLookOnClick || viewModel.previewURL != nil {
                    viewModel.previewURL = file.url
                }
            case .text(let snippet):
                copy(snippet)
            case .clipboard(let entry):
                copy(entry)
                if (quickLookOnClick || viewModel.previewURL != nil),
                   let url = dependencies.clipboardHistory.imageURL(for: entry) {
                    viewModel.previewURL = url
                }
            }
        }
    }

    /// Images open in the editor; recordings play in their default app.
    private func open(_ item: RecentItem) {
        viewModel.previewURL = nil
        switch item {
        case .file(let file) where file.kind == .image: dependencies.editor.open(fileAt: file.url)
        case .file(let file): NSWorkspace.shared.open(file.url)
        case .text(let snippet): PlainTextOpener.open(snippet.text, in: dependencies.settings.plainTextApp)
        case .clipboard(let entry):
            if let url = dependencies.clipboardHistory.imageURL(for: entry) {
                dependencies.editor.openCopy(ofImageAt: url)
            } else if let text = entry.text {
                PlainTextOpener.open(text, in: dependencies.settings.plainTextApp)
            }
        }
    }

    private func restoreOriginal(of url: URL) {
        do {
            try dependencies.versions.restoreOriginal(of: url)
        } catch {
            ErrorPresenter.present(error)
        }
    }

    private func copy(_ snippet: TextSnippet) {
        dependencies.clipboard.copy(text: snippet.text)
        copiedItem = .text(snippet.id)
    }

    private func copy(_ entry: ClipboardEntry) {
        dependencies.clipboardHistory.copy(entry)
        copiedItem = .clipboard(entry.id)
    }

    private func itemProvider(for item: RecentItem) -> NSItemProvider {
        switch item {
        case .file(let file): NSItemProvider(object: file.url as NSURL)
        case .text(let snippet): NSItemProvider(object: snippet.text as NSString)
        case .clipboard(let entry):
            if let url = dependencies.clipboardHistory.imageURL(for: entry) {
                NSItemProvider(contentsOf: url) ?? NSItemProvider()
            } else {
                NSItemProvider(object: (entry.text ?? "") as NSString)
            }
        }
    }

    private func applyPendingFilter() {
        guard let categories = MainWindowRouter.shared.pendingLibraryCategories else { return }
        viewModel.selectedCategories = categories
        MainWindowRouter.shared.pendingLibraryCategories = nil
    }

    private func previewURLs(for items: [RecentItem]) -> [URL] {
        items.compactMap { item in
            item.file?.url ?? item.clipboardEntry.flatMap(dependencies.clipboardHistory.imageURL(for:))
        }
    }

    private func updateSources() {
        viewModel.updateSources(
            files: dependencies.library.items,
            snippets: dependencies.textHistory.snippets,
            clipboardEntries: dependencies.clipboardHistory.entries
        )
    }
}

private final class GridInteractionState {
    var pointerItem: RecentItem?
    /// Where each visible item sits in the grid, for drag selection.
    var frames: [RecentItem.ID: CGRect] = [:]
    var columnCount = 1
    var pressureStage = 0
    var isFocused = false
}

/// Captured text in the grid. Clicking it copies it again; double-clicking opens it.
private struct TextCard: View {
    let snippet: TextSnippet
    let isSelected: Bool
    let isCopied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snippet.text)
                .font(.callout)
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .aspectRatio(CapturePreviewLayout.aspectRatio, contentMode: .fit)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: CapturePreviewLayout.cornerRadius))
                .overlay(alignment: .bottomTrailing) {
                    if isCopied {
                        Label("Copied", systemImage: "checkmark")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: .capsule)
                            .padding(8)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: CapturePreviewLayout.cornerRadius)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                }
                .animation(.response, value: isCopied)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.summary)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(snippet.date.formatted(date: .abbreviated, time: .shortened)) · \(snippet.lineCount == 1 ? String(localized: "1 line") : String(localized: "\(snippet.lineCount) lines"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Copies the text")
    }
}

/// One capture in the grid: its thumbnail, name, and when it was taken. An edited capture
/// shows its original peeking out behind it, and a badge that opens both versions.
private struct LibraryCell: View {
    let item: LibraryItem
    /// The untouched original, when this capture was saved over in the editor.
    let original: URL?
    let isSelected: Bool
    let openInEditor: (URL) -> Void
    let showQuickLook: (URL) -> Void

    @State private var showsVersions = false

    var body: some View {
        let metadata = "\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(item.byteCount.formatted(.byteCount(style: .file)))"

        VStack(alignment: .leading, spacing: 8) {
            FileThumbnail(url: item.url, version: item.modified)
                .aspectRatio(CapturePreviewLayout.aspectRatio, contentMode: .fit)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: CapturePreviewLayout.cornerRadius))
                .clipShape(.rect(cornerRadius: CapturePreviewLayout.cornerRadius))
                .overlay(alignment: .bottomLeading) {
                    if item.kind == .video {
                        Image(systemName: "video.fill")
                            .font(.caption)
                            .padding(6)
                            .background(.regularMaterial, in: .capsule)
                            .padding(8)
                            .accessibilityLabel("Recording")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if original != nil {
                        Button {
                            showsVersions = true
                        } label: {
                            Label("Edited", systemImage: "square.stack")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .background(.regularMaterial, in: .capsule)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .padding(6)
                        .help("Show the edited and original versions")
                        .popover(isPresented: $showsVersions, arrowEdge: .bottom) {
                            if let original {
                                VersionsView(edited: item, original: original, openInEditor: openInEditor)
                            }
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: CapturePreviewLayout.cornerRadius)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                }
            VStack(alignment: .leading, spacing: 2) {
                // Two lines, so a long name shows whole, with every cell the same height.
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.middle)
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(metadata)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(original != nil ? Text("Edited") : Text(""))
        .accessibilityAction(named: Text(item.kind == .image ? "Open in Editor" : "Open")) {
            if item.kind == .image {
                openInEditor(item.url)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
        .accessibilityAction(named: Text("Quick Look")) {
            showQuickLook(item.url)
        }
    }
}

/// The edited capture next to its original. Double-click either one to open it in the editor.
private struct VersionsView: View {
    let edited: LibraryItem
    let original: URL
    let openInEditor: (URL) -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                version("Edited", url: edited.url, version: edited.modified)
                version("Original", url: original, version: dependencies.versions.editedDate(for: edited.url))
            }
            HStack {
                Button("Remove Original", role: .destructive) {
                    dependencies.versions.removeOriginal(of: edited.url)
                    dismiss()
                }
                .help("Moves the original to the Trash and keeps the edited version")
                Spacer()
                Button("Restore Original") {
                    do {
                        try dependencies.versions.restoreOriginal(of: edited.url)
                        dismiss()
                    } catch {
                        ErrorPresenter.present(error)
                    }
                }
                .help("Puts the original back and moves the edited version to the Trash")
            }
        }
        .padding(16)
        .frame(width: 440)
        .quickLookPreview($previewURL, in: [edited.url, original])
    }

    private func version(_ title: LocalizedStringKey, url: URL, version: Date?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FileThumbnail(url: url, version: version)
                .padding(6)
                .frame(height: 130)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .contentShape(.rect)
                .onTapGesture {
                    if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                        dismiss()
                        openInEditor(url)
                    } else {
                        previewURL = url
                    }
                }
                .help("Click to preview, double-click to open in the editor")
            Text(title)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview(screenRecording: .granted)
    LibraryView(viewModel: LibraryViewModel())
        .environment(dependencies)
        .frame(width: 800, height: 560)
}
#endif
