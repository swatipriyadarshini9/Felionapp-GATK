import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/supabase_config.dart';
import '../services/auth_errors.dart';
import '../services/auth_service.dart';
import '../services/local_auth_store.dart';

class OtpPage extends StatefulWidget {
  const OtpPage({
    super.key,
    required this.email,
    this.onVerified,
    this.pitchMode = false,
    this.initialError,
  });

  final String email;
  final Future<void> Function()? onVerified;
  final bool pitchMode;

  /// Surfaced immediately, e.g. when the send was throttled before landing here.
  final String? initialError;

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final AuthService _auth = AuthService();
  final TextEditingController _codeController = TextEditingController();
  bool _verifying = false;
  bool _resending = false;
  String? _error;
  String? _notice;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  bool get _usePitchAuth =>
      widget.pitchMode || SupabaseConfig.useLocalAuth;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialError;
    _error = seed == null ? null : userFacingAuthError(seed);
    if (!_usePitchAuth) _syncCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _syncCooldown() async {
    final remaining = await _auth.otpCooldownRemaining(widget.email);
    if (!mounted) return;
    _startCooldown(remaining);
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds);
    if (seconds <= 0) return;

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown = _cooldown - 1);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      if (_usePitchAuth) {
        final ok = await LocalAuthStore.verifyOtp(
          widget.email,
          _codeController.text,
        );
        if (!ok) {
          throw Exception(
            'Invalid code. Use ${LocalAuthStore.demoOtpCode} for this demo.',
          );
        }
      } else {
        await _auth.verifyEmailOtp(
          email: widget.email,
          token: _codeController.text,
        );
      }
      if (widget.onVerified != null) {
        await widget.onVerified!();
      }
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() => _error = userFacingAuthError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0) return;

    setState(() {
      _error = null;
      _notice = null;
      _resending = true;
    });
    try {
      if (_usePitchAuth) {
        await LocalAuthStore.beginEmailOtp(widget.email);
        if (!mounted) return;
        setState(() => _notice =
            'Demo access code remains ${LocalAuthStore.demoOtpCode}.');
      } else {
        await _auth.sendEmailOtp(widget.email);
        if (!mounted) return;
        setState(() => _notice = 'A new code was sent to ${widget.email}.');
        _startCooldown(AuthService.otpResendCooldown.inSeconds);
      }
    } on OtpRateLimitException catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingAuthError(e));
      _startCooldown(e.retryAfterSeconds);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingAuthError(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  String get _resendLabel {
    if (_cooldown > 0) return 'Resend code in ${_cooldown}s';
    return 'Resend code';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Verify email', style: TextStyle(fontSize: 16)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mark_email_read_outlined,
                    size: 48, color: Colors.blue.shade700),
                const SizedBox(height: 16),
                Text(
                  _usePitchAuth
                      ? 'Enter the clinical access code for'
                      : 'Enter the 6-digit code emailed to',
                  style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.email.isEmpty ? 'your Gmail' : widget.email,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
                if (_usePitchAuth) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Code: ${LocalAuthStore.demoOtpCode}',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Text(
                    'Enter the 6-digit code from the email. '
                    'It may take a minute to arrive — check your spam folder too.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blueGrey.shade500,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.text,
                  textAlign: TextAlign.center,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    letterSpacing: 2,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(500),
                  ],
                  decoration: InputDecoration(
                    hintText: '6-digit code or paste link',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _verifying ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    minimumSize: const Size(double.infinity, 52),
                  ),
                  child: _verifying
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'VERIFY & CONTINUE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: (_resending || _cooldown > 0) ? null : _resend,
                  child: _resending
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_resendLabel),
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _notice!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
