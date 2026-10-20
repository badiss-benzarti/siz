import 'dart:typed_data';

import 'package:siz/core/errors/app_exception.dart';
import 'package:siz/core/media/photo_compressor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('a big phone photo becomes a small JPEG of at most 1080 px', () {
    // A noisy 4000 x 3000 picture compresses poorly, like a real photo.
    final photo = img.Image(width: 4000, height: 3000);
    for (final pixel in photo) {
      pixel
        ..r = (pixel.x * 7 + pixel.y * 3) % 256
        ..g = (pixel.x * pixel.y) % 256
        ..b = (pixel.y * 11) % 256;
    }
    final original = Uint8List.fromList(img.encodePng(photo));

    final jpeg = PhotoCompressor.compressSync(original);
    final result = img.decodeJpg(jpeg)!;

    // Extreme detail: shrunk further until it fits, keeping its shape.
    expect(result.width, lessThanOrEqualTo(1080));
    expect(result.width / result.height, closeTo(4 / 3, 0.01));
    expect(jpeg.length, lessThanOrEqualTo(PhotoCompressor.targetBytes));
  });

  test('portrait photos keep their shape', () {
    final photo = img.Image(width: 1500, height: 2000);
    final jpeg = PhotoCompressor.compressSync(
      Uint8List.fromList(img.encodePng(photo)),
    );
    final result = img.decodeJpg(jpeg)!;
    expect(result.height, 1080);
    expect(result.width, 810);
  });

  test('small photos are not enlarged', () {
    final photo = img.Image(width: 600, height: 400);
    final result = img.decodeJpg(
      PhotoCompressor.compressSync(Uint8List.fromList(img.encodePng(photo))),
    )!;
    expect(result.width, 600);
  });

  test('a file that is not a photo is refused', () {
    expect(
      () => PhotoCompressor.compressSync(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<AppException>()),
    );
  });
}
