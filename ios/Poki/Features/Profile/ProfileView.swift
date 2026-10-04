
import SwiftUI
import PokiCore

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingAction: PersonAction?
    @State private var isDeletePresented = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 52))
                        VStack(alignment: .leading) {
                            Text(model.profile?.name ?? "Your profile")
                                .font(.headline)
                            Text("@\(model.profile?.username ?? "")")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if let error { Text(error).foregroundStyle(.red) }

                Section("Poki") {
                    Button("Add a friend", systemImage: "person.badge.plus") { model.isAddFriendPresented = true }
                    Button("Friend requests", systemImage: "person.2") { model.isNotificationsPresented = true }
                    Button("Configure favorite", systemImage: "star") {
                        model.isFavoriteEditorPresented = true
                    }
                }

                if !model.friends.isEmpty {
                    Section("Friends") {
                        ForEach(model.friends) { friend in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(friend.name)
                                    Text("@\(friend.username)").font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    if model.muted.contains(where: { $0.id == friend.id }) {
                                        Button("Unmute", systemImage: "bell") { perform { try await model.unmute(friend.id) } }
                                    } else {
                                        Button("Mute", systemImage: "bell.slash") { perform { try await model.mute(friend.id) } }
                                    }
                                    Button("Remove friend", systemImage: "person.badge.minus") { pendingAction = .remove(friend) }
                                    Button("Block", systemImage: "hand.raised", role: .destructive) { pendingAction = .block(friend) }
                                } label: {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Options for \(friend.name)")
                            }
                        }
                    }
                }

                if !model.muted.isEmpty {
                    Section {
                        ForEach(model.muted) { person in
                            HStack {
                                Text("@\(person.username)")
                                Spacer()
                                Button("Unmute") { perform { try await model.unmute(person.id) } }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Unmute \(person.name)")
                            }
                        }
                    } header: {
                        Text("Muted")
                    } footer: {
                        Text("Muted people’s pokes are hidden from your inbox and badge. Unmuting shows their recent pokes again. You can still poke each other.")
                    }
                }

                if !model.blocked.isEmpty {
                    Section("Blocked") {
                        ForEach(model.blocked) { person in
                            HStack {
                                Text("@\(person.username)")
                                Spacer()
                                Button("Unblock") { perform { try await model.unblock(person.id) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section {
                    Text("Requests and pokes appear in the app’s notification inbox. Open Poki to check for new activity.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                    Button("Delete account", role: .destructive) { isDeletePresented = true }
                }
            }
            .disabled(busy)
            .navigationTitle("Profile")
            .confirmationDialog(pendingAction?.title ?? "", isPresented: Binding(
                get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
            ), titleVisibility: .visible, presenting: pendingAction) { action in
                Button(action.confirm, role: .destructive) {
                    switch action {
                    case .remove(let friend): perform { try await model.removeFriend(friend.id) }
                    case .block(let friend): perform { try await model.block(friend.id) }
                    }
                }
            } message: { action in
                Text(action.message)
            }
            .confirmationDialog("Delete your account?", isPresented: $isDeletePresented, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { perform { try await model.deleteAccount() } }
            } message: {
                Text("Your profile, friends, requests, and pokes are permanently deleted. This cannot be undone.")
            }
        }
    }

    private func perform(_ work: @escaping @MainActor () async throws -> Void) {
        busy = true; error = nil
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

private enum PersonAction {
    case remove(Friend)
    case block(Friend)

    var title: String {
        switch self {
        case .remove(let friend): "Remove \(friend.name)?"
        case .block(let friend): "Block \(friend.name)?"
        }
    }
    var confirm: String {
        switch self {
        case .remove: "Remove friend"
        case .block: "Block"
        }
    }
    var message: String {
        switch self {
        case .remove: "You’ll stop being able to poke each other. Either of you can send a new request later."
        case .block: "They’re removed from your friends, can’t find you by username, and can’t send you requests."
        }
    }
}
