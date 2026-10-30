import AppKit
import Combine
import SwiftUI

/// The landing screen: permission status and quick actions.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        HomeContent(viewModel: HomeViewModel(permissions: dependencies.permissions))
    }
}

private struct HomeContent: View {
    @State var viewModel: HomeViewModel

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if viewModel.screenRecording == .notGranted {
                    permissionCard
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Actions")
                        .font(.headline)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(QuickAction.all) { action in
                            QuickActionTile(action: action, isEnabled: false) {}
                        }
                    }
                    Text("Capture tools arrive in the next few updates. The Roadmap lists everything planned.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Home")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Untitled")
                .font(.largeTitle.weight(.semibold))
            Text("Screenshots, recordings, and a replay buffer, all in one place.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("\(viewModel.availableCount) of \(viewModel.plannedCount) planned features available")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private var permissionCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Screen Recording access needed")
                        .font(.headline)
                    Text("macOS asks once before any app can capture the screen. Untitled only captures when you ask it to.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Grant Access…") {
                            viewModel.requestScreenRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Open System Settings") {
                            viewModel.openScreenRecordingSettings()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }
}

#Preview("Needs permission") {
    HomeView()
        .environment(AppDependencies.preview())
        .frame(width: 700, height: 520)
}

#Preview("Granted") {
    HomeView()
        .environment(AppDependencies.preview(screenRecording: .granted))
        .frame(width: 700, height: 520)
}
