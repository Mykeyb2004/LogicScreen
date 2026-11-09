import Foundation
import Security

/// Describes the running code, rather than another copy found by Launch Services.
public struct AppSigningInfo: Sendable {
    public let codeHash: String?
    public let isAdHoc: Bool?

    public static func current() -> AppSigningInfo {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else {
            return AppSigningInfo(codeHash: nil, isAdHoc: nil)
        }
        let hash = (values[kSecCodeInfoUnique as String] as? Data)?.map { String(format: "%02x", $0) }.joined()
        let flags = values[kSecCodeInfoFlags as String] as? NSNumber
        // CSCommon.h's kSecCodeSignatureAdhoc is not exposed to Swift.
        return AppSigningInfo(codeHash: hash, isAdHoc: flags.map { $0.uint32Value & 0x0002 != 0 })
    }
}
