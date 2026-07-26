# Felino Supabase + Google Auth Setup

Complete these steps once, then paste keys into
`frontend/flutter_application_1/lib/config/supabase_config.dart`.

## 1. Create a Supabase project

1. Go to [https://supabase.com/dashboard](https://supabase.com/dashboard) and create a project.
2. Wait until the project is ready.
3. Open **Project Settings → API**.
4. Copy:
   - **Project URL** → `supabaseUrl`
   - **anon public** key → `supabaseAnonKey`

## 2. Run the SQL migration

1. Open **SQL Editor → New query**.
2. Paste the contents of [`migrations/001_init.sql`](migrations/001_init.sql).
3. Click **Run**.

## 3. Enable Email OTP (6-digit codes)

**Critical:** emails are sent with the **Magic Link** template. If that template
has no `{{ .Token }}`, Gmail only gets a link and the app has no code to enter.

1. Open **Authentication → Providers → Email** → enable Email.
2. Open **Authentication → Email Templates → Magic Link**.
3. Paste the HTML from [`email_templates/magic_link.html`](email_templates/magic_link.html)
   (must include `{{ .Token }}`) and Save.
4. Full checklist: [`AUTH_FIX.md`](AUTH_FIX.md).

## 4. Enable Google Sign-In

### Google Cloud Console

1. Create (or open) a Google Cloud project.
2. **APIs & Services → OAuth consent screen** — External; add your Gmail as a test user.
3. **Credentials → Create credentials → OAuth client ID** → **Web application**:
   - Origins: `http://127.0.0.1:8080`, `http://localhost:8080`
   - Redirect URI: `https://dssbjadsxkuddgkajhik.supabase.co/auth/v1/callback`
   - Copy **Client ID** + **Client Secret**

### Supabase Dashboard

1. **Authentication → Providers → Google** → Enable → paste Client ID + Secret → Save.
2. **Authentication → URL Configuration**:
   - Site URL: `http://127.0.0.1:8080`
   - Redirect URLs: `http://127.0.0.1:8080/**`, `http://localhost:8080/**`
3. Optional for Android ID-token: paste Web Client ID into Flutter `googleWebClientId`.
   Web Google login works via Supabase OAuth without that Flutter field.

## 5. Paste into Flutter

Edit `frontend/flutter_application_1/lib/config/supabase_config.dart`:

```dart
static const String supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
static const String supabaseAnonKey = 'YOUR_ANON_KEY';
static const String googleWebClientId = 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';
```

## 6. Android Studio demo

```bash
cd frontend/flutter_application_1
flutter pub get
flutter run
```

**Flow to verify**

1. First-time: enter Gmail → **Send code** → enter OTP from inbox → dashboard.
2. Sign out → **Continue with Google** (returning path; OTP skipped if already verified).
3. Use **Load demo variants** to render Circos without the GATK backend.

## Notes

- Never commit the **service_role** key.
- Until real keys are pasted, OTP/Google calls will fail; Circos + demo variants still work after you temporarily bypass auth for local UI checks (not recommended for shared builds).
