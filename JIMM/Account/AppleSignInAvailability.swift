import Foundation

/// Compile-time availability for Sign in with Apple.
///
/// Controlled by the `JIMM_ENABLE_APPLE_SIGN_IN` Swift active compilation condition.
/// - **Release**: enabled (uses `JIMM.entitlements` with the Apple capability).
/// - **Debug** (Personal Team): disabled (uses `JIMM.Debug.entitlements` without the capability).
///
/// To re-enable for local Debug after joining the paid Apple Developer Program:
/// 1. JIMM target → Debug → Code Signing Entitlements → `JIMM/JIMM.entitlements`
/// 2. JIMM target → Debug → Swift Active Compilation Conditions → add `JIMM_ENABLE_APPLE_SIGN_IN`
enum AppleSignInAvailability {
    #if JIMM_ENABLE_APPLE_SIGN_IN
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif
}
