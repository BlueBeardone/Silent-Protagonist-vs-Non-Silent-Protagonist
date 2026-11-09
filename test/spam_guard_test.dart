import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/spam_guard.dart';

void main() {
  test('rejects a non-empty honeypot', () async {
    final guard = SpamGuard();
    expect(
      await guard.check(
        honeypot: 'https://spam.example',
        turnstileToken: null,
        remoteIp: null,
      ),
      isNotNull,
    );
  });

  test('accepts an empty honeypot when Turnstile is disabled', () async {
    final guard = SpamGuard();
    expect(
      await guard.check(
        honeypot: '',
        turnstileToken: null,
        remoteIp: null,
      ),
      isNull,
    );
  });

  test('requires a token when Turnstile is enabled', () async {
    final guard = SpamGuard(turnstileSecret: 'secret');
    expect(
      await guard.check(
        honeypot: '',
        turnstileToken: null,
        remoteIp: null,
      ),
      isNotNull,
    );
  });

  test('accepts a valid Turnstile token', () async {
    final guard = SpamGuard(
      turnstileSecret: 'secret',
      client: MockClient((request) async {
        expect(request.url.host, 'challenges.cloudflare.com');
        expect(request.body, contains('secret'));
        expect(request.body, contains('token'));
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );
    expect(
      await guard.check(
        honeypot: '',
        turnstileToken: 'token',
        remoteIp: '1.2.3.4',
      ),
      isNull,
    );
  });

  test('rejects a failed Turnstile verification', () async {
    final guard = SpamGuard(
      turnstileSecret: 'secret',
      client: MockClient((request) async {
        return http.Response(jsonEncode({'success': false}), 200);
      }),
    );
    expect(
      await guard.check(
        honeypot: '',
        turnstileToken: 'token',
        remoteIp: null,
      ),
      isNotNull,
    );
  });
}
