import Foundation
import OSLog
import Synchronization

/// Logs whenever the main thread stops answering long enough to drop frames. It's a setting in
/// Settings › Advanced, on by default in development builds. See the stalls in the Recent
/// Problems list, or with `log stream --predicate 'category == "hang"'`.
nonisolated enum HangDetector {
    private static let threshold: TimeInterval = 0.1
    private static let log = Logger(subsystem: Log.subsystem, category: "hang")
    private static let isRunning = Atomic<Bool>(false)

    /// Starts or stops watching. Calling it again with the same value does nothing.
    static func setEnabled(_ enabled: Bool) {
        if enabled {
            guard isRunning.compareExchange(expected: false, desired: true, ordering: .relaxed).exchanged else { return }
            let thread = Thread { watch() }
            thread.name = "HangDetector"
            thread.qualityOfService = .utility
            thread.start()
        } else {
            isRunning.store(false, ordering: .relaxed)
        }
    }

    private static func watch() {
        while isRunning.load(ordering: .relaxed) {
            let sent = ProcessInfo.processInfo.systemUptime
            let answered = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { answered.signal() }
            answered.wait()
            let delay = ProcessInfo.processInfo.systemUptime - sent
            if delay >= threshold {
                log.error("Main thread blocked for \(Int(delay * 1000), privacy: .public) ms")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
