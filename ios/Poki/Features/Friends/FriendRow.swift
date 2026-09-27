import PokiCore
import SwiftUI

struct FriendRow: View {
    @Environment(AppModel.self) private var model
    let friend: Friend

    private var isSending: Bool {
        model.sendingFriendIDs.contains(friend.id)
    }

    var body: some View {
        @Bindable var model = model
        let draft = Binding(
            get: { model.drafts[friend.id, default: ""] },
            set: { model.updateDraft($0, for: friend) }
        )

        HStack(spacing: 12) {
            Button {
                Task { await model.send(to: friend) }
            } label: {
                Image(systemName: friend.avatarSystemName)
                    .font(.system(size: 46))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityLabel("Poke \(friend.name)")

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(.subheadline.weight(.semibold))

                TextField("Thinking of you", text: draft)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .submitLabel(.done)
                    .accessibilityLabel("Message for \(friend.name)")
            }

            Button {
                Task { await model.send(to: friend) }
            } label: {
                Group {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.body.bold())
                    }
                }
                .frame(width: 42, height: 42)
                .foregroundStyle(.white)
                .background(.black, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityLabel("Send poke to \(friend.name)")
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}

