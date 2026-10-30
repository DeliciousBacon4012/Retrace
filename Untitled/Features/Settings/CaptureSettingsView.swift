import SwiftUI

struct CaptureSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("After capture") {
                Toggle("Copy to clipboard", isOn: $settings.copiesToClipboard)
                Toggle("Save to folder", isOn: $settings.savesToFolder)
                Toggle("Show Quick Access overlay", isOn: $settings.showsQuickAccess)
                Toggle("Open in editor", isOn: $settings.opensEditor)
            }

            Section("Quick Access") {
                Picker("Position", selection: $settings.overlayCorner) {
                    ForEach(OverlayCorner.allCases) { Text($0.title).tag($0) }
                }
                Picker("Close automatically", selection: $settings.overlayAutoCloseSeconds) {
                    Text("Never").tag(0)
                    Text("After 5 seconds").tag(5)
                    Text("After 10 seconds").tag(10)
                    Text("After 30 seconds").tag(30)
                }
            }

            Section {
                Toggle("Include the pointer", isOn: $settings.includesCursor)
                Toggle("Include window shadow", isOn: $settings.includesWindowShadow)
            } footer: {
                PendingFeatureFooter()
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    CaptureSettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .frame(width: 520)
}
