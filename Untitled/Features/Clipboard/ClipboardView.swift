import AppKit
import QuickLook
import SwiftUI

/// Everything you copied, newest first. Click copies it again; double-click opens it.
struct ClipboardView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var selection: ClipboardEntry.ID?
    @State private var copiedID: ClipboardEntry.ID?
    @State private var previewURL: URL?
    @FocusState private var isFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 320), spacing: 20)]

    var body: some View {
        let history = dependencies.clipboardHistory
        let entries = history.entries

        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(entries) { entry in
                    ClipboardCard(
                        entry: entry,
                        imageURL: history.imageURL(for: entry),
                        isSelected: selection == entry.id,
                        isCopied: copiedID == entry.id
                    )
                    .onTapGesture { click(entry) }
                    .onDrag { itemProvider(for: entry) }
                    .contextMenu { contextMenu(for: entry) }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            togglePreview(in: entries)
            return .handled
        }
        .onDeleteCommand {
            if let selection { history.remove([selection]) }
        }
        .onExitCommand { selection = nil }
        .quickLookPreview($previewURL, in: entries.compactMap(history.imageURL(for:)))
        .overlay { emptyState(isEmpty: entries.isEmpty) }
        .task(id: copiedID) {
            guard copiedID != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
    }

    @ViewBuilder
    private func emptyState(isEmpty: Bool) -> some View {
        if isEmpty, !dependencies.settings.keepsClipboardHistory {
            ContentUnavailableView {
                Label("Clipboard History Is Off", systemImage: "clipboard")
            } description: {
                Text("Turn it on to keep the text and images you copy in any app.")
            } actions: {
                Button("Turn On") { dependencies.settings.keepsClipboardHistory = true }
            }
        } else if isEmpty {
            ContentUnavailableView {
                Label("Nothing Copied Yet", systemImage: "clipboard")
            } description: {
                Text("Text and images you copy in any app appear here and stay until you remove them.")
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for entry: ClipboardEntry) -> some View {
        let history = dependencies.clipboardHistory
        Button("Copy") { copy(entry) }
        if let url = history.imageURL(for: entry) {
            Button("Open in Editor") { dependencies.editor.openCopy(ofImageAt: url) }
            Button("Quick Look") { previewURL = url }
        } else if let text = entry.text {
            let app = dependencies.settings.plainTextApp
            Button("Open in \(PlainTextOpener.appName(for: app))") { PlainTextOpener.open(text, in: app) }
        }
        Divider()
        Button("Delete", role: .destructive) { history.remove([entry.id]) }
    }

    private func click(_ entry: ClipboardEntry) {
        isFocused = true
        selection = entry.id
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            open(entry)
        } else {
            copy(entry)
            if previewURL != nil, let url = dependencies.clipboardHistory.imageURL(for: entry) {
                previewURL = url
            }
        }
    }

    private func open(_ entry: ClipboardEntry) {
        previewURL = nil
        if let url = dependencies.clipboardHistory.imageURL(for: entry) {
            dependencies.editor.openCopy(ofImageAt: url)
        } else if let text = entry.text {
            PlainTextOpener.open(text, in: dependencies.settings.plainTextApp)
        }
    }

    private func copy(_ entry: ClipboardEntry) {
        dependencies.clipboardHistory.copy(entry)
        copiedID = entry.id
    }

    private func togglePreview(in entries: [ClipboardEntry]) {
        let history = dependencies.clipboardHistory
        if previewURL != nil {
            previewURL = nil
        } else if let selection, let entry = entries.first(where: { $0.id == selection }) {
            previewURL = history.imageURL(for: entry)
        }
    }

    private func itemProvider(for entry: ClipboardEntry) -> NSItemProvider {
        if let url = dependencies.clipboardHistory.imageURL(for: entry) {
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        return NSItemProvider(object: (entry.text ?? "") as NSString)
    }
}

/// One copied item: the text, or the image, with where and when it was copied.
private struct ClipboardCard: View {
    let entry: ClipboardEntry
    let imageURL: URL?
    let isSelected: Bool
    let isCopied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
                .frame(maxWidth: .infinity)
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
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .animation(.response, value: isCopied)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Copies it again")
    }

    @ViewBuilder
    private var preview: some View {
        if let imageURL {
            FileThumbnail(url: imageURL)
                .padding(6)
        } else {
            Text(entry.text ?? "")
                .font(.callout)
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
    }

    private var title: String {
        switch entry.content {
        case .text(let text):
            text.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        case .image(_, let width, let height):
            String(localized: "Image \(width) × \(height)")
        }
    }

    private var detail: String {
        let date = entry.date.formatted(date: .abbreviated, time: .shortened)
        guard let app = entry.appName else { return date }
        return "\(date) · \(app)"
    }
}
