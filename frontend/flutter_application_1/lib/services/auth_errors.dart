import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// Turns Auth / network exceptions into short messages safe to show in the UI.
String userFacingAuthError(Object error) {
  if (error is OtpRateLimitException) {
    return error.toString();
  }

  if (error is AuthException) {
    return _fromAuthMessage(error.message, statusCode: error.statusCode);
  }

  final raw = error.toString();
  // AuthRetryableFetchException(message: ..., statusCode: 500)
  final nested = RegExp(
    r'(?:AuthException|AuthApiException|AuthRetryableFetchException)'
    r'\([^)]*(?:message:\s*)?([^;)\n]+)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (nested != null) {
    return _fromAuthMessage(nested.group(1)!.trim());
  }

  return _fromAuthMessage(raw);
}

String _fromAuthMessage(String message, {String? statusCode}) {
  var msg = message
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^AuthException:\s*', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^AuthApiException:\s*', caseSensitive: false), '')
      .replaceFirst(
        RegExp(r'^AuthRetryableFetchException:\s*', caseSensitive: false),
        '',
      )
      .trim();

  // Strip leftover "statusCode: 500" / "code: unexpected_failure" crumbs.
  msg = msg
      .replaceAll(RegExp(r'status\s*code\s*[:=]?\s*\d+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bcode\s*[:=]\s*[\w_]+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\berror_code\s*[:=]\s*[\w_]+', caseSensitive: false), '')
      .replaceAll(RegExp(r'[;,]+\s*$'), '')
      .trim();

  final lower = msg.toLowerCase();
  final code = (statusCode ?? '').trim();

  if (code == '403' ||
      lower.contains('not authorized') ||
      lower.contains('email address not authorized')) {
    return 'This email cannot receive codes yet. '
        'Ask the project owner to finish SMTP setup, or use an authorized address.';
  }

  if (code == '429' ||
      lower.contains('rate limit') ||
      lower.contains('too many requests') ||
      lower.contains('security purposes')) {
    final wait = RegExp(r'(\d+)\s*second').firstMatch(lower);
    if (wait != null) {
      return 'Please wait ${wait.group(1)}s before requesting another code.';
    }
    return 'Too many email attempts. Please wait a few minutes and try again.';
  }

  if (code == '500' ||
      lower.contains('error sending') ||
      lower.contains('magic link') ||
      lower.contains('unexpected failure') ||
      lower.contains('smtp')) {
    return 'We could not send the email right now. '
        'Please try again in a moment.';
  }

  if ((lower.contains('invalid') && lower.contains('otp')) ||
      lower.contains('token has expired') ||
      lower.contains('otp_expired') ||
      lower.contains('invalid token')) {
    return 'That code is invalid or expired. Request a new one and try again.';
  }

  if (lower.contains('network') ||
      lower.contains('socket') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection')) {
    return 'Connection problem. Check your internet and try again.';
  }

  if (lower.contains('cancelled') || lower.contains('canceled')) {
    return 'Sign-in was cancelled.';
  }

  if (lower.contains('google')) {
    return 'Google sign-in could not be completed. Please try again.';
  }

  // Already a clean human sentence we threw ourselves.
  if (msg.length < 160 &&
      !lower.contains('exception') &&
      !RegExp(r'\b\d{3}\b').hasMatch(msg) &&
      !lower.contains('statuscode')) {
    return msg.isEmpty ? 'Something went wrong. Please try again.' : msg;
  }

  return 'Something went wrong. Please try again.';
}
