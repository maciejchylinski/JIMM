import Foundation

/// Public Supabase client configuration for JIMM.
///
/// Fill `LocalSupabaseSecrets.swift` (gitignored) by copying
/// `docs/supabase/LocalSupabaseSecrets.example.swift`. Only the anon key is allowed in the app.
enum SupabaseConfig {
    static var url: URL? {
        let raw = LocalSupabaseSecrets.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    static var anonKey: String? {
        let key = LocalSupabaseSecrets.anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// Soft redirect used for email confirmation / password recovery links.
    static let authRedirectURL = URL(string: "mch.jim://auth-callback")!

    static var isConfigured: Bool {
        url != nil && anonKey != nil
    }
}
