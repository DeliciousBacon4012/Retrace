import Foundation

extension Bundle {
    /// The version shown to people, such as "0.1.0 (1)".
    nonisolated var displayVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }
}
