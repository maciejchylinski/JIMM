# JIMM Supabase setup (account, auth, sync, delete)

## 1. Create a Supabase project

1. Create a project at [supabase.com](https://supabase.com).
2. Open **Project Settings → API**.
3. Copy:
   - **Project URL** → `SUPABASE_URL`
   - **anon public** key → `SUPABASE_ANON_KEY`
4. Never put the **service_role** key in the iOS app or git.

## 2. App local secrets

```bash
cp docs/supabase/LocalSupabaseSecrets.example.swift JIMM/Account/LocalSupabaseSecrets.swift
```

Edit `JIMM/Account/LocalSupabaseSecrets.swift` with your URL and anon key.
That file is gitignored.

## 3. Run SQL

In the Supabase SQL Editor, run the full script:

`supabase/migrations/20260326_jimm_account_sync.sql`

Then, if the project already existed before profile names were added, also run:

`supabase/migrations/20261012_profiles_first_last_name.sql`

This creates tables, profile trigger, grants, and RLS so each user can only access their own rows. Profile stores optional `first_name` / `last_name` for Account UI.

## 4. Auth providers (Dashboard → Authentication)

### Email

- Enable **Email** provider.
- Decide whether email confirmation is required (recommended for production).
- Under **URL Configuration**, add redirect URL:
  - `mch.jim://auth-callback`
- Site URL can stay the default for now; password reset / confirm links should use the redirect above.

### Sign in with Apple

1. In Apple Developer → Identifiers → your App ID (`mch.jim`): enable **Sign In with Apple**.
2. In Xcode: target **JIMM** → Signing & Capabilities → **Sign in with Apple** (entitlements file is already wired).
3. In Supabase → Authentication → Providers → **Apple**:
   - Enable Apple.
   - For native iOS `signInWithIdToken`, add your **App ID / bundle ID** (`mch.jim`) to **Client IDs**.
   - Secret Key / Services ID setup is mainly needed for web OAuth; native ID-token flow uses the bundle ID audience.

## 5. Deploy delete-account Edge Function

Full auth user deletion requires the Admin API (service role), which must stay on the server.

```bash
# From a machine with Supabase CLI logged in:
supabase functions deploy delete-account --project-ref YOUR_PROJECT_REF
```

Ensure function secrets include (usually auto-injected on hosted Supabase):

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (Function secret only)

Source: `supabase/functions/delete-account/index.ts`

In Dashboard → Edge Functions → `delete-account`, confirm JWT verification is enabled so only signed-in users can invoke it.

## 6. Verify

1. Build & run JIMM.
2. Settings → Account → Create account / Sign in / Continue with Apple.
3. Back up local data when prompted; use **Sync Now**.
4. Airplane mode: log a workout (must work).
5. Go online → Sync Now → data appears in Supabase Table Editor (your `user_id` only).
6. Delete Account → cloud rows + auth user gone; local data kept unless you chose otherwise.

## Security checklist

- [ ] RLS enabled on all JIMM tables
- [ ] No table policies for `anon` role
- [ ] App contains only anon key
- [ ] service_role only in Edge Function secrets
- [ ] `LocalSupabaseSecrets.swift` not committed
