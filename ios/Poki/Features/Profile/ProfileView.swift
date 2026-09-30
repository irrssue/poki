import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model

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

                Section("Poki") {
                    Button("Add a friend", systemImage: "person.badge.plus") { model.isAddFriendPresented = true }
                    Button("Friend requests", systemImage: "person.2") { model.isNotificationsPresented = true }
                    Button("Configure favorite", systemImage: "star") {
                        model.isFavoriteEditorPresented = true
                    }
                }

                Section {
                    Text("Requests and pokes appear in the app’s notification inbox. Open Poki to check for new activity.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                }
            }
            .navigationTitle("Profile")
            
        }
    }
}

