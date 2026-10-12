#if JIMM_ENABLE_APPLE_SIGN_IN
import AuthenticationServices
#endif
import SwiftUI

// MARK: - Settings section

struct AccountSettingsSection: View {
    @ObservedObject var auth: AuthService
    @Binding var showAccountSheet: Bool

    var body: some View {
        Section {
            if !SupabaseConfig.isConfigured {
                Text("Account is not available yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if auth.isSignedIn {
                Button {
                    showAccountSheet = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let firstName = auth.profileFirstName, !firstName.isEmpty {
                                Text(firstName)
                                    .foregroundStyle(.primary)
                            }
                            Text(auth.accountIdentifier)
                                .foregroundStyle(auth.profileFirstName == nil ? .primary : .secondary)
                                .font(auth.profileFirstName == nil ? .body : .footnote)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    showAccountSheet = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Account")
                                .foregroundStyle(.primary)
                            Text("Sign in or sign up.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Hub

struct AccountHubView: View {
    private enum AuthMode: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Sign Up"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthService.shared

    @State private var mode: AuthMode = .signIn
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var formMessage: String?
    @State private var isFormError = false
    @State private var alertMessage: String?
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showForgotPassword = false
    @State private var deleteConfirmationText = ""

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
        .sheet(isPresented: $showForgotPassword) {
            NavigationStack {
                ForgotPasswordView(initialEmail: email)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showDeleteConfirm, onDismiss: {
            deleteConfirmationText = ""
        }) {
            NavigationStack {
                deleteAccountConfirmation
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var signedOutContent: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(AuthMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
            if mode == .signUp {
                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)
                    .autocorrectionDisabled(true)
                TextField("Last Name", text: $lastName)
                    .textContentType(.familyName)
                    .autocorrectionDisabled(true)
            }
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            SecureField("Password", text: $password)
                .textContentType(mode == .signUp ? .newPassword : .password)
            if mode == .signIn {
                Button {
                    showForgotPassword = true
                } label: {
                    Text("Forgot password?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } footer: {
            if mode == .signUp {
                Text("Password must be at least 6 characters. Last name is optional.")
            }
        }

        Section {
            Button(mode.title) {
                Task { await submitAuth() }
            }
            .disabled(isWorking || !canSubmit)
        }

        if let formMessage {
            Section {
                Text(formMessage)
                    .foregroundStyle(isFormError ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        Section {
            if let firstName = auth.profileFirstName, !firstName.isEmpty {
                LabeledContent("First Name", value: firstName)
            }
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
                deleteConfirmationText = ""
                showDeleteConfirm = true
            }
        }
    }

    private var deleteAccountConfirmation: some View {
        Form {
            Section {
                Text("This will permanently delete your account and online backup. Workouts saved on this iPhone will stay here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            Section {
                TextField("Type DELETE", text: $deleteConfirmationText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } footer: {
                Text("Type DELETE to confirm.")
            }

            Section {
                Button("Delete Account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                .disabled(deleteConfirmationText != "DELETE" || isWorking)
            }
        }
        .navigationTitle("Delete account?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    showDeleteConfirm = false
                }
            }
        }
        .disabled(isWorking)
    }

    private var canSubmit: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp {
            return !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    #if JIMM_ENABLE_APPLE_SIGN_IN
    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            formMessage = AuthService.userFacingAuthMessage(from: error)
            isFormError = true
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                formMessage = AuthServiceError.invalidAppleCredential.localizedDescription
                isFormError = true
                return
            }
            isWorking = true
            defer { isWorking = false }
            do {
                try await auth.signInWithApple(idToken: idToken, fullName: credential.fullName)
                formMessage = nil
            } catch {
                formMessage = AuthService.userFacingAuthMessage(from: error)
                isFormError = true
            }
        }
    }
    #endif

    private func submitAuth() async {
        isWorking = true
        defer { isWorking = false }
        isFormError = false
        formMessage = nil
        do {
            switch mode {
            case .signIn:
                try await auth.signIn(email: email, password: password)
            case .signUp:
                try await auth.signUp(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName
                )
                if !auth.isSignedIn {
                    formMessage = "Check your email to confirm your account, then sign in."
                    isFormError = false
                    mode = .signIn
                }
            }
        } catch {
            isFormError = true
            formMessage = AuthService.userFacingAuthMessage(from: error)
        }
    }

    private func signOut() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.signOut()
            dismiss()
        } catch {
            alertMessage = AuthService.userFacingAuthMessage(from: error)
        }
    }

    private func deleteAccount() async {
        guard deleteConfirmationText == "DELETE" else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.deleteAccount()
            showDeleteConfirm = false
            dismiss()
        } catch {
            showDeleteConfirm = false
            alertMessage = AuthService.userFacingAuthMessage(from: error)
        }
    }
}

// MARK: - Forgot password

private struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthService.shared

    @State private var email: String
    @State private var isWorking = false
    @State private var message: String?
    @State private var isError = false

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            } footer: {
                Text("Enter your email and we’ll send you a reset link.")
            }

            Section {
                Button("Send Reset Link") {
                    Task { await submit() }
                }
                .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(isError ? .red : .secondary)
                }
            }
        }
        .navigationTitle("Reset password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .disabled(isWorking)
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        isError = false
        message = nil
        do {
            try await auth.resetPassword(email: email)
            message = "Check your email for a password reset link."
        } catch {
            isError = true
            message = AuthService.userFacingAuthMessage(from: error)
        }
    }
}
