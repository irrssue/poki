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
                            Text("Your profile")
                                .font(.headline)
                            Text("@you")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Poki") {
                    Button("Add a friend", systemImage: "person.badge.plus") { }
                    Button("Friend requests", systemImage: "person.2") { }
                    Button("Configure favorite", systemImage: "star") {
                        model.isFavoriteEditorPresented = true
                    }
                }

                Section("Settings") {
                    Label("Notifications", systemImage: "bell")
                    Label("Privacy and safety", systemImage: "hand.raised")
                    Label("Help", systemImage: "questionmark.circle")
                }

                Section {
                    Text("Prototype mode · sends are simulated")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .safeAreaPadding(.bottom, 88)
        }
    }
}

