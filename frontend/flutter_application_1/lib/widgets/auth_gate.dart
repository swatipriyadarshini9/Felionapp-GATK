import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../screens/analysis_dashboard.dart';
import '../screens/login_page.dart';
import '../screens/otp_page.dart';
import '../services/auth_service.dart';
import '../services/local_auth_store.dart';

/// Routes by session + first-time OTP verification status.
/// Pitch demo auth uses a local access code (no SMTP / Google spend).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService();
  bool _checking = true;
  bool _otpVerified = false;
  bool _localSession = false;
  Session? _session;
  String _otpEmail = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
    if (!SupabaseConfig.useLocalAuth && SupabaseConfig.isConfigured) {
      _auth.onAuthStateChange.listen((data) async {
        if (!mounted) return;
        _session = data.session;
        if (_session != null) {
          try {
            await _auth.markOtpVerified();
          } catch (_) {}
        }
        await _refreshVerification();
      });
    }
  }

  Future<void> _bootstrap() async {
    if (SupabaseConfig.useLocalAuth) {
      final verified = await LocalAuthStore.isVerified;
      final email = await LocalAuthStore.email;
      if (!mounted) return;
      setState(() {
        _localSession = verified;
        _otpVerified = verified;
        _otpEmail = email ?? '';
        _checking = false;
      });
      return;
    }

    _session = _auth.currentSession;
    if (_session != null) {
      try {
        await _auth.markOtpVerified();
      } catch (_) {}
    }
    await _refreshVerification();
  }

  Future<void> _refreshVerification() async {
    if (!mounted) return;
    setState(() => _checking = true);
    try {
      if (SupabaseConfig.useLocalAuth) {
        final verified = await LocalAuthStore.isVerified;
        final email = await LocalAuthStore.email;
        if (!mounted) return;
        setState(() {
          _localSession = verified;
          _otpVerified = verified;
          _otpEmail = email ?? '';
          _checking = false;
        });
        return;
      }

      _session = _auth.currentSession;
      final verified =
          _session == null ? false : await _auth.isOtpVerified();
      if (!mounted) return;
      setState(() {
        _otpVerified = verified;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _otpVerified = _session != null;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (SupabaseConfig.useLocalAuth) {
      if (!_localSession || !_otpVerified) {
        return LoginPage(
          configMissing: true,
          onLocalAuthChanged: _refreshVerification,
        );
      }
      return const AnalysisDashboard();
    }

    if (_session == null) {
      return LoginPage(onLocalAuthChanged: _refreshVerification);
    }

    if (!_otpVerified) {
      return OtpPage(
        email: _session!.user.email ?? _otpEmail,
        onVerified: _refreshVerification,
      );
    }

    return const AnalysisDashboard();
  }
}
