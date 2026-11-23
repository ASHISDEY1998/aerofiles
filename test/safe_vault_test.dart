import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';
import 'package:aerofiles/services/security/safe_vault_service.dart';

void main() {
  group('Safe Vault & Encryption Tests', () {
    test('VaultItem JSON serialization and deserialization', () {
      final item = VaultItem(
        id: 'vault_123',
        fileName: 'secret.pdf',
        originalPath: '/storage/emulated/0/Documents/secret.pdf',
        size: 2048,
        dateAdded: DateTime(2026, 11, 23, 12, 0, 0),
      );

      final json = item.toJson();
      expect(json['id'], 'vault_123');
      expect(json['fileName'], 'secret.pdf');

      final reconstructed = VaultItem.fromJson(json);
      expect(reconstructed.id, item.id);
      expect(reconstructed.fileName, item.fileName);
      expect(reconstructed.size, item.size);
      expect(reconstructed.isDocument, isTrue);
      expect(reconstructed.isVideo, isFalse);
    });

    test('AES-256-CTR encryption and decryption roundtrip', () {
      final key = Uint8List.fromList(sha256.convert(utf8.encode('test_pin_1234')).bytes);
      final iv = Uint8List.fromList(List.generate(16, (i) => i));

      final plaintext = utf8.encode('Top Secret AeroFiles Content 1234567890!@#');

      // Encrypt
      final encCipher = StreamCipher('AES/CTR')
        ..init(true, ParametersWithIV(KeyParameter(key), iv));
      final ciphertext = encCipher.process(Uint8List.fromList(plaintext));

      expect(ciphertext, isNot(equals(plaintext)));

      // Decrypt
      final decCipher = StreamCipher('AES/CTR')
        ..init(false, ParametersWithIV(KeyParameter(key), iv));
      final decrypted = decCipher.process(ciphertext);

      expect(utf8.decode(decrypted), 'Top Secret AeroFiles Content 1234567890!@#');
    });
  });
}
