import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'haircut_art.dart';

/// Where posted photos live: JPEG files in the app's private documents
/// folder. The database keeps each file's path. Drawn demo photos are
/// stored as `art:<style>` instead of a path.
class PhotoStore {
  const PhotoStore({this.baseDir});

  /// The folder holding the photos folder; the app's documents folder when
  /// null (tests pass a temporary folder).
  final Directory? baseDir;

  static const artPrefix = 'art:';

  /// Writes [jpeg] to a new file and returns what to store in the database.
  Future<String> save(Uint8List jpeg) async {
    final base = baseDir ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'photos'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${const Uuid().v4()}.jpg'));
    await file.writeAsBytes(jpeg, flush: true);
    return file.path;
  }

  /// Deletes a saved photo; drawn photos and missing files are ignored.
  Future<void> delete(String source) async {
    if (source.startsWith(artPrefix)) return;
    try {
      await File(source).delete();
    } catch (_) {}
  }
}

/// Shows a photo saved by [PhotoStore], or a drawn demo photo.
class LocalPhoto extends StatelessWidget {
  const LocalPhoto({super.key, required this.source});

  final String source;

  static const _placeholder = ColoredBox(
    color: Color(0xFFE5E7EB),
    child: Center(child: Icon(Icons.image_outlined, color: Colors.grey)),
  );

  @override
  Widget build(BuildContext context) {
    if (source.startsWith(PhotoStore.artPrefix)) {
      final style = HaircutStyle.values
          .asNameMap()[source.substring(PhotoStore.artPrefix.length)];
      return style == null ? _placeholder : HaircutArt(style: style);
    }
    return Image.file(
      File(source),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder,
    );
  }
}
