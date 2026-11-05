#if DEBUG
import Foundation
import OSLog

/// Logs whenever the main thread stops answering long enough to drop frames, in development
/// builds only. See them with: `log stream --predicate 'category == "hang"'`.
nonisolated enum HangDetector {
    private static let threshold: TimeInterval = 0.1
    private static let log = Logger(subsystem: Log.subsystem, category: "hang")

    static func start() {
        let thread = Thread {
            while true {
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
        thread.name = "HangDetector"
        thread.qualityOfService = .utility
        thread.start()
    }
}
#endif
