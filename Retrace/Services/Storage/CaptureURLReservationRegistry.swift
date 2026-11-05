import Foundation

/// Reserves output names before asynchronous writers create their files.
nonisolated final class CaptureURLReservationRegistry: @unchecked Sendable {
    static let shared = CaptureURLReservationRegistry()

    private let lock = NSLock()
    private var reservations: [String: Date] = [:]
    private let reservationLifetime: TimeInterval = 24 * 60 * 60

    private init() {}

    func uniqueURL(in folder: URL, baseName: String, fileExtension: String) -> URL {
        lock.lock()
        defer { lock.unlock() }

        let now = Date.now
        reservations = reservations.filter { path, expiry in
            expiry > now && !FileManager.default.fileExists(atPath: path)
        }

        var candidate = folder.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var counter = 2
        while isUnavailable(candidate) {
            candidate = folder.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }

        reservations[candidate.path(percentEncoded: false)] = now.addingTimeInterval(reservationLifetime)
        return candidate
    }

    private func isUnavailable(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path) || reservations[path] != nil
    }
}
