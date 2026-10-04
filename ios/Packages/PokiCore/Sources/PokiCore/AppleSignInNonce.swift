import CryptoKit
import Foundation
import Security

/// A single-use Sign in with Apple nonce. Apple receives `hashed` and embeds it in the
/// identity token; Supabase receives `raw` and rejects tokens whose claim does not match.
public struct AppleSignInNonce: Sendable {
    public let raw: String
    public var hashed: String { Self.sha256(raw) }

    public init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Secure random generation failed")
        raw = Self.hex(bytes)
    }

    public init(raw: String) { self.raw = raw }

    static func sha256(_ value: String) -> String { hex(SHA256.hash(data: Data(value.utf8))) }
    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
