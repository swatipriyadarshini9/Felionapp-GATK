/// Live Supabase client config (URL + anon/publishable only).
/// NEVER put SUPABASE_SECRET_KEY / service_role in this Flutter app.
/// See `supabase/SETUP.md`.
class SupabaseConfig {
  SupabaseConfig._();

  /// Pitch / investor demo: local access code, no email SMTP, no Google paywall.
  /// Set to `true` to use the local demo code instead of live email OTP.
  static const bool usePitchDemoAuth = false;

  static const String supabaseUrl = 'https://dssbjadsxkuddgkajhik.supabase.co';

  /// Legacy JWT anon key (works with Auth + RLS from the Flutter client).
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRzc2JqYWRzeGt1ZGRna2FqaGlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5NzQxNTYsImV4cCI6MjEwMDU1MDE1Nn0.UheT_7DFW0WqGpA042sJmQvBoxFM6B_AfYabKDXQmG4';

  /// Newer publishable key from the dashboard (optional / reference).
  static const String supabasePublishableKey =
      'sb_publishable_qZK6To3FaCqNix55Gmd2mw_G8EaZGrW';

  /// Google Cloud OAuth **Web** client ID (Android ID-token flow).
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: 'YOUR_GOOGLE_WEB_CLIENT_ID',
  );

  static bool get isConfigured {
    final url = supabaseUrl.trim();
    final key = supabaseAnonKey.trim();
    if (url.isEmpty || key.isEmpty) return false;
    if (url.contains('YOUR_') || key.contains('YOUR_')) return false;
    if (!url.startsWith('http')) return false;
    return true;
  }

  /// True when the app should use local demo login (no paid email/Google).
  static bool get useLocalAuth => usePitchDemoAuth || !isConfigured;

  static bool get isGoogleConfigured {
    if (usePitchDemoAuth) return false;
    final id = googleWebClientId.trim();
    return id.isNotEmpty && !id.contains('YOUR_');
  }
}
