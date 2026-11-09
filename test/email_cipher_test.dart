import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/logic/email_cipher.dart';

void main() {
  final key = base64Encode(List<int>.filled(32, 1));

  test('round-trips an email', () async {
    final cipher = EmailCipher(key: key);
    final encrypted = await cipher.encrypt('barry@gmail.com');
    expect(encrypted, isNot(contains('barry@gmail.com')));
    expect(await cipher.decrypt(encrypted), 'barry@gmail.com');
  });

  test('uses a different nonce for each encryption', () async {
    final cipher = EmailCipher(key: key);
    final first = await cipher.encrypt('barry@gmail.com');
    final second = await cipher.encrypt('barry@gmail.com');
    expect(first, isNot(second));
  });
}
