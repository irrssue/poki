import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var creatingAccount = true
    @State private var name = ""
    @State private var username = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.signedIn ? "Make it yours." : "A little hello goes a long way.")
                        .font(.title2.weight(.semibold))
                    Text(model.signedIn ? "Choose a username so friends can find you." : "Your people, one little poke away.")
                        .foregroundStyle(.secondary)
                }
                if model.signedIn {
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
                } else {
                    Section(creatingAccount ? "Create your account" : "Welcome back") {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(creatingAccount ? .newPassword : .password)
                        if creatingAccount {
                            Text("Use at least 8 characters. Your email stays private; friends find you by username.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button(creatingAccount ? "Create account" : "Sign in") {
                            run {
                                let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
                                if creatingAccount {
                                    let signedIn = try await model.signUp(email: email, password: password)
                                    if !signedIn {
                                        notice = "Check your email on this iPhone and tap the confirmation link to return to Poki. If you already tapped it, try signing in."
                                        creatingAccount = false
                                    }
                                } else { try await model.signIn(email: email, password: password) }
                                password = ""
                            }
                        }.disabled(!email.contains("@") || (creatingAccount ? password.count < 8 : password.isEmpty))
                    }
                    if !creatingAccount {
                        Button("Resend confirmation email") {
                            run {
                                try await model.accountService.resendConfirmation(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
                                notice = "If confirmation is needed, a new email has been sent. Open the newest link on this iPhone."
                            }
                        }.disabled(!email.contains("@"))
                    }
                    Button(creatingAccount ? "Already have an account? Sign in" : "New here? Create an account") {
                        creatingAccount.toggle(); error = nil; notice = nil; password = ""
                    }
                }
                if let notice { Text(notice).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red).accessibilityLabel("Error: \(error)") }
                if busy { ProgressView().frame(maxWidth: .infinity) }
            }
            .disabled(busy)
            .navigationTitle("Poki")
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
