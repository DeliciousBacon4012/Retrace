import SwiftUI

/// One clipboard item shown in the unified Library grid.
struct ClipboardCard: View {
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
                            .background(.regularMaterial, in: .capsule)
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
