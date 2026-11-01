import AppKit
import Combine
import SwiftUI

/// The Capture page: permission status, the capture buttons, the replay buffer,
/// recent captures, and where new ones are saved, all in standard grouped sections.
struct CaptureHomeView: View {
    let showRecents: () -> Void

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        CaptureHomeContent(
            viewModel: CaptureHomeViewModel(permissions: dependencies.permissions),
            capture: dependencies.capture,
            recording: dependencies.recording,
            library: dependencies.library,
            showRecents: showRecents
        )
    }
}

private struct CaptureHomeContent: View {
    @State var viewModel: CaptureHomeViewModel
    let capture: CaptureCoordinator
    let recording: RecordingCoordinator
    let library: CaptureLibrary
    let showRecents: () -> Void

    var body: some View {
        Form {
            if viewModel.screenRecording == .notGranted {
                PermissionSection(viewModel: viewModel)
            }

            Section("Screenshot") {
                ActionGrid {
                    ForEach(QuickAction.screenshots) { action in
                        CaptureButton(action: action, isDisabled: capture.isCapturing) {
                            Task { await capture.run(action) }
                        }
                    }
                }
            }

            Section("Recording") {
                if recording.isRecording || recording.countdown != nil {
                    StopRecordingButton(recording: recording)
                } else {
                    ActionGrid {
                        ForEach(QuickAction.recordings) { action in
                            CaptureButton(action: action, isDisabled: recording.recorder.state != .idle) {
                                if let mode = action.recordingMode {
                                    Task { await recording.toggle(mode) }
                                }
                            }
                        }
                    }
                }
                ReplayRow()
            }

            if !library.items.isEmpty {
                Section {
                    RecentCapturesRow(items: Array(library.items.prefix(8)))
                } header: {
                    HStack {
                        Text("Recents")
                        Spacer()
                        Button("Show All", action: showRecents)
                            .buttonStyle(.link)
                    }
                }
            }

            Section {
                SaveLocationFooter()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background { AmbientBackground() }
        .animation(.panel, value: viewModel.screenRecording)
        .animation(.panel, value: library.items.isEmpty)
        .animation(.panel, value: recording.isRecording)
        .animation(.response, value: recording.countdown)
        .task {
            await viewModel.watchScreenRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refresh()
        }
    }
}

/// Equal-width buttons side by side.
private struct ActionGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Grid(horizontalSpacing: Design.spacingM) {
            GridRow { content }
        }
        .padding(.vertical, 4)
    }
}

/// One capture mode as a large standard button: icon over title, shortcut underneath.
private struct CaptureButton: View {
    let action: QuickAction
    let isDisabled: Bool
    let perform: () -> Void

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: action.symbolName)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 26)
                Text(action.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(settings.shortcuts[action.id]?.displayString ?? " ")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.extraLarge)
        .disabled(isDisabled)
        .help(action.title)
    }
}

/// While recording, the recording buttons become one Stop button with the elapsed time.
/// During the countdown it cancels instead.
private struct StopRecordingButton: View {
    let recording: RecordingCoordinator

    var body: some View {
        Button {
            Task { await recording.toggle(.area) }
        } label: {
            HStack {
                Image(systemName: recording.countdown == nil ? "stop.fill" : "xmark")
                if let remaining = recording.countdown {
                    Text("Cancel · \(remaining)")
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                } else if case .recording(let since) = recording.recorder.state {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text("Stop · \(Duration.seconds(max(0, context.date.timeIntervalSince(since))).formatted(.time(pattern: .minuteSecond)))")
                            .monospacedDigit()
                    }
                } else {
                    Text("Saving…")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.extraLarge)
        .disabled(recording.recorder.state == .finishing)
        .padding(.vertical, 4)
    }
}

/// The newest captures, side by side. Double-click opens one; drag it into any app.
private struct RecentCapturesRow: View {
    let items: [LibraryItem]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Design.spacingM) {
                ForEach(items) { item in
                    RecentThumbnail(item: item)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never)
    }
}

