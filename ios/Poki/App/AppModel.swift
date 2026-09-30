import Foundation
import Observation
import PokiCore

@MainActor
@Observable
final class AppModel {
    enum Destination {
        case home
        case profile
    }

    var destination: Destination = .home
    var friends: [Friend] = []
    var drafts: [UUID: String] = [:]
    var sendingFriendIDs: Set<UUID> = []
    var favorite: FavoriteConfiguration?
    var feedback: SendFeedback?
    var isFavoriteEditorPresented = false
    var isAddFriendPresented = false
    var isNotificationsPresented = false
    var profile: Person?
    var requests: [FriendRequest] = []
    var receivedPokes: [ReceivedPoke] = []
    var signedIn = false
    var starting = true
    var syncError: String?
    let accountService: AccountService
    private var sessionGeneration = UUID()
    private var refreshing = false
    var notificationCount: Int { requests.filter(\.incoming).count + receivedPokes.filter(\.unread).count }

    private let pokeService: (any PokeService)?
    private let favoriteStore: FavoriteStore

    init(
        pokeService: (any PokeService)? = nil,
        accountService: AccountService = AccountService(),
        favoriteStore: FavoriteStore = FavoriteStore()
    ) {
        self.pokeService = pokeService
        self.accountService = accountService
        self.favoriteStore = favoriteStore
        self.favorite = nil
    }

    func start() async {
        signedIn = await accountService.isSignedIn
        if signedIn { await refresh() }
        starting = false
    }

    func verify(email: String, code: String) async throws {
        try await accountService.verify(email: email, code: code)
        signedIn = true
        try await loadSnapshot()
    }

    func createProfile(username: String, name: String) async throws {
        let _: EmptyResponse = try await accountService.rpc("poki_create_profile", body: ["username": username, "display_name": name])
        try await loadSnapshot()
    }

    func search(username: String) async throws -> SearchResult? {
        try await accountService.rpc("poki_search", body: ["username": username])
    }

    func requestFriend(_ id: UUID) async throws {
        let _: EmptyResponse = try await accountService.rpc("poki_request", body: ["recipient_id": id.uuidString])
        await refresh()
    }

    func respond(_ id: UUID, accept: Bool) async throws {
        try await accountService.respond(id: id, accept: accept)
        await refresh()
    }

    func refresh() async {
        guard signedIn, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do { try await loadSnapshot(); syncError = nil }
        catch { syncError = error.localizedDescription }
    }

    private func loadSnapshot() async throws {
        let generation = sessionGeneration
        let snapshot: SocialSnapshot = try await accountService.rpc("poki_snapshot")
        guard generation == sessionGeneration else { return }
        profile = snapshot.profile
        friends = snapshot.friends.map(\.friend)
        requests = snapshot.requests
        receivedPokes = snapshot.pokes
        if let saved = favoriteStore.load(), friends.contains(where: { $0.id == saved.friendID }) { favorite = saved }
        else { favorite = nil }
    }

    func markPokesRead() async {
        let ids = receivedPokes.filter(\.unread).map(\.id)
        guard !ids.isEmpty else { return }
        do { try await accountService.markRead(ids: ids); await refresh() }
        catch { syncError = error.localizedDescription }
    }

    func signOut() async {
        sessionGeneration = UUID()
        signedIn = false; profile = nil; friends = []; requests = []; receivedPokes = []
        drafts = [:]; sendingFriendIDs = []; favorite = nil; favoriteStore.save(nil)
        feedback = nil; syncError = nil; destination = .home
        isAddFriendPresented = false; isNotificationsPresented = false; isFavoriteEditorPresented = false
        await accountService.signOut()
    }

    func updateDraft(_ value: String, for friend: Friend) {
        guard value.count <= MessageValidator.maximumLength,
              !value.contains(where: { $0.isNewline }) else { return }
        drafts[friend.id] = value
    }

    func send(to friend: Friend, message override: String? = nil) async {
        guard friends.contains(where: { $0.id == friend.id }),
              !sendingFriendIDs.contains(friend.id) else { return }

        let draft = override ?? drafts[friend.id, default: ""]
        let message = MessageValidator.resolvedMessage(from: draft)
        guard MessageValidator.isValid(message) else { return }
        let generation = sessionGeneration
        sendingFriendIDs.insert(friend.id)

        do {
            if let pokeService {
                try await pokeService.sendPoke(to: friend.id, message: message)
            } else {
                let _: EmptyResponse = try await accountService.rpc("poki_send", body: ["recipient_id": friend.id.uuidString, "message": message, "poke_id": UUID().uuidString])
            }
            guard generation == sessionGeneration else { return }
            if override == nil && drafts[friend.id, default: ""] == draft { drafts[friend.id] = "" }
            feedback = SendFeedback(friendName: friend.name, succeeded: true)
        } catch {
            guard generation == sessionGeneration else { return }
            syncError = error.localizedDescription
            feedback = SendFeedback(friendName: friend.name, succeeded: false)
        }

        sendingFriendIDs.remove(friend.id)
    }

    func sendFavorite() async {
        guard let favorite,
              let friend = friends.first(where: { $0.id == favorite.friendID }) else {
            isFavoriteEditorPresented = true
            return
        }
        await send(to: friend, message: favorite.message)
    }

    func saveFavorite(friendID: UUID, message: String) {
        let normalized = MessageValidator.normalized(message)
        guard friends.contains(where: { $0.id == friendID }), !normalized.isEmpty, MessageValidator.isValid(normalized) else { return }
        favorite = FavoriteConfiguration(friendID: friendID, message: normalized)
        favoriteStore.save(favorite)
        isFavoriteEditorPresented = false
    }

    func clearFavorite() {
        favorite = nil
        favoriteStore.save(nil)
    }
}

struct SendFeedback: Equatable {
    var friendName: String
    var succeeded: Bool
}

