import AuthenticationServices
import Combine
import Foundation
import Supabase
import SwiftUI

enum AuthServiceError: LocalizedError {
    case notConfigured
    case notSignedIn
    case invalidAppleCredential
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Cloud account is not available right now."
        case .notSignedIn:
            return "You are not signed in."
        case .invalidAppleCredential:
            return "Apple Sign In did not return a valid identity token."
        case .message(let text):
            return text
        }
    }
}

enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced(Date)
    case pendingBackup
    case offline
    case error(String)

    var label: String {
        switch self {
        case .idle:
            return "Not synced"
        case .syncing:
            return "Syncing…"
        case .synced(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .pendingBackup:
            return "Local data ready to back up"
        case .offline:
            return "Offline — will sync later"
        case .error(let message):
            return message
        }
    }
}

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var session: Session?
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published var lastErrorMessage: String?
    /// Shown once after sign-in when local workouts/plans exist and may need first backup.
    @Published var shouldOfferInitialBackup = false

    private var authListenerTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let offeredBackupKeyPrefix = "account.offeredInitialBackup."

    var isSignedIn: Bool { session != nil }
    var userEmail: String? { session?.user.email }
    var userID: UUID? { session?.user.id }
    var accountIdentifier: String {
        if let email = userEmail, !email.isEmpty { return email }
        if let id = userID { return id.uuidString }
        return "Signed in"
    }

    private init() {
        bootstrap()
    }

    func bootstrap() {
        authListenerTask?.cancel()
        guard let client = SupabaseService.shared.client else {
            session = nil
            syncStatus = .idle
            return
        }

        authListenerTask = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                self.session = session
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if session != nil {
                        self.evaluateInitialBackupOffer()
                        if self.syncStatus != .syncing {
                            self.syncStatus = self.hasCompletedInitialBackup ? .idle : .pendingBackup
                        }
                    }
                case .signedOut:
                    self.syncStatus = .idle
                    self.shouldOfferInitialBackup = false
                default:
                    break
                }
            }
        }
    }

    // MARK: - Email / password

    func signUp(email: String, password: String) async throws {
        let client = try requireClient()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        _ = try await client.auth.signUp(
            email: trimmed,
            password: password,
            redirectTo: SupabaseConfig.authRedirectURL
        )
        // Session may be nil until email confirmation depending on project settings.
        session = try? await client.auth.session
        evaluateInitialBackupOffer()
    }

    func signIn(email: String, password: String) async throws {
        let client = try requireClient()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result = try await client.auth.signIn(email: trimmed, password: password)
        session = result
        evaluateInitialBackupOffer()
    }

    func resetPassword(email: String) async throws {
        let client = try requireClient()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try await client.auth.resetPasswordForEmail(
            trimmed,
            redirectTo: SupabaseConfig.authRedirectURL
        )
    }

    // MARK: - Apple

    func signInWithApple(idToken: String, fullName: PersonNameComponents?) async throws {
        let client = try requireClient()
        let result = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken)
        )
        session = result
        if let fullName {
            let formatted = PersonNameComponentsFormatter().string(from: fullName)
            if !formatted.isEmpty {
                _ = try? await client.auth.update(
                    user: UserAttributes(data: ["full_name": .string(formatted)])
                )
            }
        }
        evaluateInitialBackupOffer()
    }

    // MARK: - Session lifecycle

    func signOut() async throws {
        let client = try requireClient()
        try await client.auth.signOut()
        session = nil
        syncStatus = .idle
        shouldOfferInitialBackup = false
    }

    /// Deletes online backup + auth user via Edge Function, then signs out locally.
    /// Local workouts on device are kept.
    func deleteAccount() async throws {
        let client = try requireClient()
        guard session != nil else { throw AuthServiceError.notSignedIn }

        do {
            try await client.functions.invoke("delete-account")
        } catch {
            // If the function is not deployed, surface a clear error.
            throw AuthServiceError.message(
                "Could not delete account. Please try again. (\(error.localizedDescription))"
            )
        }

        try? await client.auth.signOut()
        session = nil
        syncStatus = .idle
        shouldOfferInitialBackup = false
        clearBackupFlags()
    }

    func handleAuthRedirect(url: URL) async {
        guard let client = SupabaseService.shared.client else { return }
        do {
            try await client.auth.session(from: url)
            session = try? await client.auth.session
            evaluateInitialBackupOffer()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Sync status helpers

    func setSyncStatus(_ status: SyncStatus) {
        syncStatus = status
    }

    func markInitialBackupCompleted() {
        guard let userID else { return }
        defaults.set(true, forKey: offeredBackupKeyPrefix + userID.uuidString)
        shouldOfferInitialBackup = false
        if case .pendingBackup = syncStatus {
            syncStatus = .idle
        }
    }

    var hasCompletedInitialBackup: Bool {
        guard let userID else { return true }
        return defaults.bool(forKey: offeredBackupKeyPrefix + userID.uuidString)
    }

    func evaluateInitialBackupOffer() {
        guard isSignedIn, !hasCompletedInitialBackup else {
            shouldOfferInitialBackup = false
            return
        }
        // Wait until SwiftData is attached before deciding there is nothing to back up.
        guard SyncService.shared.isModelContextAttached else {
            shouldOfferInitialBackup = false
            syncStatus = .pendingBackup
            return
        }
        if SyncService.shared.hasLocalUserDataToBackup() {
            shouldOfferInitialBackup = true
            syncStatus = .pendingBackup
        } else {
            // Nothing local to back up; still allow future sync of new workouts.
            shouldOfferInitialBackup = false
            markInitialBackupCompleted()
        }
    }

    private func clearBackupFlags() {
        let prefix = offeredBackupKeyPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client = SupabaseService.shared.client else {
            throw AuthServiceError.notConfigured
        }
        return client
    }
}
