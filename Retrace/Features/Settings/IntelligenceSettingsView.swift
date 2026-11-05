import SwiftUI

/// Apple's on-device image and text understanding, and how Retrace uses it.
struct IntelligenceSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @AppStorage(SmartCropMode.storageKey) private var smartCropMode: SmartCropMode = .attention
    @AppStorage(TextRecognitionSpeed.storageKey) private var textSpeed: TextRecognitionSpeed = .accurate

    var body: some View {
        @Bindable var settings = settings
        let index = dependencies.contentIndex

        Group {
            Section {
                Toggle("Search inside images", isOn: $settings.indexesLibraryContent)
                LabeledContent("Images read") {
                    HStack(spacing: Design.spacingS) {
                        if index.isIndexing {
                            ProgressView().controlSize(.small)
                        }
                        Text(index.indexedCount, format: .number)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
            } header: {
                Text("Library")
            } footer: {
                Text("Retrace reads the text in your screenshots and recognizes what's in them, so the Library's search can find them and Find Similar can compare them. It all happens on this Mac, slowly in the background. Turning this off deletes what it learned.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Smart Crop looks for", selection: $smartCropMode) {
                    ForEach(SmartCropMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Text recognition", selection: $textSpeed) {
                    ForEach(TextRecognitionSpeed.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Vision")
            } footer: {
                Text("Attention finds where your eye goes first, Objects frames everything distinct, and Document finds a page or card. Accurate text recognition reads small type and many languages; Fast suits quick grabs of clear text.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
