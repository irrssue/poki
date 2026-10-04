import PokiCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { model.isNotificationsPresented = true } label: {
                    Image(systemName: model.notificationCount > 0 ? "bell.badge" : "bell")
                        .font(.title3).foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Notifications, \(model.notificationCount) unread")
            }.padding(.horizontal, 16)
            if let error = model.syncError {
                Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            }
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.friends.isEmpty {
                    ContentUnavailableView {
                        Label("A little closer", systemImage: "person.2")
                    } description: {
                        Text("Add someone you’re thinking of. Once they accept, you can send each other a poke.")
                    } actions: {
                        Button("Add a friend") { model.isAddFriendPresented = true }.buttonStyle(.borderedProminent).tint(.black)
                    }.padding(.top, 70)
                }
                ForEach(model.friends) { friend in
                    FriendRow(friend: friend).id(friend.id)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityLabel("Friends")
        .refreshable { await model.refresh() }
        .onChange(of: model.selectedFriendID) { _, id in
            if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
        }
        .onAppear { if let id = model.selectedFriendID { proxy.scrollTo(id, anchor: .center) } }
        }
        }
    }
}

