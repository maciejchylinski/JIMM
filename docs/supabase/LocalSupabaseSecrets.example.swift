import Foundation

/// Copy to `JIMM/Account/LocalSupabaseSecrets.swift` and fill in values.
/// That file is gitignored — never commit real keys.
///
/// Use only the **anon** (public) key from Supabase → Project Settings → API.
/// Never put the service_role key, database password, or admin secrets in the app.
enum LocalSupabaseSecrets {
    static let urlString = "https://YOUR_PROJECT_REF.supabase.co"
    static let anonKey = "YOUR_SUPABASE_ANON_KEY"
}
