#if JIMM_ENABLE_APPLE_SIGN_IN
import AuthenticationServices
#endif
import SwiftUI

// MARK: - Settings section

struct AccountSettingsSection: View {
    @ObservedObject var auth: AuthService
    @State private var showAccountSheet = false

    var body: some View {
        Section("Account") {
            if !SupabaseConfig.isConfigured {
                Text("Account is not available yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if auth.isSignedIn {
                Button {
                    showAccountSheet = true
                } label: {
                    HStack {
                        Text(auth.accountIdentifier)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Button("Account") {
                    showAccountSheet = true
                }
                Text("Sign in to use your account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showAccountSheet) {
            NavigationStack {
                AccountHubView()
            }
        }
    }
}

// MARK: - Hub

struct AccountHubView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthService.shared

    @State private var isWorking = false
    @State private var alertMessage: String?
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            if auth.isSignedIn {
                signedInContent
            } else {
                signedOutContent
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(UITheme.appBackground.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .disabled(isWorking)
        .overlay {
            if isWorking {
                ProgressView()
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Account", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your workouts stay on this iPhone.")
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and online backup. Workouts saved on this iPhone will stay here.")
        }
    }

    @ViewBuilder
    private var signedOutContent: some View {
        Section {
            Text("Sign in or create an account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(Color.clear)
        }

        #if JIMM_ENABLE_APPLE_SIGN_IN
        Section {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        #endif

        Section {
            NavigationLink("Sign In") {
                EmailAuthFormView(mode: .signIn)
            }
            NavigationLink("Create Account") {
                EmailAuthFormView(mode: .signUp)
            }
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        Section {
            LabeledContent(
                "Email",
                value: auth.userEmail?.isEmpty == false ? (auth.userEmail ?? "") : auth.accountIdentifier
            )
        }

        Section {
            Button("Sign Out", role: .destructive) {
                showSignOutConfirm = true
            }
            Button("Delete Account", role: .destructive) {
                showDeleteConfirm = true
            }
        }
    }

    #if JIMM_ENABLE_APPLE_SIGN_IN
    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            alertMessage = error.localizedDescription
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                alertMessage = AuthServiceError.invalidAppleCredential.localizedDescription
                return
            }
            isWorking = true
            defer { isWorking = false }
            do {
                try await auth.signInWithApple(idToken: idToken, fullName: credential.fullName)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }
    #endif

    private func signOut() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.signOut()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.deleteAccount()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

// MARK: - Email forms

struct EmailAuthFormView: View {
    enum Mode {
        case signUp
        case signIn
        case reset

        var title: String {
            switch self {
            case .signUp: return "Create Account"
            case .signIn: return "Sign In"
            case .reset: return "Reset password"
            }
        }

        var submitTitle: String {
            switch self {
            case .signUp: return "Create Account"
            case .signIn: return "Sign In"
            case .reset: return "Send Reset Link"
            }
        }
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthService.shared

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if mode == .signIn || mode == .signUp {
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                }
                if mode == .signIn {
                    NavigationLink {
                        EmailAuthFormView(mode: .reset)
                    } label: {
                        Text("Forgot password?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                switch mode {
                case .signUp:
                    Text("Use at least 6 characters.")
                case .signIn:
                    EmptyView()
                case .reset:
                    Text("Enter your email and we’ll send you a reset link.")
                }
            }

            Section {
                Button(mode.submitTitle) {
                    Task { await submit() }
                }
                .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ((mode == .signIn || mode == .signUp) && password.isEmpty))
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(isError ? .red : .secondary)
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        isError = false
        do {
            switch mode {
            case .signUp:
                try await auth.signUp(email: email, password: password)
                if auth.isSignedIn {
                    dismiss()
                } else {
                    message = "Check your email to confirm your account, then sign in."
                }
            case .signIn:
                try await auth.signIn(email: email, password: password)
                dismiss()
            case .reset:
                try await auth.resetPassword(email: email)
                message = "Check your email for a password reset link."
            }
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }
}
