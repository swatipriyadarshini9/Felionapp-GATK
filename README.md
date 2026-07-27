# Felino Genomics

Clinical genomics demo: Flutter client + FastAPI backend + Supabase auth/RLS scaffolding.

## Structure

- `frontend/flutter_application_1` — Flutter app (Circos plot, upload, auth gate)
- `backend` — FastAPI VCF/BAM analysis + Gemini interpretation
- `supabase` — SQL migration, email template, setup notes


## Quick start (demo)

### Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env   # if present; else create .env with GEMINI_API_KEY=
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

### Flutter web

```powershell
$env:PATH = "C:\Users\Swati\flutter\bin;" + $env:PATH
cd frontend\flutter_application_1
flutter pub get
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080
```

Open http://127.0.0.1:8080

### Auth notes

- Live email OTP needs Supabase Magic Link template with `{{ .Token }}` and (for any Gmail) custom SMTP — see `supabase/AUTH_FIX.md`.
- For a no-cost pitch login, set `usePitchDemoAuth = true` in `lib/config/supabase_config.dart` and use access code `246810`.
- Google login: Create a Google Cloud OAuth client, add Client ID/Secret in Supabase, then users can sign in with Google.
- Email OTP: Verify a domain in your email provider (DNS), configure SMTP in Supabase, then send login codes.
- To test the app on various Android devices and configurations use Android Studio.

## Demo
https://github.com/user-attachments/assets/ab40380f-61d2-4f0f-b7ca-47f747601782

## Secrets

Do **not** commit:

- `backend/.env` (Gemini API key)
- Supabase **service_role** / secret keys

The Flutter **anon** key is public-client config and must be protected by Supabase RLS.
