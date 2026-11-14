import PokiCore
import SwiftUI

/// One accepted friend. The whole rounded container is the poke target: a
/// full-size button sits behind the content, and everything except the message
/// field lets taps fall through to it. The field stays an editing exception, so
/// tapping, selecting or typing in it never sends.
struct FriendRow: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isEditing: Bool
    @State private var acknowledged = false
    @State private var rejectedEdits = 0
    let friend: Friend

    private var isSending: Bool { model.sendingFriendIDs.contains(friend.id) }
    private var draftText: String { model.drafts[friend.id, default: ""] }
    private var remaining: Int { MessageValidator.remainingCharacters(for: draftText) }
    private var outgoingMessage: String { MessageValidator.resolvedMessage(from: draftText) }

    var body: some View {
        let draft = Binding(
            get: { draftText },
            set: { value in
                if MessageValidator.isValid(value) {
                    model.updateDraft(value, for: friend)
                } else {
                    // Never silently truncate: keep the last valid text and signal the refusal.
                    rejectedEdits += 1
                }
            }
        )

        ZStack {
            Button(action: send) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(.secondarySystemBackground))
            }
            .buttonStyle(RowPressStyle())
            .disabled(isSending)
            .accessibilityLabel("Poke \(friend.name)")
            .accessibilityValue(isSending ? "Sending" : acknowledged ? "Poked" : "")
            .accessibilityHint("Sends “\(outgoingMessage)”")

            HStack(spacing: 12) {
                Image(systemName: friend.avatarSystemName)
                    .font(.system(size: 46))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(friend.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if isEditing && remaining <= 10 {
                            Text("\(remaining)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(remaining <= 3 ? Color.orange : Color.secondary)
                                .accessibilityLabel("\(remaining) characters left")
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                    TextField(MessageValidator.defaultMessage, text: draft)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isEditing)
                        .submitLabel(.done)
                        .accessibilityLabel("Message for \(friend.name)")
                        .accessibilityHint("Up to \(MessageValidator.maximumLength) characters")
                }

                status
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .sensoryFeedback(.success, trigger: model.sentAt[friend.id])
        .sensoryFeedback(.error, trigger: model.failedAt[friend.id])
        .sensoryFeedback(.warning, trigger: rejectedEdits)
        .task(id: model.sentAt[friend.id]) {
            guard model.sentAt[friend.id] != nil else { return }
            withAnimation(.snappy) { acknowledged = true }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { acknowledged = false }
        }
    }

    @ViewBuilder
    private var status: some View {
        Group {
            if isSending {
                ProgressView().tint(Color(.systemBackground))
            } else if acknowledged {
                Image(systemName: "checkmark").font(.footnote.bold())
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "arrow.up").font(.footnote.bold())
            }
        }
        .frame(width: 34, height: 34)
        .foregroundStyle(Color(.systemBackground))
        .background(Color.primary, in: Circle())
    }

    private func send() {
        Task { await model.send(to: friend) }
    }
}

private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
