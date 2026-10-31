import AppKit
import SwiftUI

struct OutputSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.writable) { Text($0.title).tag($0) }
                }
                if settings.imageFormat.isLossy {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: $settings.imageQuality, in: 0.3...1, step: 0.05) {
                                Text("Quality")
                            } minimumValueLabel: {
                                Image(systemName: "tortoise").accessibilityLabel("Smaller files")
                            } maximumValueLabel: {
                                Image(systemName: "sparkles").accessibilityLabel("Best quality")
                            }
                            .labelsHidden()
                            Text(settings.imageQuality.formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Toggle("Save Retina captures at standard size", isOn: $settings.downscalesRetina)
            } footer: {
                Text(formatFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Remove metadata", isOn: $settings.stripsMetadata)
            } footer: {
                Text("Leaves out location, camera, and device details when saving or exporting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Location") {
                LabeledContent("Save to") {
                    HStack {
                        Text(settings.saveFolderURL.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(settings.saveFolderPath)
                        Button("Choose…") {
                            if let folder = FolderPicker.chooseFolder(startingAt: settings.saveFolderURL) {
                                settings.saveFolderPath = folder.path
                            }
                        }
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([settings.saveFolderURL])
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .help("Show in Finder")
                        .accessibilityLabel("Show in Finder")
                    }
                }
            }

            Section {
                TextField("File name", text: $settings.filenameTemplate)
            } header: {
                Text("File name")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use {date} and {time} to insert when the capture was taken.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    PendingFeatureFooter()
                }
            }
        }
        .formStyle(.grouped)
        .animation(.response, value: settings.imageFormat)
    }

    private var formatFooter: String {
        switch settings.imageFormat {
        case .png: String(localized: "PNG keeps every pixel exact. Best for text and interface screenshots.")
        case .jpeg: String(localized: "JPEG makes small files that open everywhere. Fine detail can blur a little.")
        case .heic, .avif: String(localized: "Much smaller than PNG with very little visible loss. Some older apps can't open it.")
        case .tiff: String(localized: "TIFF keeps every pixel exact, with large files.")
        case .gif: String(localized: "GIF uses only 256 colors.")
        }
    }
}

#if DEBUG
#Preview {
    OutputSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
#endif
