import SwiftUI
import UniformTypeIdentifiers

/// An entry point to the existing annotation editor from the main workspace.
struct EditorLandingView: View {
    let onBrowseLibrary: () -> Void

    @Environment(AppDependencies.self) private var dependencies
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            Spacer(minLength: 24)

            VStack(spacing: 18) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Drop an image to edit")
                        .font(.title2.weight(.semibold))
                    Text("Open a screenshot or another image in the annotation editor.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button("Choose Image…", systemImage: "folder") {
                        isImporting = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Browse Library", systemImage: "square.grid.2x2", action: onBrowseLibrary)
                        .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: 520, minHeight: 300)
            .padding(28)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                    )
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, Self.isImage(url) else {
                    errorMessage = String(localized: "Choose an image file to open in the editor.")
                    return false
                }
                dependencies.editor.open(fileAt: url)
                return true
            } isTargeted: { isTargeted in
                isDropTargeted = isTargeted
            }

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                guard Self.isImage(url) else {
                    errorMessage = String(localized: "Choose an image file to open in the editor.")
                    return
                }
                dependencies.editor.open(fileAt: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't Open Image", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }
}
