import AppKit
import SwiftUI

/// Where captures are saved, what they're called, how they're encoded, and what they reveal.
struct FilesPrivacySettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
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
                TextField("File name", text: $settings.filenameTemplate)
                LabeledContent("Example") {
                    Text(exampleFileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Location")
            } footer: {
                Text("Use {date} and {time} to insert when the capture was taken.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
            } header: {
                Text("Format")
            } footer: {
                Text(formatFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Remove metadata from images", isOn: $settings.stripsMetadata)
                Toggle("Remove metadata from videos", isOn: $settings.stripsVideoMetadata)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Images keep only their pixels: no capture date, no app name, and a standard color profile instead of your display's own. Images with redactions are always saved this way. Videos keep no location, device or app details.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .animation(.response, value: settings.imageFormat)
    }

    /// The name the next screenshot would get, so the template's effect is visible as you type.
    private var exampleFileName: String {
        FileNameTemplate.fileName(from: settings.filenameTemplate, date: .now) + "." + settings.imageFormat.fileExtension
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
    FilesPrivacySettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
#endif
