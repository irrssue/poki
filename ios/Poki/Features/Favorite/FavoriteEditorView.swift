import PokiCore
import SwiftUI

struct FavoriteEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFriendID: UUID?
    @State private var message = "Thinking of you"

    private var canSave: Bool {
        selectedFriendID != nil &&
        !MessageValidator.normalized(message).isEmpty &&
        MessageValidator.isValid(message)
    }

    var body: some View {
        let messageBinding = Binding(
            get: { message },
            set: { newValue in
                guard MessageValidator.isValid(newValue) else { return }
                message = newValue
            }
        )

        NavigationStack {
            Form {
                Section("Favorite person") {
                    Picker("Friend", selection: $selectedFriendID) {
                        Text("Choose a friend").tag(UUID?.none)
                        ForEach(model.friends) { friend in
                            Text(friend.name).tag(Optional(friend.id))
                        }
                    }
                }

                Section("One-tap message") {
                    TextField("Message", text: messageBinding)
                    Text("\(MessageValidator.remainingCharacters(for: message)) characters remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.favorite != nil {
                    Button("Clear favorite", role: .destructive) {
                        model.clearFavorite()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Favorite poke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let selectedFriendID else { return }
                        model.saveFavorite(friendID: selectedFriendID, message: message)
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                guard let favorite = model.favorite else { return }
                selectedFriendID = favorite.friendID
                message = favorite.message
            }
        }
    }
}
