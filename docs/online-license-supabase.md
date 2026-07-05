# Online License with Supabase

This project now includes a Supabase-based online license scaffold:

- SQL schema and RLS: `supabase/migrations/20260702_online_license.sql`
- Seed example: `supabase/seeds/create_test_license.sql`
- Edge Functions:
  - `supabase/functions/activate-license/index.ts`
  - `supabase/functions/validate-license/index.ts`
- Flutter client service:
  - `lib/app/services/license/online_license_service.dart`
- Postman collection:
  - `postman/trading-desk-license.postman_collection.json`
- PowerShell deploy helper:
  - `scripts/deploy_supabase_functions.ps1`

## 1. Create Supabase project

Create a Supabase project, then enable Auth with Email/Password.

## 2. Run the SQL migration

Apply:

- `supabase/migrations/20260702_online_license.sql`

This creates:

- `public.licenses`
- `public.license_activations`

## 3. Create users and licenses

Each license row should belong to a Supabase auth user:

- `user_id`
- `license_key`
- `status = 'active'`
- `max_devices`
- `expires_at`

Quick helper:

- run the queries in `supabase/seeds/create_test_license.sql`

## 4. Set secrets for Edge Functions

Required:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

The repo also includes a helper script:

```powershell
./scripts/deploy_supabase_functions.ps1
```

## 5. Deploy functions

Example:

```bash
supabase functions deploy activate-license
supabase functions deploy validate-license
```

For this project the correct hosted values are:

- Project ref: `kcylkaiawiftlkkkltly`
- Supabase URL: `https://kcylkaiawiftlkkkltly.supabase.co`

When deploying to hosted Supabase, the reserved runtime variables such as
`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are already available to Edge
Functions. Do not try to create them again with `supabase secrets set`.

## 5.1 Expected activate flow

1. User signs in with Supabase Auth
2. Flutter sends `license_key + device_id` to `activate-license`
3. The function checks:
   - license exists
   - status is `active`
   - `expires_at` is still valid
   - device count does not exceed `max_devices`
4. If valid:
   - writes or updates `license_activations`
   - returns `valid: true`

## 5.2 Expected validate flow

1. Flutter starts
2. Flutter sends `license_key + device_id` to `validate-license`
3. The function checks:
   - license still exists
   - status is still `active`
   - license has not expired
   - this device already exists in `license_activations`
4. If valid:
   - updates `last_seen_at`
   - returns `valid: true`

## 5.3 Test with Postman

Import:

- `postman/trading-desk-license.postman_collection.json`

Set variables:

- `supabase_url`
- `supabase_anon_key`
- `user_email`
- `user_password`
- `user_access_token`
- `license_key`
- `device_id`
- `device_name`

The collection now includes a `Login User` request that stores
`user_access_token` automatically after a successful sign-in.

## 6. Build Flutter app with Supabase env vars

Pass these at build time:

```bash
flutter build windows --release ^
  --dart-define=SUPABASE_LICENSE_ENABLED=true ^
  --dart-define=SUPABASE_URL=https://kcylkaiawiftlkkkltly.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Optional:

```bash
--dart-define=SUPABASE_LICENSE_ACTIVATE_FUNCTION=activate-license
--dart-define=SUPABASE_LICENSE_VALIDATE_FUNCTION=validate-license
```

## 7. App flow

When enabled:

1. User signs in with email/password
2. User enters a license key
3. Flutter calls Supabase Edge Function
4. Function validates license and device slot
5. Flutter grants a time-limited local backend session
6. Local backend unlocks full API until that session expires

## Notes

- This is a strong starting point, not tamper-proof DRM.
- Never embed the Supabase `service_role` key in the desktop app.
- The desktop app only uses the anon key and authenticated user token.
