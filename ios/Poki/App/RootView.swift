import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Group {
            if model.starting {
                ProgressView()
            } else if !model.signedIn || model.profile == nil {
                AccountView()
            } else {
                Group {
                    switch model.destination {
                    case .home: HomeView()
                    case .profile: ProfileView()
                    }
                }
                .safeAreaInset(edge: .bottom) { BottomBar().padding(.bottom, 8) }
            }
        }
        .background(Color(.systemBackground))
        .task { await model.start() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
        .sheet(isPresented: $model.isAddFriendPresented) { AddFriendView() }
        .sheet(isPresented: $model.isNotificationsPresented) { NotificationsView() }
        .sheet(isPresented: $model.isFavoriteEditorPresented) { FavoriteEditorView() }
        .overlay(alignment: .top) {
            if let feedback = model.feedback {
                FeedbackBanner(feedback: feedback)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: feedback) {
                        try? await Task.sleep(for: .seconds(1.5))
                        guard !Task.isCancelled else { return }
                        withAnimation { model.feedback = nil }
                    }
            }
        }
        .animation(.snappy, value: model.feedback)
    }
}
