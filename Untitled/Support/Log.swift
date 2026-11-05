import OSLog

/// Shared loggers, one category per area. View them in Console.app by filtering on the subsystem.
nonisolated enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "retrace"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let capture = Logger(subsystem: subsystem, category: "capture")
}
