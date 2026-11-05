import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Clipboard history and captured-text history: whether each runs, how long it keeps things,
/// and which apps clipboard history ignores. Both histories offer the same choices.
struct ClipboardSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @State private var isConfirmingClear = false
    @State private var isConfirmingClearText = false

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Toggle("Keep clipboard history", isOn: $settings.keepsClipboardHistory)
                HistoryRetentionPicker(selection: $settings.clipboardRetention)
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
                Text("Clipboard History")
            } footer: {
                Text("Text and images you copy in any app stay on this Mac only. Choosing a shorter limit removes older items right away.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep captured text", isOn: $settings.keepsTextHistory)
                HistoryRetentionPicker(selection: $settings.textHistoryRetention)
                    .disabled(!settings.keepsTextHistory)
                LabeledContent("Saved snippets") {
                    Text(dependencies.textHistory.snippets.count, format: .number)
                        .monospacedDigit()
                }
                Button("Clear Captured Text…") { isConfirmingClearText = true }
                    .disabled(dependencies.textHistory.snippets.isEmpty)
                    .confirmationDialog("Clear captured text?", isPresented: $isConfirmingClearText) {
                        Button("Clear", role: .destructive) { dependencies.textHistory.removeAll() }
                    } message: {
                        Text("Every saved snippet is removed from Library and the menu bar. Your clipboard isn't affected.")
                    }
            } header: {
                Text("Captured Text")
            } footer: {
                Text("Text from Capture Text, kept in Retrace's own folder rather than your save folder. Turning it off pauses it and keeps what's saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(settings.clipboardExcludedApps, id: \.self) { bundleID in
                    ExcludedAppRow(bundleID: bundleID) {
                        settings.clipboardExcludedApps.removeAll { $0 == bundleID }
                    }
                }
                Button("Add App…", action: addApp)
            } header: {
                Text("Ignore copies from")
            } footer: {
                Text("Copies marked private by an app are skipped. App exclusions use the app in front when the clipboard change is detected and may miss copies written by a different app.")
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
}

/// How long a history keeps things: forever, then time limits from shortest to longest, then
/// counts from fewest to most. Clipboard history and captured text share it.
struct HistoryRetentionPicker: View {
    @Binding var selection: HistoryRetention

    var body: some View {
        Picker("Keep items", selection: $selection) {
            Text(HistoryRetention.forever.title).tag(HistoryRetention.forever)
            Divider()
            ForEach(HistoryRetention.allCases.filter(\.isTimeLimit)) { Text($0.title).tag($0) }
            Divider()
            ForEach(HistoryRetention.allCases.filter { $0.maximumCount != nil }) { Text($0.title).tag($0) }
        }
    }
}

/// An ignored app by its icon and name, with a button to stop ignoring it. An app that
/// isn't installed shows its usual name, marked as not installed.
private struct ExcludedAppRow: View {
    let bundleID: String
    let remove: () -> Void

    /// Names for the apps ignored by default, for when they aren't installed.
    private static let knownNames = [
        "com.apple.Passwords": "Passwords",
        "com.apple.keychainaccess": "Keychain Access",
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden",
        "io.trezor.TrezorSuite": "Trezor Suite",
        "com.ledger.live": "Ledger Live",
    ]

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        LabeledContent {
            Button("Remove", systemImage: "minus.circle.fill", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Stop ignoring this app")
        } label: {
            HStack(spacing: 8) {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(FileManager.default.displayName(atPath: url.path(percentEncoded: false)).replacingOccurrences(of: ".app", with: ""))
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 16))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.tertiary)
                    Text(Self.knownNames[bundleID] ?? bundleID)
                    Text("Not installed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
