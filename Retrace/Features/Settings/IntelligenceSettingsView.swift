import SwiftUI

/// Searching inside Library images, read on this Mac. Shown in General.
struct LibrarySearchSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings

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
                Text("Search")
            } footer: {
                Text("Retrace reads the text in your screenshots and recognizes what's in them, so the Library's search can find them and Find Similar can compare them. It all happens on this Mac, slowly in the background. Turning this off deletes what it learned.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        }
    }
}

/// Smart Crop and text recognition with Apple's Vision. Shown in Editor.
struct VisionSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @AppStorage(SmartCropMode.storageKey) private var smartCropMode: SmartCropMode = .automatic
    @AppStorage(TextRecognitionSpeed.storageKey) private var textSpeed: TextRecognitionSpeed = .accurate

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Picker("Smart Crop looks for", selection: $smartCropMode) {
                    ForEach(SmartCropMode.allCases) { Text($0.title).tag($0) }
                }
                .capsuleSegmentedStyle()
                Picker("Text recognition", selection: $textSpeed) {
                    ForEach(TextRecognitionSpeed.allCases) { Text($0.title).tag($0) }
                }
                .capsuleSegmentedStyle()
                Toggle("Keep line breaks in copied text", isOn: $settings.keepsOCRLineBreaks)
            } header: {
                Text("Vision")
            } footer: {
                Text("Automatic picks for you: a page or card if there is one, every distinct object if there are several, or where your eye goes first.  Accurate text recognition reads small type and many languages; Fast suits quick grabs of clear text. Recognized text is copied automatically; turn off line breaks to join it into one paragraph.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
