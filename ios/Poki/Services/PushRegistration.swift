import Foundation
import Observation
import Security

protocol PushRegistrationAPI: Sendable {
    func registerPush(id: UUID, token: String, environment: String) async throws
    func unregisterPush(id: UUID) async throws
}
extension AccountService: PushRegistrationAPI {
    func registerPush(id: UUID, token: String, environment: String) async throws {
        let _: EmptyResponse = try await rpc("poki_register_device", body: ["device_id": id.uuidString, "device_token": token, "apns_environment": environment])
    }
    func unregisterPush(id: UUID) async throws {
        let _: EmptyResponse = try await rpc("poki_unregister_device", body: ["device_id": id.uuidString])
    }
}

struct PushRegistrationRecord: Codable, Equatable {
    let id: UUID
    let owner: UUID
}
@MainActor protocol PushRegistrationStorage {
    func load() throws -> PushRegistrationRecord?
    func save(_ record: PushRegistrationRecord?) throws
}

@MainActor struct KeychainPushRegistrationStorage: PushRegistrationStorage {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pokiapp.push", kSecAttrAccount as String: "registration"]
    }
    func load() throws -> PushRegistrationRecord? {
        var query = query
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ServiceFailure(message: "Could not read notification settings.") }
        return try JSONDecoder().decode(PushRegistrationRecord.self, from: data)
    }
    func save(_ record: PushRegistrationRecord?) throws {
        if let record {
            let data = try JSONEncoder().encode(record)
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecSuccess { return }
            guard status == errSecItemNotFound else { throw ServiceFailure(message: "Could not save notification settings.") }
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ServiceFailure(message: "Could not save notification settings.") }
        } else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ServiceFailure(message: "Could not clear notification settings.") }
        }
    }
}

/// Serializes registration and removal so a late upload cannot undo sign-out.
@MainActor @Observable final class PushRegistration {
    private let api: any PushRegistrationAPI
    private let storage: any PushRegistrationStorage
    private var queue: Task<Void, Never>?
    private var suspended = false
    private var owner: UUID?
    private var uploadedToken: String?
    private var uploadedAt: Date?
    var error: String?
    private(set) var registered = false

    init(api: any PushRegistrationAPI, storage: any PushRegistrationStorage = KeychainPushRegistrationStorage()) {
        self.api = api; self.storage = storage
    }
    func activate(owner: UUID) {
        guard !suspended else { return }
        self.owner = owner
    }
    func upload(token: String, environment: String) {
        guard let owner, !suspended else { return }
        let previous = queue
        queue = Task {
            await previous?.value
            guard !suspended, self.owner == owner else { return }
            if uploadedToken == token, let uploadedAt, Date().timeIntervalSince(uploadedAt) < 86400 { return }
            do {
                // Keychain outlives reinstalls; the server moves this token from a previous owner.
                let saved = try storage.load()
                let record = saved?.owner == owner ? saved! : PushRegistrationRecord(id: UUID(), owner: owner)
                // Persist before uploading: a lost response can still mean server success.
                try storage.save(record)
                try await api.registerPush(id: record.id, token: token, environment: environment)
                uploadedToken = token; uploadedAt = Date(); registered = true; error = nil
            } catch { self.error = "Could not connect notifications. Try again when Poki is available." }
        }
    }
    func stop(accountDeleted: Bool = false) async throws {
        suspended = true
        await queue?.value
        do {
            if let saved = try storage.load(), !accountDeleted {
                try await api.unregisterPush(id: saved.id)
            }
            try storage.save(nil)
            owner = nil; uploadedToken = nil; uploadedAt = nil; registered = false; error = nil
            suspended = false
        } catch {
            suspended = false
            self.error = "Could not disconnect notifications. Reconnect and try signing out again."
            throw error
        }
    }
    func waitForUploads() async { await queue?.value }
}
