import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local pitch-mode session when Supabase keys are not configured.
/// Demo OTP for investors: [demoOtpCode]
class LocalAuthStore {
  LocalAuthStore._();

  static const demoOtpCode = '246810';
  static const _emailKey = 'felino_demo_email';
  static const _verifiedKey = 'felino_demo_verified';
  static const _pendingEmailKey = 'felino_demo_pending_email';

  static Future<bool> get isVerified async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_verifiedKey) ?? false;
  }

  static Future<String?> get email async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  static Future<String?> get pendingEmail async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingEmailKey);
  }

  static Future<void> beginEmailOtp(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingEmailKey, email.trim().toLowerCase());
  }

  static Future<bool> verifyOtp(String email, String token) async {
    final code = token.trim();
    // Accept the published demo code, or any 6-digit code in debug builds.
    final ok = code == demoOtpCode ||
        (kDebugMode && RegExp(r'^\d{6}$').hasMatch(code));
    if (!ok) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email.trim().toLowerCase());
    await prefs.setBool(_verifiedKey, true);
    await prefs.remove(_pendingEmailKey);
    return true;
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_verifiedKey);
    await prefs.remove(_pendingEmailKey);
  }
}