private struct RecentThumbnail: View {
    let item: LibraryItem

    var body: some View {
        FileThumbnail(url: item.url, maximumSize: CGSize(width: 240, height: 150))
            .frame(width: 128, height: 80)
            .clipShape(.rect(cornerRadius: Design.radiusS))
            .overlay {
                RoundedRectangle(cornerRadius: Design.radiusS)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
            .contentShape(.rect)
            .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
            .onDrag { NSItemProvider(object: item.url as NSURL) }
            .help(item.name)
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(.isButton)
    }
}

/// Turns the replay buffer on and off and saves what it holds.
private struct ReplayRow: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let buffer = dependencies.replay.buffer

        LabeledContent {
            HStack {
                if buffer.isOn {
                    SaveLastMenu()
                        .labelStyle(.titleOnly)
                        .fixedSize()
                }
                Toggle("Replay Buffer", isOn: Binding(
                    get: { settings.replayBufferEnabled },
                    set: { dependencies.replay.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        } label: {
            Text("Replay Buffer")
            // Ticks once a second while running, so the buffered amount counts up until full.
            TimelineView(.animation(minimumInterval: 1, paused: !isRunning(buffer))) { context in
                Text(status(buffer, at: context.date))
                    .monospacedDigit()
                    .contentTransition(.opacity)
            }
        }
        .animation(.response, value: buffer.state)
    }

    private func status(_ buffer: ReplayBuffer, at now: Date) -> String {
        let capacity = settings.replayBufferSeconds
        let length = Self.format(capacity)
        switch buffer.state {
        case .off: return String(localized: "Off. Turn it on to always keep the last \(length).")
        case .starting: return String(localized: "Starting…")
        case .running(let since):
            let held = min(max(Int(now.timeIntervalSince(since)), 0), capacity)
            return held < capacity
                ? String(localized: "\(Self.format(held)) of \(length) buffered")
                : String(localized: "Keeping the last \(length)")
        case .saving: return String(localized: "Saving…")
        }
    }

    private func isRunning(_ buffer: ReplayBuffer) -> Bool {
        if case .running = buffer.state { true } else { false }
    }

    private static func format(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}

/// One line saying where captures go, with a way to see them.
private struct SaveLocationFooter: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        LabeledContent {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([settings.saveFolderURL])
            }
        } label: {
            Text("Saving to")
            Text(settings.saveFolderURL.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Explains why Screen Recording access is needed and notices when it is granted.
private struct PermissionSection: View {
    let viewModel: CaptureHomeViewModel

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Recording access needed")
                        .font(.headline)
                    Text("Turn on Untitled in System Settings › Privacy & Security › Screen & System Audio Recording. If macOS offers to quit and reopen, choosing Later is fine: Untitled notices on its own.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Allow Access…") {
                    viewModel.requestScreenRecording()
                }
                .buttonStyle(.borderedProminent)
                Button("Open System Settings") {
                    viewModel.openScreenRecordingSettings()
                }
                Button {
                    Task { await viewModel.checkAgain() }
                } label: {
                    if viewModel.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check Again")
                    }
                }
                .disabled(viewModel.isChecking)
            }
            if !CodeSigningInfo.hasTeamIdentifier {
                Label {
                    Text("This build is signed only to run locally, so macOS forgets the permission every time it's rebuilt. In Xcode, choose a Team under Signing & Capabilities.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                .foregroundStyle(.secondary)
            }
            if viewModel.checkFoundNoAccess {
                HStack(spacing: Design.spacingS) {
                    Text("Already turned it on? Some Macs only apply it after a restart.")
                        .foregroundStyle(.secondary)
                    Button("Restart Untitled") {
                        viewModel.restart()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Needs permission") {
    let dependencies = AppDependencies.preview()
    CaptureHomeView(showRecents: {})
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 760, height: 620)
}

#Preview("Granted") {
    let dependencies = AppDependencies.preview(screenRecording: .granted)
    CaptureHomeView(showRecents: {})
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 760, height: 620)
}
#endif
