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
    /// The text card that was just copied, which says so for a moment.
    @State private var copiedSnippet: TextSnippet.ID?
    @FocusState private var isGridFocused: Bool
    /// The item under the pointer, kept out of view state so moving it doesn't redraw the grid.
    @State private var gridInteraction = GridInteractionState()
    @State private var interactionMonitor: Any?

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 320), spacing: 20)]

    var body: some View {
        let library = dependencies.library
        let history = dependencies.textHistory
        let items = viewModel.visibleItems

        ScrollViewReader { scrollProxy in
            GeometryReader { geometry in
                let columnCount = max(1, Int((geometry.size.width - 56 + 20) / 180))

                ZStack {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(items) { item in
                                cell(for: item)
                                    .id(item.id)
                                    .onHover { gridInteraction.pointerItem = $0 ? item : (gridInteraction.pointerItem?.id == item.id ? nil : gridInteraction.pointerItem) }
                                    .onTapGesture { click(item, in: items) }
                                    .onDrag { itemProvider(for: item) }
                                    .contextMenu { contextMenu(for: item, in: items) }
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                    }
                    .searchable(text: $viewModel.searchText, prompt: "Search captures")
                    .contentShape(.rect)
                    .onTapGesture {
                        viewModel.clearSelection()
                        isGridFocused = true
                    }
                    .quickLookPreview($viewModel.previewURL, in: items.compactMap(\.file).map(\.url))
                    .overlay { emptyState(library: library, history: history, isEmpty: items.isEmpty) }
                    .onChange(of: library.items) {
                        viewModel.updateSources(files: library.items, snippets: history.snippets)
                        if !library.isLoading, library.loadError == nil {
                            dependencies.versions.prune(keeping: library.items.map(\.url))
                        }
                    }
                    .onChange(of: history.snippets) {
                        viewModel.updateSources(files: library.items, snippets: history.snippets)
                    }
                    .onAppear {
                        viewModel.updateSources(files: library.items, snippets: history.snippets)
                        applyPendingFilter()
                        gridInteraction.columnCount = columnCount
                        isGridFocused = true
                        gridInteraction.isFocused = true
                        installEventMonitor(scrollProxy: scrollProxy)
                    }
                    .onDisappear(perform: removeEventMonitor)
                    .onChange(of: MainWindowRouter.shared.pendingRecentsFilter) { applyPendingFilter() }
                    .task(id: copiedSnippet) {
                        guard copiedSnippet != nil else { return }
                        try? await Task.sleep(for: .seconds(1.2))
                        guard !Task.isCancelled else { return }
                        copiedSnippet = nil
                    }
                }
                .focusable()
                .focused($isGridFocused)
                .focusEffectDisabled()
                .onKeyPress(.space) {
                    viewModel.togglePreview(in: items)
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
                    gridInteraction.columnCount = max(1, Int((width - 56 + 20) / 180))
                }
                .onChange(of: isGridFocused) { _, isFocused in
                    gridInteraction.isFocused = isFocused
                }
            }
        }
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
            TextCard(snippet: snippet, isSelected: viewModel.selection.contains(item.id), isCopied: copiedSnippet == snippet.id)
        }
    }

    @ViewBuilder
    private func emptyState(library: CaptureLibrary, history: TextHistory, isEmpty: Bool) -> some View {
        // The folder only matters when files are shown; text lives elsewhere.
        let showsFiles = viewModel.kindFilter != .text
        if isEmpty, showsFiles, library.isLoading {
            ProgressView()
        } else if isEmpty, showsFiles, let error = library.loadError {
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
        } else if isEmpty, viewModel.kindFilter == .text {
            ContentUnavailableView {
                Label("No Text Yet", systemImage: "text.viewfinder")
            } description: {
                if dependencies.settings.textHistoryLimit > 0 {
                    Text("Text you copy with Capture Text appears here.")
                } else {
                    Text("Text history is off. Turn it on in Settings › Advanced.")
                }
            }
        } else if isEmpty {
            ContentUnavailableView {
                Label("No Captures Yet", systemImage: "camera.viewfinder")
            } description: {
                Text("Use the buttons above or a shortcut. Screenshots, recordings and text you capture appear here.")
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
        }
    }

    /// Files go to the Trash, where they can be put back; text is removed from history.
    private func delete(_ items: [RecentItem]) {
        dependencies.textHistory.remove(Set(items.compactMap(\.snippet).map(\.id)))
        let files = items.compactMap(\.file)
        if !files.isEmpty {
            Task { await dependencies.library.moveToTrash(files) }
        }
    }

    /// A right-click selects the item under it, so it's clear what the menu acts on. An item
    /// that's already selected keeps the selection, and the menu acts on all of it.
    private func installEventMonitor(scrollProxy: ScrollViewProxy) {
        guard interactionMonitor == nil else { return }
        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown, .keyDown]) { [viewModel, gridInteraction] event in
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
        copiedSnippet = snippet.id
    }

    private func itemProvider(for item: RecentItem) -> NSItemProvider {
        switch item {
        case .file(let file): NSItemProvider(object: file.url as NSURL)
        case .text(let snippet): NSItemProvider(object: snippet.text as NSString)
        }
    }

    private func applyPendingFilter() {
        guard let filter = MainWindowRouter.shared.pendingRecentsFilter else { return }
        viewModel.kindFilter = filter
        MainWindowRouter.shared.pendingRecentsFilter = nil
    }
}

private final class GridInteractionState {
    var pointerItem: RecentItem?
    var columnCount = 1
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
                            .glassEffect(.regular, in: .capsule)
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
                            .glassEffect(.regular, in: .capsule)
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
                        .buttonStyle(.glass)
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
            .buttonStyle(.glass)
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
