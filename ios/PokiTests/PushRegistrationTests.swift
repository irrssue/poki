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

private final class RecordingPushAPI: PushRegistrationAPI, @unchecked Sendable {
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
