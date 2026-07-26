import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../services/auth_errors.dart';
import '../services/auth_service.dart';
import '../services/local_auth_store.dart';
import 'otp_page.dart';
import 'painters.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.configMissing = false,
    this.onLocalAuthChanged,
  });

  final bool configMissing;
  final Future<void> Function()? onLocalAuthChanged;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final AuthService _auth = AuthService();
  final TextEditingController _emailController = TextEditingController();

  late AnimationController _dnaController;
  late AnimationController _colorController;
  late Animation<Color?> _colorAnimation;

  bool _sendingOtp = false;
  bool _googleLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dnaController =
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
          ..repeat();
    _colorController =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..repeat(reverse: true);
    _colorAnimation = ColorTween(
      begin: const Color(0xFFF0F4FF),
      end: const Color(0xFFF5F0FF),
    ).animate(_colorController);
  }

  @override
  void dispose() {
    _dnaController.dispose();
    _colorController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  bool get _pitchMode =>
      widget.configMissing || SupabaseConfig.useLocalAuth;

  Future<void> _sendOtp() async {
    setState(() {
      _error = null;
      _sendingOtp = true;
    });
    try {
      final email = _emailController.text.trim();
      if (email.isEmpty || !email.contains('@')) {
        throw Exception('Enter a valid email address.');
      }

      if (_pitchMode) {
        await LocalAuthStore.beginEmailOtp(email);
        await _openOtpPage(email);
        return;
      }

      try {
        await _auth.sendEmailOtp(email);
        await _openOtpPage(email);
      } on OtpRateLimitException catch (e) {
        await _openOtpPage(email, initialError: userFacingAuthError(e));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingAuthError(e));
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _openOtpPage(String email, {String? initialError}) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpPage(
          email: email,
          pitchMode: _pitchMode,
          initialError: initialError,
          onVerified: widget.onLocalAuthChanged,
        ),
      ),
    );
    if (widget.onLocalAuthChanged != null) {
      await widget.onLocalAuthChanged!();
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _error = null;
      _googleLoading = true;
    });
    try {
      if (widget.configMissing || !SupabaseConfig.isConfigured) {
        throw Exception(
          'Google Sign-In needs Supabase. '
          'For pitch demo, use Gmail + code ${LocalAuthStore.demoOtpCode}.',
        );
      }
      await _auth.signInWithGoogle();
      // Web OAuth redirects away; native returns here with a session.
      if (widget.onLocalAuthChanged != null) {
        await widget.onLocalAuthChanged!();
      }
    } catch (e) {
      setState(() => _error = userFacingAuthError(e));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_dnaController, _colorAnimation]),
      builder: (context, child) {
        return Scaffold(
          backgroundColor: _colorAnimation.value,
          body: Stack(
            children: [
              CustomPaint(
                painter: DNAPainter(
                  progress: _dnaController.value,
                  color: Colors.blue.withValues(alpha: 0.08),
                ),
                child: Container(),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    width: 400,
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 30,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'FELINO',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Authorized Clinical Access',
                          style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                        ),
                        if (_pitchMode) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF6FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Text(
                              'Demo access: enter any email, tap Continue, '
                              'then use code ${LocalAuthStore.demoOtpCode}. '
                              'No email is sent.',
                              style: const TextStyle(fontSize: 12, height: 1.4),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.mail_outline,
                                color: Colors.blue.shade200),
                            hintText: 'Email address',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _sendingOtp ? null : _sendOtp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade800,
                            minimumSize: const Size(double.infinity, 52),
                          ),
                          child: _sendingOtp
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _pitchMode ? 'CONTINUE' : 'SEND EMAIL CODE',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        if (!_pitchMode) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                  child: Divider(color: Colors.grey.shade300)),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('or',
                                    style: TextStyle(color: Colors.blueGrey)),
                              ),
                              Expanded(
                                  child: Divider(color: Colors.grey.shade300)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _googleLoading ? null : _googleSignIn,
                            icon: _googleLoading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.g_mobiledata, size: 28),
                            label: const Text('Continue with Google'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          _pitchMode
                              ? 'Access code: ${LocalAuthStore.demoOtpCode}'
                              : 'First-time users verify with email OTP. '
                                  'Returning users can use Google Sign-In.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey.shade400,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
