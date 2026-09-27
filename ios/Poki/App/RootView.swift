import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ZStack(alignment: .bottom) {
            Group {
                switch model.destination {
                case .home:
                    HomeView()
                case .profile:
                    ProfileView()
                }
            }

            BottomBar()
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $model.isFavoriteEditorPresented) {
            FavoriteEditorView()
        }
        .overlay(alignment: .top) {
            if let feedback = model.feedback {
                FeedbackBanner(feedback: feedback)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { model.feedback = nil }
                    }
            }
        }
        .animation(.snappy, value: model.feedback)
    }
}

