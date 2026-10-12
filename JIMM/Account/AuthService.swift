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
            return "Account is not available right now."
        case .notSignedIn:
            return "You are not signed in."
        case .invalidAppleCredential:
            return "Couldn’t sign in with Apple. Please try again."
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
        case .idle, .synced:
            return "Synced"
        case .syncing:
            return "Syncing…"
        case .pendingBackup:
            return "Ready to sync"
        case .offline:
            return "Offline"
        case .error:
            return "Sync failed. Try again."
        }
    }
}

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var session: Session?
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var profileFirstName: String?
    @Published private(set) var profileLastName: String?
    @Published var lastErrorMessage: String?
    /// Internal flag for quiet first sync after sign-in. Not shown in Account UI.
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
            clearProfileNames()
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
                        Task { await self.refreshProfile() }
                    } else {
                        self.clearProfileNames()
                    }
                case .signedOut:
                    self.syncStatus = .idle
                    self.shouldOfferInitialBackup = false
                    self.clearProfileNames()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Email / password

    func signUp(email: String, password: String, firstName: String, lastName: String?) async throws {
        let client = try requireClient()
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        guard !trimmedFirst.isEmpty else {
            throw AuthServiceError.message("Enter your first name.")
        }
        guard isValidEmail(trimmedEmail) else {
            throw AuthServiceError.message("Enter a valid email address.")
        }
        guard password.count >= 6 else {
            throw AuthServiceError.message("Password must be at least 6 characters.")
        }

        do {
            var meta: [String: AnyJSON] = [
                "first_name": .string(trimmedFirst)
            ]
            if let trimmedLast {
                meta["last_name"] = .string(trimmedLast)
            }

            _ = try await client.auth.signUp(
                email: trimmedEmail,
                password: password,
                data: meta,
                redirectTo: SupabaseConfig.authRedirectURL
            )
            session = try? await client.auth.session
            if session != nil {
                try? await upsertProfileNames(firstName: trimmedFirst, lastName: trimmedLast)
                await refreshProfile()
            } else {
                profileFirstName = trimmedFirst
                profileLastName = trimmedLast
            }
            evaluateInitialBackupOffer()
        } catch {
            throw AuthServiceError.message(Self.userFacingAuthMessage(from: error))
        }
    }

    func signIn(email: String, password: String) async throws {
        let client = try requireClient()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(trimmed) else {
            throw AuthServiceError.message("Enter a valid email address.")
        }
        guard !password.isEmpty else {
            throw AuthServiceError.message("Enter your password.")
        }

        do {
            let result = try await client.auth.signIn(email: trimmed, password: password)
            session = result
            await refreshProfile()
            evaluateInitialBackupOffer()
        } catch {
            throw AuthServiceError.message(Self.userFacingAuthMessage(from: error))
        }
    }

    /// Requests a password reset email. Does not reveal whether the account exists.
    func resetPassword(email: String) async throws {
        let client = try requireClient()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(trimmed) else {
            throw AuthServiceError.message("Enter a valid email address.")
        }
        do {
            try await client.auth.resetPasswordForEmail(
                trimmed,
                redirectTo: SupabaseConfig.authRedirectURL
            )
        } catch {
            // Ignore server-side differences that could leak account existence.
            // Callers should show the same success copy for any valid email.
        }
    }

    // MARK: - Apple

    func signInWithApple(idToken: String, fullName: PersonNameComponents?) async throws {
        let client = try requireClient()
        do {
            let result = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken)
            )
            session = result
            if let fullName {
                let first = fullName.givenName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                let last = fullName.familyName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                if first != nil || last != nil {
                    try? await upsertProfileNames(firstName: first, lastName: last)
                }
            }
            await refreshProfile()
            evaluateInitialBackupOffer()
        } catch {
            throw AuthServiceError.message(Self.userFacingAuthMessage(from: error))
        }
    }

    // MARK: - Session lifecycle

    func signOut() async throws {
        let client = try requireClient()
        do {
            try await client.auth.signOut()
            session = nil
            syncStatus = .idle
            shouldOfferInitialBackup = false
            clearProfileNames()
        } catch {
            throw AuthServiceError.message(Self.userFacingAuthMessage(from: error))
        }
    }

    /// Deletes online backup + auth user via Edge Function, then signs out locally.
    /// Local workouts on device are kept.
    func deleteAccount() async throws {
        let client = try requireClient()
        guard session != nil else { throw AuthServiceError.notSignedIn }

        do {
            try await client.functions.invoke("delete-account")
        } catch {
            throw AuthServiceError.message("Couldn’t delete account. Please try again.")
        }

        try? await client.auth.signOut()
        session = nil
        syncStatus = .idle
        shouldOfferInitialBackup = false
        clearProfileNames()
        clearBackupFlags()
    }

    func handleAuthRedirect(url: URL) async {
        guard let client = SupabaseService.shared.client else { return }
        do {
            try await client.auth.session(from: url)
            session = try? await client.auth.session
            await refreshProfile()
            evaluateInitialBackupOffer()
        } catch {
            lastErrorMessage = Self.userFacingAuthMessage(from: error)
        }
    }

    // MARK: - Profile

    func refreshProfile() async {
        guard let client = SupabaseService.shared.client, let userID else {
            clearProfileNames()
            return
        }
        do {
            let profile: ProfileDTO = try await client.from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            profileFirstName = profile.firstName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            profileLastName = profile.lastName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        } catch {
            // Fall back to auth metadata if profile row is not ready yet.
            if let meta = session?.user.userMetadata {
                profileFirstName = stringMetadata(meta["first_name"])
                profileLastName = stringMetadata(meta["last_name"])
            }
        }
    }

    private func upsertProfileNames(firstName: String?, lastName: String?) async throws {
        let client = try requireClient()
        guard let userID else { throw AuthServiceError.notSignedIn }
        let display = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " ")
            .nilIfEmpty

        struct ProfileNameUpdate: Encodable {
            let id: UUID
            let email: String?
            let first_name: String?
            let last_name: String?
            let display_name: String?
        }

        let payload = ProfileNameUpdate(
            id: userID,
            email: userEmail,
            first_name: firstName,
            last_name: lastName,
            display_name: display
        )
        try await client.from("profiles")
            .upsert(payload, onConflict: "id")
            .execute()
        profileFirstName = firstName
        profileLastName = lastName
    }

    private func clearProfileNames() {
        profileFirstName = nil
        profileLastName = nil
    }

    private func stringMetadata(_ value: AnyJSON?) -> String? {
        guard case let .string(text) = value else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func userFacingAuthMessage(from error: Error) -> String {
        if let authError = error as? AuthServiceError, let description = authError.errorDescription {
            return description
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("invalid login") || text.contains("invalid credentials") || text.contains("email not confirmed") {
            if text.contains("email not confirmed") {
                return "Confirm your email, then sign in."
            }
            return "Incorrect email or password."
        }
        if text.contains("already registered") || text.contains("user already") || text.contains("already been registered") {
            return "An account with this email already exists."
        }
        if text.contains("invalid format") || text.contains("valid email") || text.contains("unable to validate email") {
            return "Enter a valid email address."
        }
        if text.contains("password") && (text.contains("6") || text.contains("least") || text.contains("weak") || text.contains("short")) {
            return "Password must be at least 6 characters."
        }
        if text.contains("network") || text.contains("offline") || text.contains("internet") || text.contains("timed out") {
            return "Check your connection and try again."
        }
        return "Something went wrong. Please try again."
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
        guard SyncService.shared.isModelContextAttached else {
            shouldOfferInitialBackup = false
            syncStatus = .pendingBackup
            return
        }
        if SyncService.shared.hasLocalUserDataToBackup() {
            // Keep quiet: do not surface backup UI; mark pending for background sync.
            shouldOfferInitialBackup = false
            syncStatus = .pendingBackup
        } else {
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
