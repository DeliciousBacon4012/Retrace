import AppKit

/// The elapsed time to show in the menu bar, capped for a rolling replay buffer.
nonisolated struct RecordingTimerReading: Equatable {
    let displayedSeconds: Int
    let reachedLimit: Bool
    let pulseIsBright: Bool
}

nonisolated enum RecordingTimerLogic {
    /// The dot blinks once a second while anything records: bright for the first half of each
    /// second, dim for the second. With Reduce Motion it stays bright.
    static func reading(since: Date, now: Date, maximumDuration: Int? = nil, blinks: Bool = true) -> RecordingTimerReading {
        let elapsed = max(0, now.timeIntervalSince(since))
        let limit = maximumDuration.flatMap { $0 > 0 ? Double($0) : nil }
        let displayed = Int(min(elapsed, limit ?? .greatestFiniteMagnitude).rounded(.down))
        let reachedLimit = limit.map { elapsed >= $0 } ?? false
        let halfSecondPhase = Int((elapsed * 2).rounded(.down))

        return RecordingTimerReading(
            displayedSeconds: displayed,
            reachedLimit: reachedLimit,
            pulseIsBright: !blinks || halfSecondPhase.isMultiple(of: 2)
        )
    }
}

/// Shows a red dot and elapsed time beside Retrace's menu bar icon.
/// Clicking stops a regular recording, cancels its countdown, or turns off the replay buffer.
final class RecordingStatusItem: NSObject {
    var onClick: (() -> Void)?

    private var item: NSStatusItem?
    private var timer: Timer?

    /// Shows elapsed time. When capped, the text stays at the buffer length and the dot pulses.
    func showElapsed(
        since: Date,
        maximumDuration: Int? = nil,
        toolTip: String,
        accessibilityLabel: String
    ) {
        let button = makeItem()
        button.toolTip = toolTip
        button.setAccessibilityLabel(accessibilityLabel)

        let interval: TimeInterval = 0.5
        let elapsed = max(0, Date.now.timeIntervalSince(since))
        let remainder = elapsed.truncatingRemainder(dividingBy: interval)
        let wait = interval - remainder
        let timer = Timer(fire: .now.addingTimeInterval(wait), interval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateElapsed(
                    since: since,
                    maximumDuration: maximumDuration,
                    accessibilityLabel: accessibilityLabel
                )
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer?.invalidate()
        self.timer = timer
        updateElapsed(since: since, maximumDuration: maximumDuration, accessibilityLabel: accessibilityLabel)
    }

    /// Shows the seconds left before a recording starts. Clicking cancels.
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

    private func updateElapsed(since: Date, maximumDuration: Int?, accessibilityLabel: String) {
        guard let button = item?.button else { return }
        let reading = RecordingTimerLogic.reading(
            since: since,
            now: .now,
            maximumDuration: maximumDuration,
            blinks: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let title = Self.formatted(seconds: reading.displayedSeconds)
        button.image = reading.pulseIsBright ? Self.dot : Self.dimDot
        button.setAccessibilityLabel("\(accessibilityLabel), \(title)")
        setTitle(title)
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

    private static func formatted(seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    private static func makeDot(alpha: CGFloat) -> NSImage? {
        let color = NSColor.systemRed.withAlphaComponent(alpha)
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }

    private static let dot = makeDot(alpha: 1)
    private static let dimDot = makeDot(alpha: 0.55)
}
