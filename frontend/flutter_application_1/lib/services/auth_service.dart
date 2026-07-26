import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Raised when Supabase throttles OTP emails (one per 60s per address,
/// plus an hourly cap on the built-in SMTP service).
class OtpRateLimitException implements Exception {
  OtpRateLimitException({
    required this.retryAfterSeconds,
    this.serverMessage,
  });

  final int retryAfterSeconds;
  final String? serverMessage;

  bool get isHourlyCap =>
      (serverMessage ?? '').toLowerCase().contains('email rate limit');

  @override
  String toString() {
    if (isHourlyCap) {
      return 'Email sending limit reached. Please wait a while, or use a code '
          'you already received.';
    }
    return 'Please wait ${retryAfterSeconds}s before requesting another code.';
  }
}

/// Dual auth:
/// • Live Supabase (email OTP + Google) when keys are configured
/// • Pitch / local demo auth when keys are missing (OTP code: 246810)
class AuthService {
  AuthService({SupabaseClient? client}) : _overrideClient = client;

  final SupabaseClient? _overrideClient;

  static const demoOtpCode = '246810';
  static const _prefEmail = 'felino_demo_email';
  static const _prefVerified = 'felino_demo_verified';
  static const _prefPendingEmail = 'felino_demo_pending_email';

  bool get isLive => SupabaseConfig.isConfigured && !SupabaseConfig.usePitchDemoAuth;

  /// Redirect after magic-link / Google OAuth (web localhost demo).
  static String get authRedirectTo {
    if (kIsWeb) {
      return Uri.base.origin.endsWith('/')
          ? Uri.base.origin
          : '${Uri.base.origin}/';
    }
    return 'io.supabase.felino://login-callback/';
  }

  SupabaseClient get _client {
    final override = _overrideClient;
    if (override != null) return override;
    if (!SupabaseConfig.isConfigured) {
      throw Exception('Supabase is not configured.');
    }
    return Supabase.instance.client;
  }

  Session? get currentSession {
    if (!isLive && _overrideClient == null) return null;
    return _client.auth.currentSession;
  }

  User? get currentUser {
    if (!isLive && _overrideClient == null) return null;
    return _client.auth.currentUser;
  }

  Stream<AuthState> get onAuthStateChange {
    if (!isLive && _overrideClient == null) {
      return const Stream.empty();
    }
    return _client.auth.onAuthStateChange;
  }

  Future<bool> hasDemoSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefVerified) == true &&
        (prefs.getString(_prefEmail)?.isNotEmpty ?? false);
  }

  Future<String?> demoEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefEmail);
  }

  /// Supabase allows one OTP email per address every 60 seconds.
  static const otpResendCooldown = Duration(seconds: 60);

  /// Seconds still remaining before another code can be requested.
  Future<int> otpCooldownRemaining(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_prefLastSentKey(email));
    if (last == null) return 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    final remaining = otpResendCooldown.inMilliseconds - elapsed;
    return remaining <= 0 ? 0 : (remaining / 1000).ceil();
  }

  static String _prefLastSentKey(String email) =>
      'felino_otp_last_sent_${email.trim().toLowerCase()}';

  static String _prefUserVerifiedKey(String userId) =>
      'felino_user_otp_verified_$userId';

  Future<void> sendEmailOtp(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      throw Exception('Enter a valid Gmail address.');
    }

    if (!isLive) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefPendingEmail, trimmed);
      return;
    }

    final waitFor = await otpCooldownRemaining(trimmed);
    if (waitFor > 0) {
      throw OtpRateLimitException(retryAfterSeconds: waitFor);
    }

    final prefs = await SharedPreferences.getInstance();
    try {
      // Sends email using the Magic Link template.
      // Template MUST include {{ .Token }} for the 6-digit code (see SETUP.md).
      await _client.auth.signInWithOtp(
        email: trimmed,
        shouldCreateUser: true,
        emailRedirectTo: authRedirectTo,
      );
      await prefs.setInt(
        _prefLastSentKey(trimmed),
        DateTime.now().millisecondsSinceEpoch,
      );
    } on AuthException catch (e) {
      if (_isRateLimit(e)) {
        final hourlyCap = e.message.toLowerCase().contains('email rate limit');
        final wait = _retryAfterFrom(e) ??
            (hourlyCap ? 300 : otpResendCooldown.inSeconds);
        await prefs.setInt(
          _prefLastSentKey(trimmed),
          DateTime.now().millisecondsSinceEpoch +
              (wait - otpResendCooldown.inSeconds) * 1000,
        );
        throw OtpRateLimitException(
          retryAfterSeconds: wait,
          serverMessage: e.message,
        );
      }
      rethrow;
    }
  }

  bool _isRateLimit(AuthException e) {
    final msg = e.message.toLowerCase();
    return e.statusCode == '429' ||
        msg.contains('rate limit') ||
        msg.contains('too many requests') ||
        msg.contains('security purposes');
  }

  int? _retryAfterFrom(AuthException e) {
    final match = RegExp(r'(\d+)\s*second').firstMatch(e.message);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }

  /// Accepts a 6-digit code OR a pasted magic-link URL from the email.
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    var raw = token.trim();

    if (!isLive) {
      if (raw != demoOtpCode) {
        throw Exception(
          'Invalid code. For this pitch demo use $demoOtpCode',
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefEmail, trimmedEmail);
      await prefs.setBool(_prefVerified, true);
      await prefs.remove(_prefPendingEmail);
      return;
    }

    // User pasted the whole magic link instead of typing the digits.
    final fromUrl = _extractOtpFromInput(raw);
    if (fromUrl != null) raw = fromUrl;

    if (!RegExp(r'^\d{6,8}$').hasMatch(raw)) {
      throw Exception(
        'Enter the 6-digit code from your email (e.g. 483921), '
        'or paste the full magic link. '
        'If the email has no digits, the Magic Link template must include '
        '{{ .Token }} — then request a new code.',
      );
    }

    AuthException? lastError;
    // Prefer email (current), then deprecated magiclink/signup for older projects.
    for (final type in const [
      OtpType.email,
      OtpType.magiclink,
      OtpType.signup,
    ]) {
      try {
        final res = await _client.auth.verifyOTP(
          email: trimmedEmail,
          token: raw,
          type: type,
        );
        if (res.session != null || res.user != null || currentSession != null) {
          await markOtpVerified();
          return;
        }
      } on AuthException catch (e) {
        lastError = e;
      }
    }

    throw Exception(
      lastError?.message ??
          'Invalid or expired code. Request a new one, or wait if you hit the email rate limit.',
    );
  }

  /// Pull a 6–8 digit OTP out of typed input or a magic-link URL.
  String? _extractOtpFromInput(String input) {
    final digitsOnly = input.replaceAll(RegExp(r'\s'), '');
    if (RegExp(r'^\d{6,8}$').hasMatch(digitsOnly)) return digitsOnly;

    final uri = Uri.tryParse(input);
    if (uri == null) return null;

    for (final key in const ['token', 'otp', 'code']) {
      final v = uri.queryParameters[key];
      if (v != null && RegExp(r'^\d{6,8}$').hasMatch(v)) return v;
    }

    // Some links put the code in the fragment: #access_token=...&token=123456
    final frag = uri.fragment;
    if (frag.isNotEmpty) {
      final params = Uri.splitQueryString(frag);
      for (final key in const ['token', 'otp', 'code']) {
        final v = params[key];
        if (v != null && RegExp(r'^\d{6,8}$').hasMatch(v)) return v;
      }
    }

    // Last resort: any standalone 6-digit run in the string.
    final match = RegExp(r'(?<!\d)(\d{6})(?!\d)').firstMatch(input);
    return match?.group(1);
  }

  Future<void> signInWithGoogle() async {
    if (!isLive) {
      throw Exception(
        'Google Sign-In needs Supabase keys. Use email + demo code $demoOtpCode for now.',
      );
    }

    if (kIsWeb || !SupabaseConfig.isGoogleConfigured) {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: authRedirectTo,
        authScreenLaunchMode: LaunchMode.platformDefault,
      );
      if (!launched) {
        throw Exception(
          'Could not open Google sign-in. In Supabase Dashboard enable '
          'Authentication → Providers → Google and add Client ID + Secret. '
          'Also add $authRedirectTo under Authentication → URL Configuration → Redirect URLs.',
        );
      }
      return;
    }

    final googleSignIn = GoogleSignIn(
      serverClientId: SupabaseConfig.googleWebClientId,
      scopes: const ['email', 'profile'],
    );

    final account = await googleSignIn.signIn();
    if (account == null) {
      throw Exception('Google sign-in was cancelled.');
    }

    final googleAuth = await account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw Exception('Failed to obtain Google ID token.');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
    await markOtpVerified();
  }

  Future<void> _ensureProfileRow() async {
    final user = currentUser;
    if (user == null) return;
    try {
      await _client.from('profiles').upsert({
        'id': user.id,
        'email': user.email,
      });
    } catch (_) {
      // Profiles table may be missing if SQL migration was not run.
      // Auth still works via session + local verification flag.
    }
  }

  Future<bool> isOtpVerified() async {
    if (!isLive) {
      return hasDemoSession();
    }
    final user = currentUser;
    if (user == null) return false;

    // Local backup — survives missing profiles table / RLS failures.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefUserVerifiedKey(user.id)) == true) {
      return true;
    }

    // Google already verified the email.
    final identities = user.identities ?? [];
    final viaGoogle = identities.any((i) => i.provider == 'google');
    if (viaGoogle) {
      await markOtpVerified();
      return true;
    }

    // Completing email OTP / magic link already proves ownership.
    // email_confirmed_at is set after a successful verifyOTP or link click.
    if (user.emailConfirmedAt != null && user.emailConfirmedAt!.isNotEmpty) {
      await markOtpVerified();
      return true;
    }

    try {
      final row = await _client
          .from('profiles')
          .select('otp_verified_at')
          .eq('id', user.id)
          .maybeSingle();
      if (row != null && row['otp_verified_at'] != null) {
        await prefs.setBool(_prefUserVerifiedKey(user.id), true);
        return true;
      }
    } catch (_) {
      // Table missing / RLS — fall through.
    }

    return false;
  }

  Future<void> markOtpVerified() async {
    final user = currentUser;
    if (user == null) return;

    // Always persist locally so AuthGate cannot get stuck.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefUserVerifiedKey(user.id), true);

    try {
      await _ensureProfileRow();
      await _client.from('profiles').update({
        'otp_verified_at': DateTime.now().toUtc().toIso8601String(),
        'email': user.email,
      }).eq('id', user.id);
    } catch (_) {
      // Non-fatal: local flag is enough to enter the app.
    }
  }

  Future<void> signOut() async {
    if (!isLive) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefEmail);
      await prefs.remove(_prefVerified);
      await prefs.remove(_prefPendingEmail);
      return;
    }
    final user = currentUser;
    try {
      if (SupabaseConfig.isGoogleConfigured) {
        final googleSignIn = GoogleSignIn(
          serverClientId: SupabaseConfig.googleWebClientId,
        );
        await googleSignIn.signOut();
      }
    } catch (_) {
      // ignore
    }
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefUserVerifiedKey(user.id));
    }
    await _client.auth.signOut();
  }
}

/// Resolve API host: Android emulator → 10.0.2.2, else localhost.
String apiBaseUrl() {
  if (kIsWeb) return 'http://127.0.0.1:8000';
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
  } catch (_) {
    // fall through
  }
  return 'http://127.0.0.1:8000';
}
