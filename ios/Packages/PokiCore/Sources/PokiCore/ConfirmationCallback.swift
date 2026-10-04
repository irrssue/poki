import Foundation

/// Parses only the app's email-confirmation callback. Never log callback URLs.
public struct ConfirmationCallback: Sendable {
    public static let redirectURL = "com.pokiapp.poki://auth/confirm"
    public let refreshToken: String

    public enum Failure: Error { case invalid, expired }

    public init(url: URL) throws {
        guard url.scheme?.lowercased() == "com.pokiapp.poki",
              url.host == "auth", url.path == "/confirm",
              url.user == nil, url.password == nil, url.port == nil,
              let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment else {
            throw Failure.invalid
        }
        var components = URLComponents()
        components.percentEncodedQuery = fragment
        let items = components.queryItems ?? []
        guard !items.contains(where: { $0.name == "error" || $0.name == "error_code" }) else {
            throw Failure.expired
        }
        let tokens = items.filter { $0.name == "refresh_token" }
        guard tokens.count == 1, let token = tokens[0].value, !token.isEmpty,
              items.contains(where: { $0.name == "type" && $0.value == "signup" }) else {
            throw Failure.invalid
        }
        refreshToken = token
    }
}
