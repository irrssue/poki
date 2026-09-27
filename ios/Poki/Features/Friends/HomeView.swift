import PokiCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(model.friends) { friend in
                    FriendRow(friend: friend)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 112)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityLabel("Friends")
    }
}

