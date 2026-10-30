import SwiftUI

/// A large button for a quick action on the Home screen.
struct QuickActionTile: View {
    let action: QuickAction
    let isEnabled: Bool
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            VStack(spacing: 8) {
                Image(systemName: action.symbolName)
                    .font(.title2)
                    .imageScale(.large)
                    .frame(height: 28)
                Text(action.title)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(isEnabled ? action.title : String(localized: "\(action.title) is coming in a later update"))
    }
}

#Preview {
    QuickActionTile(action: QuickAction.all[0], isEnabled: false) {}
        .frame(width: 160)
        .padding()
}
