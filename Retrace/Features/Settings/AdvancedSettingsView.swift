import AppKit
import OSLog
import UniformTypeIdentifiers
import SwiftUI

/// The technical side of Retrace: memory, permissions, what it logged, its data on disk, and a
/// full reset. Logs and sizes are read in the background, only while the page is open.
struct AdvancedSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @State private var isConfirmingReset = false
    @State private var isConfirmingRebuild = false
    @State private var screenRecording: PermissionStatus = .notGranted
    @State private var problems: [Diagnostics.Problem] = []
    @State private var hasReadProblems = false
    @State private var dataSize: Int64?
    @State private var copiedSummary = false

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section {
                LabeledContent("Memory in use") {
                    Text(Int64(dependencies.memory.footprint), format: .byteCount(style: .memory))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Picker("Thumbnail memory", selection: $settings.thumbnailMemoryMB) {
                    ForEach(SettingsStore.thumbnailMemoryChoices, id: \.self) { megabytes in
                        Text(Int64(megabytes) * 1_048_576, format: .byteCount(style: .memory)).tag(megabytes)
                    }
                }
                LabeledContent("Caches") {
                    Button("Clear Caches") {
                        dependencies.relieveMemory()
                        dependencies.memory.refresh()
                    }
                }
            } header: {
                Text("Memory")
            } footer: {
                Text("The same number Activity Monitor shows. When macOS runs short of memory, Retrace lets go of thumbnails and editor previews by itself; they come back when needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    HStack {
                        Label(
                            screenRecording == .granted ? "Allowed" : "Not allowed",
                            systemImage: screenRecording == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(screenRecording == .granted ? Color.green : Color.orange)
                        Button("Open System Settings") {
                            dependencies.permissions.openScreenRecordingSettings()
                        }
                    }
                }
            }

            Section {
                problemList
                Toggle("Log slow moments", isOn: $settings.logsSlowMoments)
                LabeledContent("Logs") {
                    HStack {
                        Button("Save Log…", action: saveLog)
                        Button("Open Console", action: openConsole)
                    }
                }
                LabeledContent("Diagnostic summary") {
                    Button(copiedSummary ? "Copied" : "Copy Summary", action: copySummary)
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Errors are what Retrace logged since it launched; the latest five show here, and Save Log has everything. Slow moments are times the interface stopped answering for 100 ms or more. The summary lists this Mac, its displays, and Retrace's state, without file names or anything you copied. In Console, filter by \(Log.subsystem).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Data folder") {
                    HStack {
                        if let dataSize {
                            Text(dataSize, format: .byteCount(style: .file))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Button("Show in Finder", action: showDataFolder)
                    }
                }
                LabeledContent("Search index") {
                    HStack {
                        Text("\(dependencies.contentIndex.indexedCount) images")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Rebuild…") { isConfirmingRebuild = true }
                            .disabled(!settings.indexesLibraryContent)
                            .confirmationDialog("Rebuild the search index?", isPresented: $isConfirmingRebuild) {
                                Button("Rebuild") { dependencies.rebuildContentIndex() }
                            } message: {
                                Text("Retrace forgets what it learned about your images and reads them again in the background. Search inside images is incomplete until it finishes.")
                            }
                    }
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Clipboard history, captured text, the search index, and originals of edited captures. Your captures are in your save folder, not here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings…", role: .destructive) {
                    isConfirmingReset = true
                }
                .confirmationDialog(
                    "Reset all settings?",
                    isPresented: $isConfirmingReset
                ) {
                    Button("Reset", role: .destructive) {
                        dependencies.settings.resetToDefaults()
                    }
                } message: {
                    Text("Every preference returns to its default. Your captures and histories are not affected.")
                }
            }
        }
        .onAppear {
            screenRecording = dependencies.permissions.screenRecordingStatus
        }
        .task {
            // Live while the pane is open, and only then.
            while !Task.isCancelled {
                withAnimation { dependencies.memory.refresh() }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task {
            // The log store is slower to read, so less often.
            while !Task.isCancelled {
                let read = await Task.detached(priority: .utility) { Diagnostics.recentProblems() }.value
                guard !Task.isCancelled else { return }
                withAnimation(.response) {
                    problems = read
                    hasReadProblems = true
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .task {
            guard let folder = Diagnostics.dataFolder else { return }
            dataSize = await Task.detached(priority: .utility) { Diagnostics.size(of: folder) }.value
        }
    }

    @ViewBuilder
    private var problemList: some View {
        LabeledContent("Errors since launch") {
            if !hasReadProblems {
                ProgressView().controlSize(.small)
            } else if problems.isEmpty {
                Label("None", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Text(problems.count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(problems.contains(where: \.isFault) ? Color.red : Color.orange)
                    .contentTransition(.numericText())
            }
        }
        // The latest few, newest first. Save Log has everything.
        ForEach(problems.prefix(5)) { problem in
            ProblemRow(problem: problem)
        }
    }

    // MARK: Actions

    private func copySummary() {
        let state = [
            "Screen Recording \(screenRecording == .granted ? "allowed" : "not allowed")",
            "Memory in use \(ByteCountFormatter.string(fromByteCount: Int64(dependencies.memory.footprint), countStyle: .memory))",
            "Library \(dependencies.library.items.count) items, search index \(dependencies.contentIndex.indexedCount) images\(dependencies.contentIndex.isIndexing ? ", indexing" : "")",
            "Clipboard history \(settings.keepsClipboardHistory ? "on" : "off"), \(dependencies.clipboardHistory.entries.count) items",
            "Captured text \(settings.keepsTextHistory ? "on" : "off"), \(dependencies.textHistory.snippets.count) snippets",
            "Replay buffer \(settings.replayBufferEnabled ? "on" : "off")",
            "Errors since launch \(problems.count)",
        ]
        let recent = problems.prefix(10).map { "  [\($0.category)] \($0.message)" }
        let text = (Diagnostics.systemSummary() + Diagnostics.displaySummary() + state + (recent.isEmpty ? [] : ["Latest errors:"] + recent))
            .joined(separator: "\n")
        dependencies.clipboard.copy(text: text)
        withAnimation(.pop) { copiedSummary = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.pop) { copiedSummary = false }
        }
    }

    private func saveLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Retrace Log.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task.detached(priority: .userInitiated) {
            let text = Diagnostics.logText()
            do {
                try Data(text.utf8).write(to: url, options: .atomic)
            } catch {
                Log.app.error("Saving the log failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func openConsole() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func showDataFolder() {
        guard let folder = Diagnostics.dataFolder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

/// One logged error: when, where in Retrace, and what it said.
private struct ProblemRow: View {
    let problem: Diagnostics.Problem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(problem.category == "hang" ? "Slow moment" : problem.category.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(problem.isFault ? Color.red : Color.orange)
                Spacer()
                Text(problem.date, format: .dateTime.hour().minute().second())
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(problem.message)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    let dependencies = AppDependencies.preview()
    AdvancedSettingsView()
        .environment(dependencies)
        .environment(dependencies.settings)
        .settingsPage()
}
#endif
