import Foundation
import Supabase

/// Shared Supabase client. Safe to use when unconfigured — `client` is nil.
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    private(set) var client: SupabaseClient?

    private init() {
        reconfigure()
    }

    func reconfigure() {
        guard let url = SupabaseConfig.url, let anonKey = SupabaseConfig.anonKey else {
            client = nil
            return
        }
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    redirectToURL: SupabaseConfig.authRedirectURL,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    var isConfigured: Bool { client != nil }
}
