import SwiftUI

struct FeedbackBanner: View {
    let feedback: SendFeedback

    var body: some View {
        Label(
            feedback.succeeded ? "Poked \(feedback.friendName)" : "Couldn't poke \(feedback.friendName)",
            systemImage: feedback.succeeded ? "checkmark" : "exclamationmark.triangle"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.black, in: Capsule())
        .accessibilityAddTraits(.isStaticText)
    }
}

