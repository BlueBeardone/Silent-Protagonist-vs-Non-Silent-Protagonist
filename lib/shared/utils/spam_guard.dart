import 'dart:convert';

import 'package:http/http.dart' as http;

/// A small anti-spam check for the public comment endpoint.
///
/// Two layers:
///
/// 1. **Honeypot** — a hidden `website` field. A real browser leaves it empty;
///    a bot that fills every field will set it. A non-empty value is rejected.
/// 2. **Optional Cloudflare Turnstile** — when [turnstileSecret] is set, the
///    client must send a `turnstileToken` and the server verifies it with
///    Cloudflare. When the secret is absent, Turnstile is skipped.
class SpamGuard {
  SpamGuard({
    this.turnstileSecret,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// The Turnstile secret. Empty or null disables Turnstile.
  final String? turnstileSecret;

  final http.Client _client;

  /// Whether Turnstile verification is enabled.
  bool get requiresTurnstile =>
      turnstileSecret != null && turnstileSecret!.trim().isNotEmpty;

  /// Returns `null` when the request is acceptable, else a reason to reject it.
  ///
  /// [remoteIp] is passed to Turnstile as `remoteip`; it is optional.
  Future<String?> check({
    required String? honeypot,
    required String? turnstileToken,
    required String? remoteIp,
  }) async {
    if (honeypot != null && honeypot.trim().isNotEmpty) {
      return 'Rejected.';
    }
    if (!requiresTurnstile) return null;

    final token = turnstileToken?.trim();
    if (token == null || token.isEmpty) {
      return 'Missing Turnstile token.';
    }

    try {
      final response = await _client
          .post(
            Uri.parse(
              'https://challenges.cloudflare.com/turnstile/v0/siteverify',
            ),
            headers: {'content-type': 'application/x-www-form-urlencoded'},
            body: {
              'secret': turnstileSecret!.trim(),
              'response': token,
              if (remoteIp != null && remoteIp.isNotEmpty) 'remoteip': remoteIp,
            },
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return 'Turnstile verification failed.';
      }
      final body = jsonDecode(response.body);
      if (body is Map && body['success'] == true) return null;
      return 'Turnstile verification failed.';
    } catch (_) {
      // A network failure or a malformed response must not let the request
      // through; fail closed.
      return 'Turnstile verification failed.';
    }
  }
}
