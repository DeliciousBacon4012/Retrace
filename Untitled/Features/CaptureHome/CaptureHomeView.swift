import AppKit
import Combine
import SwiftUI

/// The Capture tab: permission status, the capture buttons, recent captures,
/// and where new ones are saved.
struct CaptureHomeView: View {
    let showLibrary: () -> Void

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        CaptureHomeContent(
            viewModel: CaptureHomeViewModel(permissions: dependencies.permissions),
            capture: dependencies.capture,
            recording: dependencies.recording,
            library: dependencies.library,
            showLibrary: showLibrary
        )
    }
}

private struct CaptureHomeContent: View {
    @State var viewModel: CaptureHomeViewModel
    let capture: CaptureCoordinator
    let recording: RecordingCoordinator
    let library: CaptureLibrary
    let showLibrary: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.spacingXL) {
                if viewModel.screenRecording == .notGranted {
                    PermissionCard(viewModel: viewModel)
                        .transition(.blurReplace.combined(with: .scale(0.96)))
                }

                VStack(alignment: .leading, spacing: Design.spacingM) {
                    SectionLabel("Screenshot")
                    TileRow {
                        ForEach(QuickAction.screenshots) { action in
                            CaptureTile(action: action, title: action.title, isActive: false, isDisabled: capture.isCapturing) {
                                if let mode = action.captureMode {
                                    Task { await capture.capture(mode) }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Design.spacingM) {
                    SectionLabel("Recording")
                    TileRow {
                        ForEach(QuickAction.recordings) { action in
                            CaptureTile(
                                action: action,
                                title: recording.isRecording ? String(localized: "Stop Recording") : action.title,
                                isActive: recording.isRecording,
                                isDisabled: recording.recorder.state == .starting || recording.recorder.state == .finishing
                            ) {
                                if let mode = action.recordingMode {
                                    Task { await recording.toggle(mode) }
                                }
                            }
                        }
                    }
                    ReplayRow()
                }

                if !library.items.isEmpty {
                    VStack(alignment: .leading, spacing: Design.spacingM) {
                        HStack {
                            SectionLabel("Recent")
                            Spacer()
                            Button("Show All", action: showLibrary)
                                .buttonStyle(.link)
                                .font(.callout)
                        }
                        RecentCapturesRow(items: Array(library.items.prefix(8)))
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                VStack(alignment: .leading, spacing: Design.spacingM) {
                    SectionLabel("Output")
                    SaveLocationRow()
                }
            }
            .padding(Design.spacingXL)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(.panel, value: viewModel.screenRecording)
            .animation(.panel, value: library.items.isEmpty)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background { AmbientBackground() }
        .task {
            await viewModel.watchScreenRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refresh()
        }
    }
}

/// Lays tiles out in one row of equal widths, on one shared glass layer so
/// neighbouring tiles blend as they're pressed.
private struct TileRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: Design.spacingM) {
            HStack(spacing: Design.spacingM) {
                content
            }
        }
    }
}

/// A large glass button for one capture mode, with its shortcut in the corner.
private struct CaptureTile: View {
    let action: QuickAction
    let title: String
    let isActive: Bool
    let isDisabled: Bool
    let perform: () -> Void

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: isActive ? "stop.circle.fill" : action.symbolName)
                        .font(.system(size: 24, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isActive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(height: 28)
                    Spacer(minLength: 4)
                    if let shortcut = settings.shortcuts[action.id] {
                        ShortcutChip(shortcut: shortcut)
                    }
                }
                Spacer(minLength: Design.spacingM)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.interpolate)
                    .lineLimit(1)
            }
            .padding(Design.spacingL)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .contentShape(.rect(cornerRadius: Design.radiusL))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.radiusL))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .animation(.response, value: isActive)
        .help(title)
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
        .scrollClipDisabled()
    }
}

private struct RecentThumbnail: View {
    let item: LibraryItem
    @State private var isHovering = false

    var body: some View {
        FileThumbnail(url: item.url, maximumSize: CGSize(width: 240, height: 150))
            .frame(width: 156, height: 100)
            .clipShape(.rect(cornerRadius: Design.radiusS))
            .padding(5)
            .glassEffect(.regular, in: .rect(cornerRadius: Design.radiusM))
            .scaleEffect(isHovering ? 1.04 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 10, y: 6)
            .animation(.response, value: isHovering)
            .onHover { isHovering = $0 }
            .contentShape(.rect)
            .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
            .onDrag { NSItemProvider(object: item.url as NSURL) }
            .help(item.name)
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(.isButton)
    }
}

