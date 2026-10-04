import PokiCore
import XCTest
@testable import Poki

@MainActor
final class AppModelTests: XCTestCase {
    private func model(service: any PokeService = PreviewPokeService()) -> AppModel {
        let defaults = UserDefaults(suiteName: "PokiTests.\(UUID())")!
        let model = AppModel(pokeService: service, favoriteStore: FavoriteStore(defaults: defaults))
        model.friends = Friend.previews
        return model
    }

    func testSuccessfulSendClearsDraft() async {
        let model = model()
        let friend = model.friends[0]
        model.updateDraft("Miss you", for: friend)
        await model.send(to: friend)
        XCTAssertEqual(model.drafts[friend.id], "")
        XCTAssertEqual(model.feedback, SendFeedback(friendName: friend.name, succeeded: true))
    }

    func testInvalidDraftIsNotStored() {
        let model = model()
        let friend = model.friends[0]
        model.updateDraft(String(repeating: "x", count: 31), for: friend)
        XCTAssertNil(model.drafts[friend.id])
    }

    func testUnacceptedFriendCannotBeSentAPoke() async {
        let service = HeldPokeService()
        let model = model(service: service)
        await model.send(to: Friend(name: "Stranger", username: "stranger"))
        let calls = await service.calls
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.feedback)
    }

    func testEditingDuringSendPreservesNewDraftAndPreventsDuplicateSend() async {
        let service = HeldPokeService()
        let model = model(service: service)
        let friend = model.friends[0]
        model.updateDraft("First", for: friend)
        let task = Task { await model.send(to: friend) }
        await service.waitUntilStarted()
        model.updateDraft("Second", for: friend)
        await model.send(to: friend)
        let calls = await service.calls
        XCTAssertEqual(calls, 1)
        await service.finish()
        await task.value
        XCTAssertEqual(model.drafts[friend.id], "Second")
    }

    func testFailedSendPreservesDraft() async {
        let model = model(service: FailingPokeService())
        let friend = model.friends[0]
        model.updateDraft("Miss you", for: friend)
        await model.send(to: friend)
        XCTAssertEqual(model.drafts[friend.id], "Miss you")
        XCTAssertEqual(model.feedback?.succeeded, false)
    }

    func testOlderSnapshotDecodesWithoutMuteState() throws {
        let data = Data(#"{"profile":null,"friends":[],"requests":[],"pokes":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(SocialSnapshot.self, from: data)
        XCTAssertNil(snapshot.muted)
    }

    func testSignOutClearsMuteState() async {
        let model = model()
        model.muted = [Person(id: UUID(), username: "sam", name: "Sam")]
        await model.signOut()
        XCTAssertTrue(model.muted.isEmpty)
    }

    func testSignOutDiscardsInFlightAccountFeedback() async {
        let service = HeldPokeService()
        let model = model(service: service)
        let friend = model.friends[0]
        let task = Task { await model.send(to: friend) }
        await service.waitUntilStarted()
        await model.signOut()
        await service.finish()
        await task.value
        XCTAssertTrue(model.friends.isEmpty)
        XCTAssertTrue(model.drafts.isEmpty)
        XCTAssertNil(model.feedback)
    }
}

private actor HeldPokeService: PokeService {
    var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func sendPoke(to friendID: UUID, message: String) async throws {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }
    func finish() { continuation?.resume(); continuation = nil }
}
private struct FailingPokeService: PokeService {
    func sendPoke(to friendID: UUID, message: String) async throws { throw URLError(.notConnectedToInternet) }
}
