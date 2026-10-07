import SwiftUI
import PokiCore

enum ReportReason: String, CaseIterable, Identifiable {
    case harassment, inappropriate, spam, impersonation, other
    var id: Self { self }
    var title: String {
        switch self {
        case .harassment: "Harassment or bullying"
        case .inappropriate: "Inappropriate or offensive"
        case .spam: "Spam"
        case .impersonation: "Pretending to be someone else"
        case .other: "Something else"
        }
    }
}

/// A person, or one poke they sent; reporting a poke keeps its message as evidence.
struct ReportTarget: Identifiable {
    let personID: UUID
    let name: String
    let username: String
    var pokeID: UUID?
    var message: String?
    var id: String { pokeID?.uuidString ?? personID.uuidString }

    init(_ friend: Friend) { personID = friend.id; name = friend.name; username = friend.username }
    init(_ person: Person) { personID = person.id; name = person.name; username = person.username }
    init(_ poke: ReceivedPoke) { self.init(poke.person); pokeID = poke.id; message = poke.message }
}

struct ReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: ReportTarget
    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var block = true
    @State private var busy = false
    @State private var error: String?
    @State private var sent = false
    @State private var didBlock = false

    private var alreadyBlocked: Bool { model.blocked.contains { $0.id == target.personID } }
    private var blocking: Bool { block && !alreadyBlocked }

    var body: some View {
        NavigationStack {
            Group {
                if sent {
                    ContentUnavailableView {
                        Label("Thanks for telling us", systemImage: "checkmark.shield")
                    } description: {
                        Text(didBlock
                             ? "We’ll review your report. @\(target.username) is now blocked and won’t know you reported them."
                             : "We’ll review your report. @\(target.username) won’t know you reported them.")
                    } actions: {
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(.black)
                    }
                } else {
                    form
                }
            }
            .navigationTitle(target.pokeID == nil ? "Report @\(target.username)" : "Report poke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !sent {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send", action: submit)
                            .disabled(reason == nil || !ReportDetails.isValid(details) || busy)
                    }
                }
            }
        }
        .interactiveDismissDisabled(busy)
    }

    private var form: some View {
        Form {
            if let message = target.message {
                Section("\(target.name) poked you") { Text(message) }
            }
            Section("What’s wrong?") {
                Picker("Reason", selection: $reason) {
                    ForEach(ReportReason.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                TextField("Add details (optional)", text: $details, axis: .vertical)
                    .lineLimit(2...6)
            } footer: {
                let remaining = ReportDetails.remainingCharacters(for: details)
                if remaining < 50 {
                    Text("\(remaining) characters left").foregroundStyle(remaining < 0 ? .red : .secondary)
                }
            }
            Section {
                if !alreadyBlocked { Toggle("Also block @\(target.username)", isOn: $block) }
            } footer: {
                Text(blocking
                     ? "Blocking removes them from your friends, hides you from their search, and stops their requests. Reports are private."
                     : "Reports are private. Poki reviews them and may remove accounts that break the rules.")
            }
            if let error { Text(error).foregroundStyle(.red) }
            if busy { ProgressView() }
        }
        .disabled(busy)
    }

    private func submit() {
        guard let reason, !busy else { return }
        busy = true; error = nil
        let block = blocking
        Task {
            do {
                try await model.report(target.personID, reason: reason, pokeID: target.pokeID, details: details, block: block)
                didBlock = block; sent = true
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
