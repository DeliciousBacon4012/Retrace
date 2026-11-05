import Observation
import OSLog

/// Keeps the system-wide shortcuts in step with Settings, and reports any that
/// macOS refused because another app already uses them.
@Observable
final class GlobalShortcuts {
    /// Why a shortcut couldn't be registered, by `QuickAction` identifier.
    private(set) var problems: [String: String] = [:]

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let center = HotKeyCenter()
    @ObservationIgnored private let perform: (String) -> Void
    @ObservationIgnored private var isPaused = false

    init(settings: SettingsStore, perform: @escaping (String) -> Void) {
        self.settings = settings
        self.perform = perform
    }

    func start() {
        follow()
    }

    /// Turns every shortcut off while a new one is being typed, so pressing an
    /// existing combination records it instead of running it.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        apply(settings.shortcuts)
    }

    private func follow() {
        let shortcuts = withObservationTracking {
            settings.shortcuts
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.follow()
            }
        }
        apply(shortcuts)
    }

    private func apply(_ shortcuts: [String: Shortcut]) {
        center.unregisterAll()
        guard !isPaused else { return }
        var problems: [String: String] = [:]
        for (actionID, shortcut) in shortcuts {
            do {
                _ = try center.register(shortcut) { [weak self] in
                    self?.perform(actionID)
                }
            } catch {
                problems[actionID] = error.localizedDescription
                Log.app.error("Shortcut \(shortcut.displayString, privacy: .public) for \(actionID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        self.problems = problems
    }
}
