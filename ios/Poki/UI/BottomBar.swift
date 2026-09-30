import SwiftUI

struct BottomBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Task { await model.sendFavorite() }
            } label: {
                Image(systemName: model.favorite == nil ? "star" : "star.fill")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel(favoriteAccessibilityLabel)

            Rectangle()
                .fill(.white.opacity(0.28))
                .frame(width: 1, height: 26)

            Button {
                model.isAddFriendPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel("Add a friend")

            Rectangle().fill(.white.opacity(0.28)).frame(width: 1, height: 26)

            Button {
                withAnimation(.snappy) {
                    model.destination = model.destination == .profile ? .home : .profile
                }
            } label: {
                Image(systemName: model.destination == .profile ? "house.fill" : "person.crop.circle.fill")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel(model.destination == .profile ? "Friends" : "Profile")
        }
        .font(.title3)
        .foregroundStyle(.white)
        .frame(width: 216, height: 58)
        .background(.black, in: Capsule())
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
    }

    private var favoriteAccessibilityLabel: String {
        guard let favorite = model.favorite,
              let friend = model.friends.first(where: { $0.id == favorite.friendID }) else {
            return "Configure favorite poke"
        }
        return "Poke \(friend.name)"
    }
}