/// A rounded glass card for a row of settings or status.
private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(Design.spacingL)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: Design.radiusL))
    }
}

/// Turns the replay buffer on and off and saves what it holds.
private struct ReplayRow: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let buffer = dependencies.replay.buffer

        GlassCard {
            HStack(spacing: Design.spacingM) {
                Image(systemName: "gobackward")
                    .font(.title2)
                    .foregroundStyle(buffer.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .symbolEffect(.rotate, value: buffer.isOn)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Replay Buffer")
                            .font(.headline)
                        if case .running = buffer.state {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                                .shadow(color: .green.opacity(0.8), radius: 4)
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityHidden(true)
                        }
                    }
                    Text(status(buffer))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                if let shortcut = settings.shortcuts["saveReplay"], buffer.isOn {
                    ShortcutChip(shortcut: shortcut)
                        .transition(.opacity)
                }
                Button("Save Replay") {
                    Task { await dependencies.replay.saveClip() }
                }
                .buttonStyle(.glassProminent)
                .disabled(!buffer.isOn || buffer.state == .saving)
                Toggle("Replay Buffer", isOn: Binding(
                    get: { settings.replayBufferEnabled },
                    set: { dependencies.replay.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .animation(.response, value: buffer.state)
        }
    }

    private func status(_ buffer: ReplayBuffer) -> String {
        let length = Duration.seconds(settings.replayBufferSeconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
        switch buffer.state {
        case .off: return String(localized: "Off. Turn it on to always keep the last \(length).")
        case .starting: return String(localized: "Starting…")
        case .running: return String(localized: "Keeping the last \(length).")
        case .saving: return String(localized: "Saving…")
        }
    }
}

/// Where captures are saved, with buttons to change it or reveal it.
private struct SaveLocationRow: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        GlassCard {
            VStack(alignment: .leading, spacing: Design.spacingM) {
                HStack(spacing: Design.spacingM) {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save to")
                            .font(.headline)
                        Text(settings.saveFolderURL.path(percentEncoded: false))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Change…") {
                        if let folder = FolderPicker.chooseFolder(startingAt: settings.saveFolderURL) {
                            settings.saveFolderPath = folder.path(percentEncoded: false)
                        }
                    }
                    .buttonStyle(.glass)
                    Button("Show in Finder", systemImage: "arrow.up.forward.app") {
                        NSWorkspace.shared.activateFileViewerSelecting([settings.saveFolderURL])
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .help("Show in Finder")
                }
                Divider()
                HStack(spacing: Design.spacingL) {
                    Toggle("Save", isOn: $settings.savesToFolder)
                    Toggle("Copy to clipboard", isOn: $settings.copiesToClipboard)
                    Toggle("Show thumbnail", isOn: $settings.showsQuickAccess)
                    Spacer()
                    Picker("Format", selection: $settings.imageFormat) {
                        ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}

/// Explains why Screen Recording access is needed and notices when it is granted.
private struct PermissionCard: View {
    let viewModel: CaptureHomeViewModel

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: Design.spacingM) {
                Image(systemName: "lock.shield")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, options: .repeat(2))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Design.spacingS) {
                    Text("Screen Recording access needed")
                        .font(.headline)
                    Text("Turn on Untitled in System Settings › Privacy & Security › Screen & System Audio Recording. If macOS offers to quit and reopen, choosing Later is fine: Untitled notices on its own.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Allow Access…") {
                            viewModel.requestScreenRecording()
                        }
                        .buttonStyle(.glassProminent)
                        Button("Open System Settings") {
                            viewModel.openScreenRecordingSettings()
                        }
                        .buttonStyle(.glass)
                        Button {
                            Task { await viewModel.checkAgain() }
                        } label: {
                            if viewModel.isChecking {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Check Again")
                            }
                        }
                        .buttonStyle(.glass)
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
                        .font(.callout)
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
                        .font(.callout)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview("Needs permission") {
    let dependencies = AppDependencies.preview()
    CaptureHomeView(showLibrary: {})
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 760, height: 620)
}

#Preview("Granted") {
    let dependencies = AppDependencies.preview(screenRecording: .granted)
    CaptureHomeView(showLibrary: {})
        .environment(dependencies)
        .environment(dependencies.settings)
        .frame(width: 760, height: 620)
}
