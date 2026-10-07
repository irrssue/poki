import Foundation
import Security
import PokiCore

struct Person: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let username: String
    let name: String
    var friend: Friend { Friend(id: id, name: name, username: username) }
}
struct FriendRequest: Codable, Identifiable, Sendable {
    let id: UUID
    let incoming: Bool
    let person: Person
}
struct ReceivedPoke: Codable, Identifiable, Sendable {
    let id: UUID
    let message: String
    let unread: Bool
    let person: Person
}
struct SocialSnapshot: Codable, Sendable {
    let profile: Person?
    let friends: [Person]
    let requests: [FriendRequest]
    let pokes: [ReceivedPoke]
    // Optional so older databases without the safety migration still decode.
    let blocked: [Person]?
    let muted: [Person]?
}
struct SearchResult: Codable, Sendable {
    let person: Person
    let relationship: String
}
struct AccountSession: Codable, Sendable {
    let access_token: String
    let refresh_token: String
    let expires_at: Double?
}
struct ServiceFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// The publishable key identifies the project; it is not an admin credential.
struct AccountConfiguration: Sendable {
    let url: URL
    let key: String
    static var bundled: AccountConfiguration? {
        guard let path = Bundle.main.url(forResource: "AccountConfiguration", withExtension: "plist"),
              let data = try? Data(contentsOf: path),
              let values = try? PropertyListDecoder().decode([String: String].self, from: data),
              let rawURL = values["SUPABASE_URL"], let url = URL(string: rawURL), url.scheme == "https",
              let key = values["SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty else { return nil }
        return AccountConfiguration(url: url, key: key)
    }
}

actor AccountService {
    private let configuration: AccountConfiguration?
    private var session: AccountSession?
    private var refreshTask: Task<AccountSession, Error>?
    private var generation = UUID()
    init(configuration: AccountConfiguration? = .bundled) {
        self.configuration = configuration
        self.session = Self.loadSession()
    }
    var isSignedIn: Bool { session != nil }

    // Supabase creates the account on an Apple ID's first sign-in and reuses it afterwards.
    func signInWithApple(idToken: String, nonce: String) async throws {
        let value: AccountSession = try await request(path: "auth/v1/token?grant_type=id_token", body: ["provider": "apple", "id_token": idToken, "nonce": nonce], token: nil)
        try Self.saveSession(value)
        session = value
        generation = UUID()
    }
    func signOut() async {
        let oldToken = session?.access_token
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        Self.deleteSession()
        if let oldToken {
            let _: EmptyResponse? = try? await request(path: "auth/v1/logout?scope=local", body: [:], token: oldToken)
        }
    }
    func rpc<T: Decodable & Sendable>(_ name: String, body: [String: String] = [:], as: T.Type = T.self) async throws -> T {
        let token = try await accessToken()
        return try await request(path: "rest/v1/rpc/\(name)", body: body, token: token)
    }
    func respond(id: UUID, accept: Bool) async throws {
        let token = try await accessToken()
        let body = try JSONEncoder().encode(ResponseBody(request_id: id, accept: accept))
        let _: EmptyResponse = try await requestData(path: "rest/v1/rpc/poki_respond", body: body, token: token)
    }
    func report(_ report: ReportSubmission) async throws {
        let token = try await accessToken()
        let _: EmptyResponse = try await requestData(path: "rest/v1/rpc/poki_report", body: JSONEncoder().encode(report), token: token)
    }
    func markRead(ids: [UUID]) async throws {
        let token = try await accessToken()
        let body = try JSONEncoder().encode(["poke_ids": ids])
        let _: EmptyResponse = try await requestData(path: "rest/v1/rpc/poki_read", body: body, token: token)
    }
    private func accessToken() async throws -> String {
        guard let session else { throw ServiceFailure(message: "Sign in to continue.") }
        if let expires = session.expires_at, expires > Date().timeIntervalSince1970 + 60 { return session.access_token }
        if let refreshTask { return try await refreshTask.value.access_token }
        let currentGeneration = generation
        let task = Task<AccountSession, Error> {
            try await request(path: "auth/v1/token?grant_type=refresh_token", body: ["refresh_token": session.refresh_token], token: nil)
        }
        refreshTask = task
        do {
            let refreshed = try await task.value
            guard currentGeneration == generation else { throw CancellationError() }
            try Self.saveSession(refreshed)
            self.session = refreshed
            refreshTask = nil
            return refreshed.access_token
        } catch {
            if currentGeneration == generation { refreshTask = nil }
            throw error
        }
    }
    private func request<T: Decodable>(path: String, body: [String: String], token: String?) async throws -> T {
        try await requestData(path: path, body: JSONEncoder().encode(body), token: token)
    }
    private func requestData<T: Decodable>(path: String, body: Data, token: String?) async throws -> T {
        guard let configuration, let url = URL(string: path, relativeTo: configuration.url.appendingPathComponent("/")) else {
            throw ServiceFailure(message: "Accounts are not connected yet. Please try again after setup is complete.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(configuration.key, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ServiceFailure(message: "Could not reach Poki.") }
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(RemoteError.self, from: data)
            let message: String
            if failure?.code == "P0001", let safeMessage = failure?.message { message = safeMessage }
            else if response.statusCode == 429 { message = "Please wait a minute before trying again." }
            else if path.contains("grant_type=id_token") { message = "Could not sign in with Apple. Please try again." }
            else if response.statusCode == 401 { message = "Your session expired. Sign out and sign in again." }
            else { message = "Could not complete this action. Please try again." }
            throw ServiceFailure(message: message)
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private static var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pokiapp.account", kSecAttrAccount as String: "session"]
    }
    private static func loadSession() -> AccountSession? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AccountSession.self, from: data)
    }
    private static func saveSession(_ session: AccountSession) throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = keychainQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw ServiceFailure(message: "Could not securely save your sign-in.") }
        } else if status != errSecSuccess { throw ServiceFailure(message: "Could not securely save your sign-in.") }
    }
    private static func deleteSession() { SecItemDelete(keychainQuery as CFDictionary) }
}
struct EmptyResponse: Codable, Sendable {}
private struct ResponseBody: Encodable { let request_id: UUID; let accept: Bool }
// Nil fields are omitted, so the database defaults apply.
struct ReportSubmission: Encodable, Sendable { let person_id: UUID; let reason: String; let poke_id: UUID?; let details: String?; let also_block: Bool }
private struct RemoteError: Decodable { let code: String?; let message: String? }
