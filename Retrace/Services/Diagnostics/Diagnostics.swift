import AppKit
import OSLog

/// What Settings › Advanced shows about how Retrace is running: its own log messages from
/// this launch, a summary to paste into a bug report, and how much space its data takes.
/// Everything here reads; nothing leaves the Mac unless the person copies or saves it.
nonisolated enum Diagnostics {
    struct Problem: Identifiable, Sendable {
        /// Stays the same across reads, so the list doesn't reshuffle when it refreshes.
        var id: String { "\(date.timeIntervalSinceReferenceDate)|\(category)|\(message)" }
        let date: Date
        let category: String
        let message: String
        let isFault: Bool
    }

    /// Errors and faults Retrace logged since it launched, newest first. Reads the log store,
    /// so call it from a background task.
    static func recentProblems(limit: Int = 100) -> [Problem] {
        entries(minimumLevel: .error).suffix(limit).reversed().map { entry in
            Problem(
                date: entry.date,
                category: entry.category,
                message: entry.composedMessage,
                isFault: entry.level == .fault
            )
        }
    }

    /// Every message Retrace logged since it launched, one per line, oldest first.
    static func logText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries(minimumLevel: .debug).map { entry in
            "\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.levelName): \(entry.composedMessage)"
        }.joined(separator: "\n")
    }

    /// The size of everything in a folder, in bytes. Walks the folder, so call it from a
    /// background task.
    static func size(of folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Application Support/<bundle ID>, where history, the index, and originals live.
    static var dataFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: Bundle.main.bundleIdentifier ?? "Retrace", directoryHint: .isDirectory)
    }

    /// The Mac, the app, and its displays, in a few lines for a bug report. No file names or
    /// clipboard contents.
    static func systemSummary() -> [String] {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let process = ProcessInfo.processInfo
        let memory = ByteCountFormatter.string(fromByteCount: Int64(process.physicalMemory), countStyle: .memory)
        var lines = [
            "Retrace \(version) (\(build)), \(bundle.bundleIdentifier ?? "?")",
            "macOS \(process.operatingSystemVersionString)",
            "Mac \(sysctl("hw.model") ?? "?"), \(sysctl("machdep.cpu.brand_string") ?? "?"), \(memory) memory, \(process.activeProcessorCount) cores",
            "Thermal state \(thermalName(process.thermalState))\(process.isLowPowerModeEnabled ? ", Low Power Mode" : "")",
        ]
        #if DEBUG
        lines[0] += ", development build"
        #endif
        return lines
    }

    @MainActor
    static func displaySummary() -> [String] {
        NSScreen.screens.enumerated().map { index, screen in
            let size = screen.frame.size
            let scale = screen.backingScaleFactor
            let hz = screen.maximumFramesPerSecond
            return "Display \(index + 1): \(screen.localizedName), \(Int(size.width))×\(Int(size.height)) points at \(Int(scale))×, \(hz) Hz"
        }
    }

    // MARK: Reading the log

    private struct Entry {
        let date: Date
        let category: String
        let level: OSLogEntryLog.Level
        let composedMessage: String

        var levelName: String {
            switch level {
            case .debug: "debug"
            case .info: "info"
            case .notice: "notice"
            case .error: "error"
            case .fault: "fault"
            default: "log"
            }
        }
    }

    private static func entries(minimumLevel: OSLogEntryLog.Level) -> [Entry] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
            return try store.getEntries(matching: predicate).compactMap { entry in
                guard let log = entry as? OSLogEntryLog, log.level.rawValue >= minimumLevel.rawValue else { return nil }
                return Entry(date: log.date, category: log.category, level: log.level, composedMessage: log.composedMessage)
            }
        } catch {
            return []
        }
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
