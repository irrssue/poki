import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var name = ""
    @State private var username = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.signedIn ? "Make it yours." : "A little hello goes a long way.")
                        .font(.title2.weight(.semibold))
                    Text(model.signedIn ? "Choose a username so friends can find you." : "Sign in or create your account with a code sent to your email.")
                        .foregroundStyle(.secondary)
                }
                if model.signedIn {
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
                    Section("Email") {
                        TextField("you@example.com", text: $email)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .disabled(codeSent)
                        if codeSent {
                            TextField("Email code", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                            Button("Verify code") { run { try await model.verify(email: email, code: code) } }
                                .disabled(code.count < 6)
                            Button("Send a new code") { run { try await model.accountService.requestCode(email: email) } }
                            Button("Change email") { codeSent = false; code = ""; error = nil }
                        } else {
                            Button("Send sign-in code") {
                                run {
                                    email = email.trimmingCharacters(in: .whitespacesAndNewlines)
                                    try await model.accountService.requestCode(email: email)
                                    codeSent = true
                                }
                            }.disabled(!email.contains("@"))
                        }
                    }
                    if codeSent { Text("Check your inbox for your Poki sign-in code.").font(.footnote) }
                }
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
