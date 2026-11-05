import Foundation
import Security

/// Facts about how this copy of the app is signed.
nonisolated enum CodeSigningInfo {
    /// True when the app is signed with a developer team. Builds signed only "to run locally"
    /// get a new identity on every build, so macOS forgets privacy permissions after each one.
    static let hasTeamIdentifier: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any]
        else { return false }
        return dictionary[kSecCodeInfoTeamIdentifier as String] != nil
    }()
}
