import AppKit
import SwiftUI

struct OutputSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Images") {
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.writable) { Text($0.title).tag($0) }
                }
                Toggle("Save Retina captures at standard size", isOn: $settings.downscalesRetina)
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
    }
}

#Preview {
    OutputSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
