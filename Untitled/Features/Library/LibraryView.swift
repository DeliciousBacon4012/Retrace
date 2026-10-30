import AppKit
import QuickLook
import SwiftUI

/// Every screenshot and recording in the save folder, newest first.
struct LibraryView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = LibraryViewModel()
    @FocusState private var isGridFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 18)]

    var body: some View {
        let library = dependencies.library
        let items = viewModel.visibleItems(from: library.items)

        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(items) { item in
                    LibraryCell(item: item, isSelected: viewModel.selection.contains(item.id))
                        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) {
                                viewModel.toggle(item)
                            } else {
                                viewModel.select(item)
                            }
                            isGridFocused = true
                        }
                        .onDrag { NSItemProvider(object: item.url as NSURL) }
                        .contextMenu { contextMenu(for: item) }
                }
            }
            .padding(20)
        }
        .focusable()
        .focused($isGridFocused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            viewModel.togglePreview(in: items)
            return .handled
        }
        .onDeleteCommand {
            Task { await library.moveToTrash(viewModel.selectedItems(in: items)) }
        }
        .onExitCommand { viewModel.selection.removeAll() }
        .quickLookPreview($viewModel.previewURL, in: items.map(\.url))
        .overlay { emptyState(library: library, isFiltered: items.isEmpty && !library.items.isEmpty) }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: Text("Search captures"))
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $viewModel.kindFilter) {
                    ForEach(LibraryViewModel.KindFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.symbolName).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .help("Show screenshots, recordings, or both")
            }
            ToolbarItem {
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([library.folder])
                }
                .help("Show the save folder in Finder")
            }
        }
        .navigationSubtitle(Text("\(items.count) items"))
        .onChange(of: library.items) { _, newItems in
            viewModel.pruneSelection(keeping: newItems)
        }
    }

    @ViewBuilder
    private func emptyState(library: CaptureLibrary, isFiltered: Bool) -> some View {
        if library.isLoading {
            ProgressView()
        } else if let error = library.loadError {
            ContentUnavailableView {
                Label("Can't Open the Save Folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                SettingsLink { Text("Choose Another Folder…") }
            }
        } else if library.items.isEmpty {
            ContentUnavailableView {
                Label("No Captures Yet", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Screenshots you save appear here.")
            }
        } else if isFiltered {
            ContentUnavailableView.search(text: viewModel.searchText)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: LibraryItem) -> some View {
        let targets = viewModel.targets(for: item, in: dependencies.library.items)
        Button("Open") { targets.forEach { NSWorkspace.shared.open($0.url) } }
        Button("Quick Look") { viewModel.previewURL = item.url }
        Divider()
        Button("Copy") { dependencies.clipboard.copyFile(at: item.url) }
            .disabled(targets.count > 1)
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url)) }
        ShareLink(items: targets.map(\.url)) { Text("Share…") }
        Divider()
        Button("Move to Trash", role: .destructive) {
            Task { await dependencies.library.moveToTrash(targets) }
        }
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
                .frame(height: 150)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
                .overlay(alignment: .bottomLeading) {
                    if item.kind == .video {
                        Image(systemName: "video.fill")
                            .font(.caption)
                            .padding(6)
                            .background(.thinMaterial, in: .capsule)
                            .padding(10)
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

#Preview {
    let dependencies = AppDependencies.preview(screenRecording: .granted)
    LibraryView()
        .environment(dependencies)
        .frame(width: 800, height: 560)
}
