import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Clipboard history: whether it runs, how long it keeps things, and which apps it ignores.
struct ClipboardSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @State private var isConfirmingClear = false
    @State private var selectedApp: String?

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Toggle("Keep clipboard history", isOn: $settings.keepsClipboardHistory)
                Picker("Keep items", selection: $settings.clipboardRetention) {
                    Text(ClipboardRetention.forever.title).tag(ClipboardRetention.forever)
                    Divider()
                    ForEach(ClipboardRetention.allCases.filter(\.isTimeLimit)) { Text($0.title).tag($0) }
                    Divider()
                    ForEach(ClipboardRetention.allCases.filter { $0.maximumCount != nil }) { Text($0.title).tag($0) }
                }
                .disabled(!settings.keepsClipboardHistory)
                LabeledContent("Saved items") {
                    Text(dependencies.clipboardHistory.entries.count, format: .number)
                        .monospacedDigit()
                }
                Button("Clear Clipboard History…") { isConfirmingClear = true }
                    .disabled(dependencies.clipboardHistory.entries.isEmpty)
                    .confirmationDialog("Clear clipboard history?", isPresented: $isConfirmingClear) {
                        Button("Clear History", role: .destructive) { dependencies.clipboardHistory.removeAll() }
                    } message: {
                        Text("Everything in clipboard history is deleted. This can't be undone.")
                    }
            } header: {
                Text("History")
            } footer: {
                Text("Text and images you copy in any app are kept on this Mac only. Choosing a shorter limit removes older items right away.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                List(selection: $selectedApp) {
                    ForEach(settings.clipboardExcludedApps, id: \.self) { bundleID in
                        ExcludedAppRow(bundleID: bundleID)
                            .tag(bundleID)
                    }
                }
                .frame(minHeight: 120)
                .onDeleteCommand(perform: removeSelected)
                HStack {
                    Button("Add App…", action: addApp)
                    Button("Remove", action: removeSelected)
                        .disabled(selectedApp == nil)
                    Spacer()
                }
            } header: {
                Text("Ignore copies from")
            } footer: {
                Text("Copies that password managers mark as private are never kept, whichever app they come from.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Ignore")
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        for id in ids where !settings.clipboardExcludedApps.contains(id) {
            settings.clipboardExcludedApps.append(id)
        }
    }

    private func removeSelected() {
        guard let selectedApp else { return }
        settings.clipboardExcludedApps.removeAll { $0 == selectedApp }
        self.selectedApp = nil
    }
}

/// An ignored app by its icon and name, or its identifier when it isn't installed.
private struct ExcludedAppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(FileManager.default.displayName(atPath: url.path(percentEncoded: false)).replacingOccurrences(of: ".app", with: ""))
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.secondary)
                Text(bundleID)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview()
    ClipboardSettingsView()
        .settingsPage()
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 560, height: 540)
}
#endif
