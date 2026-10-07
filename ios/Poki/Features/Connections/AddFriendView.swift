import SwiftUI

struct AddFriendView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var result: SearchResult?
    @State private var searched = false
    @State private var busy = false
    @State private var error: String?
    @State private var reporting: ReportTarget?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("@").foregroundStyle(.secondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.search).onSubmit { search() }
                        Button(action: search) { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                            .accessibilityLabel("Search username").disabled(username.isEmpty || busy)
                    }
                    Text("Enter their full username, like @irrssue. They’ll need to accept before you can poke each other.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                if let result {
                    Section {
                        HStack {
                            Image(systemName: "person.crop.circle.fill").font(.largeTitle)
                            VStack(alignment: .leading) {
                                Text(result.person.name).font(.headline)
                                Text("@\(result.person.username)").foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        switch result.relationship {
                        case "accepted": Label("Already friends", systemImage: "checkmark.circle")
                        case "outgoing": Label("Request sent", systemImage: "clock")
                        case "incoming":
                            Button("Respond to their request") { dismiss(); model.isNotificationsPresented = true }
                        default:
                            Button("Add friend", systemImage: "person.badge.plus") {
                                busy = true
                                Task {
                                    do {
                                        try await model.requestFriend(result.person.id)
                                        self.result = try await model.search(username: result.person.username)
                                    } catch { self.error = error.localizedDescription }
                                    busy = false
                                }
                            }.disabled(busy)
                        }
                        Button("Report @\(result.person.username)", systemImage: "exclamationmark.bubble", role: .destructive) {
                            reporting = ReportTarget(result.person)
                        }
                    }
                } else if searched && !busy && error == nil {
                    ContentUnavailableView("No user found", systemImage: "person.crop.circle.badge.questionmark", description: Text("Check the username and try again."))
                }
            }
            .navigationTitle("Add a friend").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $reporting, onDismiss: clearIfBlocked) { ReportView(target: $0) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: username) { _, _ in result = nil; searched = false; error = nil }
        }
    }
    // A person blocked while reporting disappears from search, as on the server.
    private func clearIfBlocked() {
        guard let result, model.blocked.contains(where: { $0.id == result.person.id }) else { return }
        self.result = nil; searched = false
    }
    private func search() {
        guard !busy, !username.isEmpty else { return }
        busy = true; error = nil; result = nil
        let query = username
        Task {
            do {
                let match = try await model.search(username: query)
                if username == query { result = match; searched = true }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
