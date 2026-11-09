import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encrypts email addresses at rest with AES-GCM.
///
/// The key is a base64-encoded 32-byte secret supplied by the operator. The
/// encrypted form is a single base64 string: `nonce || ciphertext || mac`.
///
/// The full email is still needed for the research follow-up, so it is stored
/// encrypted rather than hashed. The API still only ever returns the masked
/// form.
class EmailCipher {
  EmailCipher({required String key})
      : _algorithm = AesGcm.with256bits(),
        _key = SecretKey(base64Decode(key));

  final AesGcm _algorithm;
  final SecretKey _key;

  /// Encrypts [email] into a base64 string.
  Future<String> encrypt(String email) async {
    final nonce = _algorithm.newNonce();
    final secretBox = await _algorithm.encrypt(
      utf8.encode(email),
      secretKey: _key,
      nonce: nonce,
    );
    final bytes = Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64Encode(bytes);
  }

  /// Decrypts a value produced by [encrypt].
  Future<String> decrypt(String encoded) async {
    final bytes = base64Decode(encoded);
    final nonce = bytes.sublist(0, 12);
    final mac = bytes.sublist(bytes.length - 16);
    final cipherText = bytes.sublist(12, bytes.length - 16);
    final clear = await _algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: _key,
    );
    return utf8.decode(clear);
  }
}
