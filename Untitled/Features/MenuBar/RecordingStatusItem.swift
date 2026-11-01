import AppKit

/// A second menu bar item shown while recording: a red dot and the elapsed time, like 0:42.
/// Clicking it stops the recording. Before that, it counts down 3, 2, 1, and clicking cancels.
final class RecordingStatusItem: NSObject {
    var onClick: (() -> Void)?

    private var item: NSStatusItem?
    private var timer: Timer?

    /// Shows the item counting up from `since`. Calling it again just restarts the count.
    func showElapsed(since: Date) {
        let button = makeItem()
        button.image = Self.dot
        button.toolTip = String(localized: "Stop Recording")
        button.setAccessibilityLabel(String(localized: "Stop Recording"))
        setTitle(Self.elapsed(since: since))

        // Tick on each whole second of the recording, also while a menu is open.
        timer?.invalidate()
        let wait = 1 - Date.now.timeIntervalSince(since).truncatingRemainder(dividingBy: 1)
        let timer = Timer(fire: .now.addingTimeInterval(wait), interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setTitle(Self.elapsed(since: since))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Shows the seconds left before recording starts. Clicking cancels.
    func showCountdown(_ remaining: Int) {
        timer?.invalidate()
        timer = nil
        let button = makeItem()
        button.image = nil
        button.toolTip = String(localized: "Cancel Countdown")
        button.setAccessibilityLabel(String(localized: "Recording starts in \(remaining). Click to cancel."))
        setTitle(remaining.formatted())
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        if let item {
            NSStatusBar.system.removeStatusItem(item)
        }
        item = nil
    }

    private func makeItem() -> NSStatusBarButton {
        if let button = item?.button { return button }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        guard let button = item.button else { return NSStatusBarButton() }
        button.target = self
        button.action = #selector(clicked)
        button.imagePosition = .imageLeading
        return button
    }

    private func setTitle(_ title: String) {
        guard let button = item?.button else { return }
        // Fixed-width digits, so the item doesn't jiggle as the seconds change.
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
    }

    @objc private func clicked() {
        onClick?()
    }

    private static func elapsed(since: Date) -> String {
        Duration.seconds(max(0, Date.now.timeIntervalSince(since).rounded(.down)))
            .formatted(.time(pattern: .minuteSecond))
    }

    /// A small red dot, drawn in color rather than as a template so it stays red.
    private static let dot: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }()
}
