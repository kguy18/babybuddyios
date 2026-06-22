import SwiftUI

/// Server URL + API token entry. Baby Buddy has no REST login endpoint, so the user
/// pastes the token from their web Settings page; we validate it with a probe request.
struct OnboardingView: View {
    @Environment(AppSession.self) private var session

    @State private var serverURL = "https://demo.baby-buddy.net"
    @State private var token = ""
    @State private var isValidating = false

    private var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
            && !isValidating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://baby.example.com", text: $serverURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Connect to Baby Buddy")
                } footer: {
                    Text("Find your API token on your Baby Buddy site under User → Settings.")
                }

                if let error = session.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            if isValidating { ProgressView().padding(.trailing, 4) }
                            Text(isValidating ? "Connecting…" : "Connect")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Baby Buddy")
        }
    }

    private func submit() {
        isValidating = true
        Task {
            _ = await session.signIn(serverURL: serverURL, token: token)
            isValidating = false
        }
    }
}
