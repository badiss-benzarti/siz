import 'package:siz/core/cloud/cloud_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('server rule messages reach the user as written', () {
    final e = cloudException(
      const PostgrestException(
        message: 'Check out your client before going off duty.',
        code: 'P0001',
      ),
    );
    expect(e.message, 'Check out your client before going off duty.');
  });

  test('a server without the latest migration says so plainly', () {
    for (final code in ['PGRST205', 'PGRST202']) {
      final e = cloudException(PostgrestException(message: 'x', code: code));
      expect(e.message, contains('not switched on'));
    }
    final storage = cloudException(
      const StorageException('Bucket not found', statusCode: '404'),
    );
    expect(storage.message, contains('not switched on'));
  });

  test('other photo upload failures get a photo message', () {
    final e = cloudException(
      const StorageException('Payload too large', statusCode: '413'),
    );
    expect(e.message, 'This photo is too large.');
  });
}
