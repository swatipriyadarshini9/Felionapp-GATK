# Felino auth setup: OTP template + Custom SMTP + Google Sign-In

Project: `dssbjadsxkuddgkajhik`

---

## Why you see 403 and no OTP in Gmail

Without custom SMTP, Supabase **only emails people who are members of your
Supabase organization**. Any other Gmail gets:

- `403` / `Email address not authorized`
- **No message in the inbox**

Fix: set up **custom SMTP** (Resend is the fastest path below).

---

## 1) Magic Link template (must show a 6-digit code)

1. Open [Auth → Email Templates](https://supabase.com/dashboard/project/dssbjadsxkuddgkajhik/auth/templates)
2. Select **Magic Link**
3. Replace the body with:

```html
<h2>Felino clinical access code</h2>
<p>Use this 6-digit code in the Felino app to verify your Gmail:</p>
<p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">
  {{ .Token }}
</p>
<p>This code expires soon. If you did not request access, you can ignore this email.</p>
```

4. Save

---

## 2) Custom SMTP with Resend (do this now)

### A. Create Resend account + API key

1. Sign up at [https://resend.com](https://resend.com)
2. Go to **API Keys** → **Create API Key**
   - Permission: **Full access** (or Sending access on a *verified* domain)
   - Copy the key (starts with `re_…`) — shown once only

### B. Add and verify a sending domain (required to email any Gmail)

1. Resend → **Domains** → **Add Domain**
2. Enter a domain you control (prefer a subdomain), e.g. `mail.yourdomain.com`
3. Add the DNS records Resend shows (SPF, DKIM, optionally DMARC) at your DNS host
4. Wait until status is **Verified** (can take a few minutes to hours)

Until the domain is verified, Resend will reject sends and Supabase will show
`500 Error sending magic link` again.

**No domain yet?** For a quick test only, Resend’s onboarding may allow sending
from `onboarding@resend.dev` to *your own* Resend signup email — not to arbitrary
Gmails. For investor demo / any user Gmail, you need a verified domain.

### C. Paste SMTP into Supabase

1. Open [Auth → SMTP Settings](https://supabase.com/dashboard/project/dssbjadsxkuddgkajhik/auth/smtp)
2. Enable **Custom SMTP**
3. Fill exactly:

| Field | Value |
| --- | --- |
| Sender email | `noreply@mail.yourdomain.com` (must match verified domain) |
| Sender name | `Felino` |
| Host | `smtp.resend.com` |
| Port | `587` |
| Username | `resend` |
| Password | your Resend API key (`re_…`) |

4. Save

### D. Raise email rate limit (after SMTP works)

1. Open [Auth → Rate Limits](https://supabase.com/dashboard/project/dssbjadsxkuddgkajhik/auth/rate-limits)
2. Increase **Rate limit for sending emails** (e.g. 30–100 / hour for demo)

### E. Test

1. In the Felino app: enter a real Gmail → **Send email code**
2. Check inbox (and spam)
3. Email must show a **6-digit code**
4. If it fails: [Auth Logs](https://supabase.com/dashboard/project/dssbjadsxkuddgkajhik/logs/auth-logs) → open the red 500/403 row → read the detailed `error`

**Common SMTP mistakes that caused your earlier 500:**
- Wrong password / restricted API key
- Sender email domain not verified
- Port `465` or `25` instead of `587`
- Extra space in host / username / password

---

## 3) Google Sign-In (do this last)

### A. Google Cloud Console

1. Open [Google Cloud Console](https://console.cloud.google.com/) → create or pick a project
2. **APIs & Services → OAuth consent screen**
   - User type: External
   - App name: `Felino`
   - Support email: yours
   - Save (add your Gmail as a test user while in Testing mode)
3. **APIs & Services → Credentials → Create credentials → OAuth client ID**
   - Application type: **Web application**
   - Name: `Felino Supabase`
   - Authorized JavaScript origins:
     - `http://127.0.0.1:8080`
     - `http://localhost:8080`
   - Authorized redirect URIs:
     - `https://dssbjadsxkuddgkajhik.supabase.co/auth/v1/callback`
4. Copy **Client ID** and **Client Secret**

### B. Supabase Dashboard

1. [Authentication → Providers → Google](https://supabase.com/dashboard/project/dssbjadsxkuddgkajhik/auth/providers)
2. Enable Google
3. Paste Client ID + Client Secret → Save
4. [Authentication → URL Configuration](https://supabase.com/dashboard/project/dssbjadsxkuddgkajhik/auth/url-configuration)
   - Site URL: `http://127.0.0.1:8080`
   - Redirect URLs (add all):
     - `http://127.0.0.1:8080/`
     - `http://127.0.0.1:8080/**`
     - `http://localhost:8080/`
     - `http://localhost:8080/**`

### C. Test in the app

1. Hard refresh http://127.0.0.1:8080 (`Ctrl+Shift+R`)
2. Click **Continue with Google**
3. Complete Google consent → you should land in the dashboard

### D. Optional (Android native later)

Paste the same **Web** Client ID into:

`frontend/flutter_application_1/lib/config/supabase_config.dart` → `googleWebClientId`

Web Google Sign-In works **without** that field as long as the provider is enabled in Supabase.

---

## 4) Restart app after dashboard changes

```powershell
$env:PATH = "C:\Users\Swati\flutter\bin;" + $env:PATH
cd C:\Users\Swati\Downloads\felionapp\frontend\flutter_application_1
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080
```

Then open http://127.0.0.1:8080
