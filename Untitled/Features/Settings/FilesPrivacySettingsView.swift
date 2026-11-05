import AppKit
import SwiftUI

/// Where captures are saved, what they're called, how they're encoded, and what they reveal.
struct FilesPrivacySettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                if settings.saveFolderPaths.count > 1 {
                    Picker("Default location", selection: Binding(
                        get: { settings.saveFolderPath },
                        set: { settings.setDefaultSaveFolder($0) }
                    )) {
                        ForEach(settings.saveFolderPaths, id: \.self) { path in
                            Text(settings.saveFolderDisplayName(for: path)).tag(path)
                        }
                    }
                }

                ForEach(settings.saveFolderPaths, id: \.self) { path in
                    HStack(spacing: 12) {
                        Image(systemName: path == settings.saveFolderPath ? "checkmark.circle.fill" : "folder")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.saveFolderDisplayName(for: path))
                                .lineLimit(1)
                            if path == settings.saveFolderPath {
                                Text("Default")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .help(path)

                        Spacer(minLength: 8)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path, isDirectory: true)])
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .help("Show in Finder")
                        .accessibilityLabel("Show \(settings.saveFolderDisplayName(for: path)) in Finder")

                        if settings.saveFolderPaths.count > 1 {
                            Button(role: .destructive) {
                                settings.removeSaveFolder(path)
                            } label: {
                                Image(systemName: "minus")
                            }
                            .help("Remove save location")
                            .accessibilityLabel("Remove \(settings.saveFolderDisplayName(for: path))")
                        }
                    }
                }

                Button("Add Location…", systemImage: "plus") {
                    if let folder = FolderPicker.chooseFolder(startingAt: settings.saveFolderURL) {
                        settings.addSaveFolder(folder)
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
                Text("Choose a default for shortcuts and add other folders for individual captures. Removing a location only removes it from retrace; its files stay in place. Use {date} and {time} in the filename.")
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
                            Slider(value: $settings.imageQuality, in: SettingsStore.imageQualityChoices, step: 0.05) {
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
        .settingsPage()
}
#endif
