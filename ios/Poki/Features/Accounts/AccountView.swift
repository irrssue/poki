import AuthenticationServices
import PokiCore
import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce: AppleSignInNonce?
    @State private var name = ""
    @State private var username = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if model.signedIn { profileSetup } else { signIn }
            }
            .disabled(busy)
            .navigationTitle("Poki")
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A little hello goes a long way.")
                .font(.title2.weight(.semibold))
            Text("Your people, one little poke away.")
                .foregroundStyle(.secondary)
            Spacer()
            if let error { Text(error).foregroundStyle(.red).accessibilityLabel("Error: \(error)") }
            if busy { ProgressView().frame(maxWidth: .infinity) }
            // One button covers both cases: a new Apple ID gets an account, a known one signs in.
            SignInWithAppleButton(.continue) { request in
                let nonce = AppleSignInNonce()
                self.nonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = nonce.hashed
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
                          let nonce else {
                        error = "Could not sign in with Apple. Please try again."
                        return
                    }
                    // Apple shares the name only on the first sign-in; use it to prefill profile setup.
                    if let fullName = credential.fullName, name.isEmpty {
                        name = PersonNameComponentsFormatter().string(from: fullName)
                    }
                    run { try await model.signInWithApple(idToken: token, nonce: nonce.raw) }
                case .failure(let failure):
                    if (failure as? ASAuthorizationError)?.code != .canceled {
                        error = "Could not sign in with Apple. Please try again."
                    }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            Text("Your email stays private; friends find you by username.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private var profileSetup: some View {
        Form {
            Section {
                Text("Make it yours.")
                    .font(.title2.weight(.semibold))
                Text("Choose a username so friends can find you.")
                    .foregroundStyle(.secondary)
            }
            if let syncError = model.syncError {
                Text(syncError).foregroundStyle(.red)
                Button("Retry loading account") { Task { await model.refresh() } }
            }
            Section("Your profile") {
                TextField("Your name", text: $name).textContentType(.name)
                TextField("@username", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("3–24 letters, numbers or underscores.").font(.caption).foregroundStyle(.secondary)
                Button("Continue") { run { try await model.createProfile(username: username, name: name) } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || username.count < 3)
            }
            Button("Use a different account") { Task { await model.signOut() } }
            if let error { Text(error).foregroundStyle(.red).accessibilityLabel("Error: \(error)") }
            if busy { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; error = nil
        Task {
            do { try await action() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
