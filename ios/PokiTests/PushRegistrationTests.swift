import XCTest
@testable import Poki

@MainActor
final class PushRegistrationTests: XCTestCase {
    private let alice = UUID()
    private let token = String(repeating: "ab", count: 32)

    func testRegistrationPersistsBeforeUploadAndReusesDeviceID() async {
        let api = RecordingPushAPI()
        let storage = MemoryPushStorage()
        let registration = PushRegistration(api: api, storage: storage)
        registration.activate(owner: alice)
        api.failNext = true
        registration.upload(token: token, environment: "sandbox")
        await registration.waitForUploads()
        XCTAssertNotNil(storage.record, "a lost response may still have registered remotely")
        XCTAssertFalse(registration.registered)
        registration.upload(token: token, environment: "sandbox")
        await registration.waitForUploads()
        XCTAssertTrue(registration.registered)
        XCTAssertEqual(Set(api.registered.map(\.id)), [storage.record!.id])
    }

    func testPreviousAccountRecordIsReplaced() async {
        let api = RecordingPushAPI()
        let storage = MemoryPushStorage()
        let stale = PushRegistrationRecord(id: UUID(), owner: UUID())
        storage.record = stale
        let registration = PushRegistration(api: api, storage: storage)
        registration.activate(owner: alice)
        registration.upload(token: token, environment: "sandbox")
        await registration.waitForUploads()
        XCTAssertTrue(registration.registered)
        XCTAssertEqual(storage.record?.owner, alice)
        XCTAssertNotEqual(storage.record?.id, stale.id)
    }

    func testSignOutUnregistersAndBlocksLateUploads() async throws {
        let api = RecordingPushAPI()
        let storage = MemoryPushStorage()
        let registration = PushRegistration(api: api, storage: storage)
        registration.activate(owner: alice)
        registration.upload(token: token, environment: "sandbox")
        await registration.waitForUploads()
        let id = storage.record!.id
        try await registration.stop()
        XCTAssertEqual(api.unregistered, [id])
        XCTAssertNil(storage.record)
        registration.upload(token: token, environment: "sandbox")
        await registration.waitForUploads()
        XCTAssertEqual(api.registered.count, 1, "uploads need a new owner after sign-out")
    }

    func testFailedUnregisterKeepsRecordForRetry() async {
        let api = RecordingPushAPI()
        let storage = MemoryPushStorage()
        storage.record = PushRegistrationRecord(id: UUID(), owner: alice)
        let registration = PushRegistration(api: api, storage: storage)
        api.failNext = true
        do { try await registration.stop(); XCTFail("sign-out must wait for server removal") } catch {}
        XCTAssertNotNil(storage.record)
        XCTAssertNotNil(registration.error)
    }

    func testSameTokenRegistersAgainForNewOwner() async {
        let api = RecordingPushAPI()
        let storage = MemoryPushStorage()
        let registration = PushRegistration(api: api, storage: storage)
        registration.activate(owner: alice)
        registration.upload(token: token, environment: "sandbox")
        await registration.waitForUploads()
        let firstID = storage.record!.id
        let nextOwner = UUID()
        registration.activate(owner: nextOwner)
        XCTAssertFalse(registration.registered)
        registration.upload(token: token, environment: "sandbox")
        await registration.waitForUploads()
        XCTAssertEqual(api.registered.count, 2)
        XCTAssertEqual(storage.record?.owner, nextOwner)
        XCTAssertNotEqual(storage.record?.id, firstID)
    }

    func testCacheIncludesEnvironmentAndRotatedToken() async {
        let api = RecordingPushAPI()
        let registration = PushRegistration(api: api, storage: MemoryPushStorage())
        registration.activate(owner: alice)
        for environment in ["sandbox", "sandbox", "production"] {
            registration.upload(token: token, environment: environment)
            await registration.waitForUploads()
        }
        XCTAssertEqual(api.registered.count, 2)
        registration.upload(token: String(repeating: "cd", count: 32), environment: "production")
        await registration.waitForUploads()
        XCTAssertEqual(api.registered.count, 3)
    }

    func testSignOutWaitsForInFlightRegistrationBeforeRemoval() async throws {
        let api = HeldPushAPI()
        let storage = MemoryPushStorage()
        let registration = PushRegistration(api: api, storage: storage)
        registration.activate(owner: alice)
        registration.upload(token: token, environment: "sandbox")
        await api.waitUntilStarted()
        let stop = Task { try await registration.stop() }
        // Let stop suspend on the in-flight request, then deliver a late token.
        await Task.yield()
        registration.upload(token: String(repeating: "cd", count: 32), environment: "sandbox")
        XCTAssertEqual(api.events, ["register"])
        api.finish()
        try await stop.value
        await registration.waitForUploads()
        XCTAssertEqual(api.events, ["register", "registered", "unregister"])
        XCTAssertNil(storage.record)
        XCTAssertFalse(registration.registered)
    }

    func testOldUploadCannotMarkNewOwnerRegistered() async {
        let api = HeldPushAPI()
        let registration = PushRegistration(api: api, storage: MemoryPushStorage())
        registration.activate(owner: alice)
        registration.upload(token: token, environment: "sandbox")
        await api.waitUntilStarted()
        registration.activate(owner: UUID())
        api.finish()
        await registration.waitForUploads()
        XCTAssertFalse(registration.registered)
    }

    func testDeletedAccountSkipsServerRemoval() async throws {
        let api = RecordingPushAPI()
        let storage = MemoryPushStorage()
        storage.record = PushRegistrationRecord(id: UUID(), owner: alice)
        try await PushRegistration(api: api, storage: storage).stop(accountDeleted: true)
        XCTAssertTrue(api.unregistered.isEmpty)
        XCTAssertNil(storage.record)
    }
}

@MainActor
final class MemoryPushStorage: PushRegistrationStorage {
    var record: PushRegistrationRecord?
    func load() throws -> PushRegistrationRecord? { record }
    func save(_ record: PushRegistrationRecord?) throws { self.record = record }
}

@MainActor
private final class RecordingPushAPI: PushRegistrationAPI {
    var registered: [(id: UUID, token: String)] = []
    var unregistered: [UUID] = []
    var failNext = false

    func registerPush(id: UUID, token: String, environment: String) async throws {
        registered.append((id, token))
        if failNext { failNext = false; throw URLError(.timedOut) }
    }
    func unregisterPush(id: UUID) async throws {
        if failNext { failNext = false; throw URLError(.timedOut) }
        unregistered.append(id)
    }
}

@MainActor
private final class HeldPushAPI: PushRegistrationAPI {
    var events: [String] = []
    private var continuation: CheckedContinuation<Void, Never>?
    func registerPush(id: UUID, token: String, environment: String) async throws {
        events.append("register")
        await withCheckedContinuation { continuation = $0 }
        events.append("registered")
    }
    func unregisterPush(id: UUID) async throws { events.append("unregister") }
    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }
    func finish() { continuation?.resume(); continuation = nil }
}
