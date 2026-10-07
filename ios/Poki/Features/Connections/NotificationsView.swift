import SwiftUI

struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var busyIDs: Set<UUID> = []
    @State private var error: String?
    @State private var reporting: ReportTarget?
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
                            .contextMenu { reportButton(ReportTarget(request.person)) }
                            .swipeActions { reportButton(ReportTarget(request.person)) }
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
                            .contextMenu { reportButton(ReportTarget(poke)) }
                            .swipeActions { reportButton(ReportTarget(poke)) }
                        }
                    }
                }
                let outgoing = model.requests.filter { !$0.incoming }
                if !outgoing.isEmpty {
                    Section("Sent requests") {
                        ForEach(outgoing) { request in
                            HStack {
                                Text("@\(request.person.username)"); Spacer(); Text("Pending").foregroundStyle(.secondary)
                                Button("Cancel") { cancel(request) }.buttonStyle(.bordered).disabled(busyIDs.contains(request.id))
                            }
                        }
                    }
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $reporting) { ReportView(target: $0) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.refresh(); await model.markPokesRead() }
        }
    }
    private func reportButton(_ target: ReportTarget) -> some View {
        Button("Report", systemImage: "exclamationmark.bubble", role: .destructive) { reporting = target }.tint(.red)
    }
    private func cancel(_ request: FriendRequest) {
        busyIDs.insert(request.id); error = nil
        Task {
            do { try await model.removeFriend(request.person.id) } catch { self.error = error.localizedDescription }
            busyIDs.remove(request.id)
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
