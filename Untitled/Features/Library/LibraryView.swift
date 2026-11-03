import AppKit
import QuickLook
import SwiftUI

/// Every screenshot and recording in the save folder, and the text Capture Text copied,
/// newest first. This is the main window's content; its filter lives in the window toolbar.
struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel

    @Environment(AppDependencies.self) private var dependencies
    /// The text card that was just copied, which says so for a moment.
    @State private var copiedSnippet: TextSnippet.ID?
    @FocusState private var isGridFocused: Bool
    /// The item under the pointer, kept out of view state so moving it doesn't redraw the grid.
    @State private var pointer = PointerItem()
    @State private var rightClickMonitor: Any?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 14)]

    var body: some View {
        let library = dependencies.library
        let history = dependencies.textHistory
        let items = viewModel.visibleItems(files: library.items, snippets: history.snippets)

        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { item in
                    cell(for: item)
                        .onHover { pointer.item = $0 ? item : (pointer.item?.id == item.id ? nil : pointer.item) }
                        .onTapGesture { click(item, in: items) }
                        .onDrag { itemProvider(for: item) }
                        .contextMenu { contextMenu(for: item, in: items) }
                }
            }
            .padding(16)
        }
        .contentShape(.rect)
        .onTapGesture {
            viewModel.selection.removeAll()
            isGridFocused = true
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
        .onExitCommand { viewModel.selection.removeAll() }
        .quickLookPreview($viewModel.previewURL, in: items.compactMap(\.file).map(\.url))
        .overlay { emptyState(library: library, history: history, isEmpty: items.isEmpty) }
        .onChange(of: library.items) { pruneSelection() }
        .onChange(of: history.snippets) { pruneSelection() }
        .onAppear {
            applyPendingFilter()
            isGridFocused = true
            installRightClickMonitor()
        }
        .onDisappear(perform: removeRightClickMonitor)
        .onChange(of: MainWindowRouter.shared.pendingRecentsFilter) { applyPendingFilter() }
        .task(id: copiedSnippet) {
            guard copiedSnippet != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            copiedSnippet = nil
        }
    }

    @ViewBuilder
    private func cell(for item: RecentItem) -> some View {
        switch item {
        case .file(let file):
            LibraryCell(item: file, isSelected: viewModel.selection.contains(item.id))
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
                Label("Can't Open the Save Folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Choose Another Folder…") {
                    let settings = dependencies.settings
                    if let folder = FolderPicker.chooseFolder(startingAt: settings.saveFolderURL) {
                        settings.saveFolderPath = folder.path
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
    private func installRightClickMonitor() {
        guard rightClickMonitor == nil else { return }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [viewModel, pointer] event in
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control),
               let item = pointer.item, !viewModel.selection.contains(item.id) {
                viewModel.select(item)
            }
            return event
        }
    }

    private func removeRightClickMonitor() {
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
        }
        rightClickMonitor = nil
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
            if let snippet = item.snippet { copy(snippet) }
        }
    }

    /// Images open in the editor; recordings play in their default app.
    private func open(_ item: RecentItem) {
        switch item {
        case .file(let file) where file.kind == .image: dependencies.editor.open(fileAt: file.url)
        case .file(let file): NSWorkspace.shared.open(file.url)
        case .text(let snippet): PlainTextOpener.open(snippet.text, in: dependencies.settings.plainTextApp)
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

    private func pruneSelection() {
        viewModel.pruneSelection(keeping: RecentItem.merged(files: dependencies.library.items, snippets: dependencies.textHistory.snippets))
    }

    private func applyPendingFilter() {
        guard let filter = MainWindowRouter.shared.pendingRecentsFilter else { return }
        viewModel.kindFilter = filter
        MainWindowRouter.shared.pendingRecentsFilter = nil
    }
}

private final class PointerItem {
    var item: RecentItem?
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
                .frame(height: 116)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
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
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
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

/// One capture in the grid: its thumbnail, name, and when it was taken.
private struct LibraryCell: View {
    let item: LibraryItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FileThumbnail(url: item.url)
                .padding(6)
                .frame(height: 116)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
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
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(item.byteCount.formatted(.byteCount(style: .file)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
