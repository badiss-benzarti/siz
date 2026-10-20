import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database_service.dart';
import '../../core/errors/app_exception.dart';
import '../../core/media/local_photo.dart';
import '../../core/media/photo_compressor.dart';
import '../../core/providers/core_providers.dart';
import 'barber_session.dart';

/// One photo of a cut, as posted by a barber.
class PortfolioPost {
  const PortfolioPost({
    required this.id,
    required this.imagePath,
    required this.imageUrl,
    required this.caption,
    required this.ratingAvg,
    required this.ratingCount,
    required this.commentCount,
    required this.createdAt,
  });

  final String id;

  /// The photo file on this phone, or a drawn demo photo (see [PhotoStore]).
  final String imagePath;

  /// Same as [imagePath]; what [LocalPhoto] shows.
  final String imageUrl;
  final String caption;

  /// This photo's own stars, from client accounts.
  final double ratingAvg;
  final int ratingCount;
  final int commentCount;
  final DateTime createdAt;
}

class PostComment {
  const PostComment({
    required this.id,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String authorName;
  final String body;
  final DateTime createdAt;
}

/// The barber's rating: from clients' ratings of real visits only.
class VisitRating {
  const VisitRating(this.average, this.count);

  final double average;
  final int count;
}

/// A barber's portfolio. Failures are thrown as `AppException`.
abstract class PortfolioRepository {
  Future<List<PortfolioPost>> postsOf(String barberId);

  Future<List<PostComment>> commentsOf(String postId);

  Future<VisitRating> visitRatingOf(String barberId);

  /// Compresses [photo], saves it on the phone and posts it.
  Future<void> publish({
    required String barberId,
    required Uint8List photo,
    required String caption,
  });

  Future<void> deletePost(PortfolioPost post);

  Future<void> deleteComment(String commentId);
}

/// SQL shared by every list of posts: the post, its barber and salon, and
/// its photo rating and comment count.
abstract final class PostQuery {
  static const select = '''
    SELECT p.id, p.shop_id, p.barber_id, p.image, p.caption, p.created_at,
      b.name AS barber_name, s.name AS shop_name,
      (SELECT AVG(stars) FROM photo_ratings r WHERE r.post_id = p.id)
        AS rating_avg,
      (SELECT COUNT(*) FROM photo_ratings r WHERE r.post_id = p.id)
        AS rating_count,
      (SELECT COUNT(*) FROM post_comments c WHERE c.post_id = p.id)
        AS comment_count
    FROM portfolio_posts p
    JOIN barbers b ON b.id = p.barber_id
    JOIN shops s ON s.id = p.shop_id
  ''';

  /// The barber's rating from clients' ratings of real visits.
  static const visitRating = '''
    SELECT AVG(stars) AS avg, COUNT(*) AS n
    FROM visit_ratings WHERE barber_id = ?
  ''';
}

/// [PortfolioRepository] on this device: rows in the database, photos as
/// files in the app's folder.
class LocalPortfolioRepository implements PortfolioRepository {
  LocalPortfolioRepository(this._db, {this.photos = const PhotoStore()});

  final DatabaseService _db;
  final PhotoStore photos;

  @override
  Future<List<PortfolioPost>> postsOf(String barberId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '${PostQuery.select} WHERE p.barber_id = ? ORDER BY p.created_at DESC',
      [barberId],
    );
    return [
      for (final r in rows)
        PortfolioPost(
          id: r['id'] as String,
          imagePath: r['image'] as String,
          imageUrl: r['image'] as String,
          caption: r['caption'] as String,
          ratingAvg: (r['rating_avg'] as num?)?.toDouble() ?? 0,
          ratingCount: r['rating_count'] as int,
          commentCount: r['comment_count'] as int,
          createdAt: DateTime.parse(r['created_at'] as String),
        ),
    ];
  }

  @override
  Future<List<PostComment>> commentsOf(String postId) async {
    final db = await _db.database;
    final rows = await db.query(
      'post_comments',
      where: 'post_id = ?',
      whereArgs: [postId],
      orderBy: 'created_at ASC',
    );
    return [
      for (final r in rows)
        PostComment(
          id: r['id'] as String,
          authorName: r['author_name'] as String,
          body: r['body'] as String,
          createdAt: DateTime.parse(r['created_at'] as String),
        ),
    ];
  }

  @override
  Future<VisitRating> visitRatingOf(String barberId) async {
    final db = await _db.database;
    final row = (await db.rawQuery(PostQuery.visitRating, [barberId])).first;
    return VisitRating((row['avg'] as num?)?.toDouble() ?? 0, row['n'] as int);
  }

  @override
  Future<void> publish({
    required String barberId,
    required Uint8List photo,
    required String caption,
  }) async {
    final text = caption.trim();
    if (text.isEmpty) throw const AppException('Write a caption.');
    final db = await _db.database;
    final barber = await db.query(
      'barbers',
      columns: ['shop_id'],
      where: 'id = ?',
      whereArgs: [barberId],
    );
    if (barber.isEmpty) throw const AppException('You are not in a salon.');
    final jpeg = await PhotoCompressor.compress(photo);
    final image = await photos.save(jpeg);
    try {
      await db.insert('portfolio_posts', {
        'id': const Uuid().v4(),
        'barber_id': barberId,
        'shop_id': barber.first['shop_id'],
        'image': image,
        'caption': text,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // No orphan photo if the post itself is refused.
      await photos.delete(image);
      rethrow;
    }
  }

  @override
  Future<void> deletePost(PortfolioPost post) async {
    final db = await _db.database;
    await db.delete('portfolio_posts', where: 'id = ?', whereArgs: [post.id]);
    await photos.delete(post.imagePath);
  }

  @override
  Future<void> deleteComment(String commentId) async {
    final db = await _db.database;
    await db.delete('post_comments', where: 'id = ?', whereArgs: [commentId]);
  }
}

final portfolioRepositoryProvider = Provider<PortfolioRepository>(
  (ref) => LocalPortfolioRepository(ref.watch(databaseServiceProvider)),
);

/// The signed-in barber's posts, newest first.
final myPostsProvider = FutureProvider.autoDispose<List<PortfolioPost>>((
  ref,
) async {
  final barberId = ref.watch(
    barberSessionProvider.select((s) => s.link?.barberId),
  );
  if (barberId == null) return const [];
  return ref.read(portfolioRepositoryProvider).postsOf(barberId);
});

final myVisitRatingProvider = FutureProvider.autoDispose<VisitRating>((
  ref,
) async {
  final barberId = ref.watch(
    barberSessionProvider.select((s) => s.link?.barberId),
  );
  if (barberId == null) return const VisitRating(0, 0);
  return ref.read(portfolioRepositoryProvider).visitRatingOf(barberId);
});

final postCommentsProvider = FutureProvider.autoDispose
    .family<List<PostComment>, String>(
      (ref, postId) => ref.read(portfolioRepositoryProvider).commentsOf(postId),
    );
