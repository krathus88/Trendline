# Setup: Supabase and Discord sign-in

One-time setup for the cloud side of Trendline. Do the steps in order. Nothing here goes in git except the migration, which is already in `supabase/migrations/`.

## 1. Create the Supabase project

1. At <https://supabase.com/dashboard>, create a new project.
2. **Region: London (eu-west-2).** Health data is UK GDPR special category data and stays in the UK.
3. Save the database password in your password manager. The app never needs it.

## 2. Apply the database migrations

With the Supabase CLI (recommended; it applies every migration in order and tracks which have run):

```sh
npx supabase@3.3.0 login
npx supabase@3.3.0 link --project-ref <your-project-ref>
npx supabase@3.3.0 db push --remote
```

(Without `--remote`, `db push` targets a local test database, not your project.)

Or by hand: in **SQL Editor**, run each file in `supabase/migrations/` in filename order.

Then check **Settings > API (Data API) > Exposed schemas**. It must list only `public` (and `graphql_public`), **not `private`**.

## 3. Turn on the allowlist hook

1. Go to **Authentication > Hooks** and add a **Before User Created** hook.
2. Type: **Postgres**. Schema: `private`. Function: `check_allowlist`.
3. Save.

## 4. Create the Discord application

1. At <https://discord.com/developers/applications>, click **New Application** and name it "Trendline".
2. Under **OAuth2**, copy the **Client ID** and reset/copy the **Client Secret**. Keep the secret in your password manager; it goes only into Supabase, never into the app or repo.
3. Under **OAuth2 > Redirects**, add:
   `https://<your-project-ref>.supabase.co/auth/v1/callback`
   (your project ref is in the project URL.)

## 5. Connect Discord to Supabase

1. **Authentication > Sign In / Providers > Discord**: enable it, paste the Client ID and Client Secret, and save.
2. Optional but recommended: disable the **Email** provider. The hook already rejects it, but turning it off removes it entirely.
3. **Authentication > URL Configuration > Redirect URLs**: add
   `com.krathus.trendline://login-callback`

## 6. Add people to the allowlist

1. In Discord: **Settings > Advanced > Developer Mode** on. Then right-click a user (or your own avatar) and choose **Copy User ID**.
2. In the SQL Editor:

   ```sql
   insert into private.allowed_users (discord_id, note)
   values ('YOUR_DISCORD_ID', 'me');
   ```

Remove someone with `delete from private.allowed_users where discord_id = '…';`. Removing them from the list stops new sign-ups only. To cut off an existing account, also delete the user under **Authentication > Users**.

## 7. Configure the app

1. In the dashboard: **Settings > API Keys**. Copy the **Project URL** and the **publishable key** (`sb_publishable_…`). **Never** use the secret / `service_role` key.
2. Copy `dart_defines.example.json` to `dart_defines.json` (git-ignored) and fill in the URL and key.
3. Run:

   ```sh
   flutter run --dart-define-from-file=dart_defines.json
   ```

## 8. First sign-in check

Sign in with your listed Discord account.

- **It works:** done.
- **"Not on the invite list" even though you're listed:** the hook couldn't find your Discord ID where it expected. Check **Authentication > Logs** for the hook's input, find where the Discord ID sits in it, and add that location to the lookup in `private.check_allowlist` (in a new migration).

## 9. Health Connect (optional, Android)

Trendline can import weight, body fat and lean mass that your scale's app saves to Health Connect.

1. In your scale's app, turn on syncing to Health Connect (it's usually under its settings or connected apps).
2. In Trendline: **Settings > Health Connect > Connect**, then allow weight (and body fat and lean mass if your scale measures them) and access to past data.

Trendline only reads from Health Connect. Withdraw access at any time from **Settings > Health Connect > Disconnect** or from Health Connect itself; readings already imported stay in your account.

## 10. Windows desktop (optional)

The same app runs on Windows, without Health Connect and barcode scanning (search and manual entry still work). It uses the same Supabase project and the same redirect URL, so there's nothing to change in the dashboard.

1. Turn on **Developer Mode** (Settings > System > For developers). Flutter needs it to build apps with plugins.
2. Install Visual Studio with the **Desktop development with C++** workload.
3. Run or build:

   ```sh
   flutter run -d windows --dart-define-from-file=dart_defines.json
   flutter build windows --release --dart-define-from-file=dart_defines.json
   ```

   The release app is in `build\windows\x64\runner\Release\` (copy the whole folder, not just the `.exe`).

Each time it starts, the app registers the `com.krathus.trendline://` link for your Windows user (under `HKCU\Software\Classes`, no admin rights needed), so Discord sign-in in the browser can return to it. The most recently started copy of the app owns the link: if you switch between a debug and a release build, sign in from the one you started last. Only one window runs at a time; opening the app again brings the running one to the front.

To remove the link registration after deleting the app:

```sh
reg delete "HKCU\Software\Classes\com.krathus.trendline" /f
```
