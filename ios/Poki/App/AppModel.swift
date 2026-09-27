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
    var friends: [Friend] = Friend.previews
    var drafts: [UUID: String] = [:]
    var sendingFriendIDs: Set<UUID> = []
    var favorite: FavoriteConfiguration?
    var feedback: SendFeedback?
    var isFavoriteEditorPresented = false

    private let pokeService: any PokeService
    private let favoriteStore: FavoriteStore

    init(
        pokeService: any PokeService = PreviewPokeService(),
        favoriteStore: FavoriteStore = FavoriteStore()
    ) {
        self.pokeService = pokeService
        self.favoriteStore = favoriteStore
        self.favorite = favoriteStore.load()
    }

    func updateDraft(_ value: String, for friend: Friend) {
        guard value.count <= MessageValidator.maximumLength,
              !value.contains(where: { $0.isNewline }) else { return }
        drafts[friend.id] = value
    }

    func send(to friend: Friend, message override: String? = nil) async {
        guard !sendingFriendIDs.contains(friend.id) else { return }

        let draft = override ?? drafts[friend.id, default: ""]
        let message = MessageValidator.resolvedMessage(from: draft)
        sendingFriendIDs.insert(friend.id)

        do {
            try await pokeService.sendPoke(to: friend.id, message: message)
            if override == nil { drafts[friend.id] = "" }
            feedback = SendFeedback(friendName: friend.name, succeeded: true)
        } catch {
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
        guard !normalized.isEmpty, MessageValidator.isValid(normalized) else { return }
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

