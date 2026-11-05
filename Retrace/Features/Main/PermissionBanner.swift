import AppKit
import SwiftUI

/// Asks for Screen Recording access above Recents, until it's granted. It stays to one
/// compact row so the captures keep the room; the details are behind the info button.
/// It's a notice in the content, so it uses a plain fill rather than glass.
struct PermissionBanner: View {
    let model: ScreenRecordingAccessModel
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Design.spacingM) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Screen Recording Access Needed")
                        .font(.headline)
                    Text("Turn on Retrace in Privacy & Security › Screen & System Audio Recording.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Allow Access…") { model.requestScreenRecording() }
                    .buttonStyle(.borderedProminent)
                Button {
                    Task { await model.checkAgain() }
                } label: {
                    if model.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check Again")
                    }
                }
                .disabled(model.isChecking)
                Button("More", systemImage: "info.circle") { showsDetails.toggle() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("More about Screen Recording access")
                    .popover(isPresented: $showsDetails, arrowEdge: .bottom) { details }
            }

            if model.checkFoundNoAccess {
                HStack(spacing: 6) {
                    Text("Already turned it on? Some Macs only apply it after a restart.")
                        .foregroundStyle(.secondary)
                    Button("Restart Retrace") { model.restart() }
                        .buttonStyle(.link)
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(.fill.quaternary, in: model.checkFoundNoAccess ? AnyShape(.rect(cornerRadius: Design.radiusL)) : AnyShape(.capsule))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If macOS offers to quit and reopen, Later is fine: Retrace notices on its own.")
            if !CodeSigningInfo.hasTeamIdentifier {
                Text("This build is signed only to run locally, so macOS forgets the permission each time it's rebuilt. In Xcode, choose a Team under Signing & Capabilities.")
                    .foregroundStyle(.secondary)
            }
            Button("Open System Settings") { model.openScreenRecordingSettings() }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300, alignment: .leading)
        .padding()
    }
}
