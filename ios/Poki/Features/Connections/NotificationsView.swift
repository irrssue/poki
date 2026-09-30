import SwiftUI

struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var busyIDs: Set<UUID> = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if let error = model.syncError { Text(error).foregroundStyle(.secondary) }
                if model.requests.isEmpty && model.receivedPokes.isEmpty {
                    ContentUnavailableView("All quiet for now", systemImage: "bell", description: Text("Friend requests and pokes will appear here."))
                }
                let incoming = model.requests.filter(\.incoming)
                if !incoming.isEmpty {
                    Section("Friend requests") {
                        ForEach(incoming) { request in
                            VStack(alignment: .leading, spacing: 12) {
                                Text("@\(request.person.username)").font(.headline)
                                Text("\(request.person.name) wants to add you.").foregroundStyle(.secondary)
                                HStack {
                                    Button("Accept") { respond(request, accept: true) }.buttonStyle(.borderedProminent).tint(.black)
                                    Button("Decline") { respond(request, accept: false) }.buttonStyle(.bordered)
                                    if busyIDs.contains(request.id) { ProgressView() }
                                }.disabled(busyIDs.contains(request.id))
                            }.padding(.vertical, 6)
                        }
                    }
                }
                if !model.receivedPokes.isEmpty {
                    Section("Pokes · last 24 hours") {
                        ForEach(model.receivedPokes) { poke in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(poke.person.name) poked you").font(.headline)
                                Text(poke.message)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                let outgoing = model.requests.filter { !$0.incoming }
                if !outgoing.isEmpty {
                    Section("Sent requests") {
                        ForEach(outgoing) { request in
                            HStack { Text("@\(request.person.username)"); Spacer(); Text("Pending").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.refresh(); await model.markPokesRead() }
        }
    }
    private func respond(_ request: FriendRequest, accept: Bool) {
        busyIDs.insert(request.id); error = nil
        Task {
            do { try await model.respond(request.id, accept: accept) } catch { self.error = error.localizedDescription }
            busyIDs.remove(request.id)
        }
    }
}
