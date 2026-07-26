# Android Studio / emulator demo

## Pitch demo auth (works without Supabase keys)

1. Enter any Gmail
2. Tap **SEND EMAIL CODE**
3. Enter access code **`246810`**
4. Dashboard unlocks

To enable live Supabase OTP later, paste Project URL + anon key into
`lib/config/supabase_config.dart` (see `supabase/SETUP.md`).

## Backend (required for upload)

Keep this running in a terminal:

```powershell
cd C:\Users\Swati\Downloads\felionapp\backend
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Health check: http://127.0.0.1:8000/health

- **VCF upload** → parses chr10 CYP2C19 calls directly
- **BAM/SAM upload** → curated chr10 panel when GATK is not installed (investor-safe)
- **LOAD DEMO VARIANTS** → same chr10 panel via API when backend is up

## Run Flutter

```powershell
$env:PATH = "C:\Users\Swati\flutter\bin;" + $env:PATH
cd C:\Users\Swati\Downloads\felionapp\frontend\flutter_application_1
flutter run
```

Already-built APK:

`build/app/outputs/flutter-apk/app-debug.apk`
