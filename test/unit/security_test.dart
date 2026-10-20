import 'dart:convert';

import 'package:siz/core/security/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PasswordHasher', () {
    const hasher = PasswordHasher(iterations: 1000);

    test('PBKDF2 matches the RFC 7914 test vector', () {
      final digest = PasswordHasher.pbkdf2(
        utf8.encode('passwd'),
        utf8.encode('salt'),
        1,
        64,
      );
      expect(
        _hex(digest),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
    });

    test('hash embeds scheme and iteration count', () async {
      final hash = await hasher.hash('StrongPassword123!', 'a1b2c3');
      expect(hash, startsWith(r'pbkdf2-sha256$1000$'));
      expect(hash.split(r'$').last.length, 64);
    });

    test('verify accepts the right password and rejects others', () async {
      final salt = hasher.generateSalt();
      final hash = await hasher.hash('CorrectHorse', salt);

      expect(await hasher.verify('CorrectHorse', salt, hash), isTrue);
      expect(await hasher.verify('WrongHorse', salt, hash), isFalse);
      expect(await hasher.verify('CorrectHorse', 'other-salt', hash), isFalse);
    });

    test(
      'legacy SHA-256 hashes still verify and are flagged for rehash',
      () async {
        final legacy = PasswordHasher.legacyHash('OldPassword', 'salt1');

        expect(await hasher.verify('OldPassword', 'salt1', legacy), isTrue);
        expect(await hasher.verify('Nope', 'salt1', legacy), isFalse);
        expect(hasher.needsRehash(legacy), isTrue);
      },
    );

    test('needsRehash detects weaker iteration counts', () async {
      final weak = await const PasswordHasher(iterations: 10).hash('p', 's');
      final current = await hasher.hash('p', 's');

      expect(hasher.needsRehash(weak), isTrue);
      expect(hasher.needsRehash(current), isFalse);
    });

    test('malformed stored hashes never verify', () async {
      expect(await hasher.verify('p', 's', r'pbkdf2-sha256$abc$00'), isFalse);
      expect(await hasher.verify('p', 's', ''), isFalse);
    });

    test('generateSalt returns 16 random bytes as hex', () {
      final a = hasher.generateSalt();
      final b = hasher.generateSalt();
      expect(a.length, 32);
      expect(a, isNot(equals(b)));
    });
  });
}
