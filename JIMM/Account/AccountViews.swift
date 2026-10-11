#if JIMM_ENABLE_APPLE_SIGN_IN
import AuthenticationServices
#endif
import SwiftData
import SwiftUI

// MARK: - Settings section

struct AccountSettingsSection: View {
    @ObservedObject var auth: AuthService
    @ObservedObject var sync: SyncService
    @State private var showAccountSheet = false

    var body: some View {
        Section("Account") {
            if !SupabaseConfig.isConfigured {
                Text("Cloud backup is not available yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if auth.isSignedIn {
                Button {
                    showAccountSheet = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(auth.accountIdentifier)
                                .foregroundStyle(.primary)
                            Text(auth.syncStatus.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Button("Sign In / Create Account") {
                    showAccountSheet = true
                }
                Text("Optional. Workouts stay on this device. Sign in to back up and sync.")
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
    @ObservedObject private var sync = SyncService.shared

    @State private var isWorking = false
    @State private var alertMessage: String?
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @Environment(\.modelContext) private var modelContext

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
            Text("Your workouts stay on this device. Cloud backup pauses until you sign in again.")
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
        .alert("Back up local workouts?", isPresented: $auth.shouldOfferInitialBackup) {
            Button("Back Up Now") {
                Task { await runSync(manual: true) }
            }
            Button("Not Now", role: .cancel) {
                auth.markInitialBackupCompleted()
            }
        } message: {
            Text("You have workouts or plans on this device. Back them up to your account? You can sync later from Settings.")
        }
    }

    @ViewBuilder
    private var signedOutContent: some View {
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
        } footer: {
            Text("Continue with Apple uses your Apple ID. Email is optional depending on your Apple privacy choices.")
        }
        #endif

        Section("Email") {
            NavigationLink("Create Account") {
                EmailAuthFormView(mode: .signUp)
            }
            NavigationLink("Sign In") {
                EmailAuthFormView(mode: .signIn)
            }
            NavigationLink("Forgot Password") {
                EmailAuthFormView(mode: .reset)
            }
        }

        Section {
            Text("JIMM works fully offline without an account. Signing in only enables optional cloud backup and sync.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        Section("Signed In") {
            LabeledContent("Account", value: auth.accountIdentifier)
            LabeledContent("Sync", value: auth.syncStatus.label)
            if let error = sync.lastSyncError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        Section {
            Button {
                Task { await runSync(manual: true) }
            } label: {
                Label(
                    auth.hasCompletedInitialBackup ? "Sync Now" : "Back Up Data",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .disabled(sync.isSyncing)
        } footer: {
            Text("New workouts sync when you are signed in and online. Logging never waits on the network.")
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

    private func runSync(manual: Bool) async {
        isWorking = true
        defer { isWorking = false }
        SyncService.shared.attach(modelContext: modelContext)
        await sync.syncNow(isManual: manual)
        if let error = sync.lastSyncError, manual {
            alertMessage = error
        }
    }

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
            case .reset: return "Reset Password"
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
                if mode != .reset {
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                }
            } footer: {
                switch mode {
                case .signUp:
                    Text("Use at least 6 characters. You may need to confirm your email before signing in.")
                case .signIn:
                    Text("Sign in with the email and password for your JIMM account.")
                case .reset:
                    Text("We will email a password reset link if an account exists for this address.")
                }
            }

            Section {
                Button(mode.title) {
                    Task { await submit() }
                }
                .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (mode != .reset && password.isEmpty))
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
                    message = "Account created. Check your email to confirm, then sign in."
                }
            case .signIn:
                try await auth.signIn(email: email, password: password)
                dismiss()
            case .reset:
                try await auth.resetPassword(email: email)
                message = "If an account exists for that email, a reset link has been sent."
            }
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }
}
