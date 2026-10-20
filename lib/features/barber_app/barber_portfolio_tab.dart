import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/media/local_photo.dart';
import '../../core/ui/dashboard_widgets.dart';
import '../../core/ui/ui_helpers.dart';
import 'barber_session.dart';
import 'portfolio.dart';

const _ink = Color(0xFF111111);
const _muted = Color(0xFF6B7280);
const _gold = Color(0xFFC9A227);

/// The barber's portfolio, laid out like a social profile: who they are and
/// their numbers on top, their cuts in a grid below.
class BarberPortfolioTab extends ConsumerWidget {
  const BarberPortfolioTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(barberSessionProvider.select((s) => s.link));
    final posts = ref.watch(myPostsProvider);
    final rating = ref.watch(myVisitRatingProvider);
    if (link == null) return const SizedBox.shrink();

    Future<void> reload() async {
      ref
        ..invalidate(myVisitRatingProvider)
        ..invalidate(myPostsProvider);
      await ref.read(myPostsProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Portfolio'),
        actions: [
          IconButton(
            tooltip: 'New post',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () => _newPost(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _ProfileHeader(
                name: link.barberName,
                salon: link.shopName,
                posts: posts.value ?? const [],
                rating: rating.value,
              ),
            ),
            switch (posts) {
              AsyncData(:final value) when value.isEmpty => SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const EmptyBox(
                        'Share your first cut. Clients see your photos on '
                        'your salon page, comment and rate them.',
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _newPost(context, ref),
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('New post'),
                      ),
                    ],
                  ),
                ),
              ),
              AsyncData(:final value) => SliverPadding(
                padding: const EdgeInsets.all(2),
                sliver: SliverGrid.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  children: [
                    for (final post in value)
                      _GridTile(
                        post: post,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PostDetailScreen(post: post),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              AsyncError(:final error) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: EmptyBox(describeError(error)),
                ),
              ),
              _ => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }

  static Future<void> _newPost(BuildContext context, WidgetRef ref) async {
    final posted = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const NewPostScreen()));
    if (posted ?? false) {
      ref.invalidate(myPostsProvider);
      if (context.mounted) {
        showSnack(context, 'Posted. Clients see it on your salon page.');
      }
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.salon,
    required this.posts,
    required this.rating,
  });

  final String name;
  final String salon;
  final List<PortfolioPost> posts;
  final VisitRating? rating;

  @override
  Widget build(BuildContext context) {
    final rated = posts.where((p) => p.ratingCount > 0).toList();
    final photoAvg = rated.isEmpty
        ? null
        : rated.fold<double>(0, (s, p) => s + p.ratingAvg) / rated.length;
    final visits = rating;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: _ink,
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat('${posts.length}', 'Posts'),
                    _Stat(
                      visits == null || visits.count == 0
                          ? '—'
                          : visits.average.toStringAsFixed(1),
                      visits == null || visits.count == 0
                          ? 'No visits rated'
                          : '${visits.count} visit${visits.count == 1 ? '' : 's'}',
                    ),
                    _Stat(
                      photoAvg == null ? '—' : photoAvg.toStringAsFixed(1),
                      'Photos',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          Text('Barber at $salon', style: const TextStyle(color: _muted)),
          const SizedBox(height: 4),
          const Text(
            'Your rating comes from clients after their cut. Each photo has '
            'its own stars.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Ratings get a star; counts and dashes do not.
    final isRating = value.contains('.');
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            if (isRating)
              const Icon(Icons.star_rounded, color: _gold, size: 20),
          ],
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
      ],
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.post, required this.onTap});

  final PortfolioPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LocalPhoto(source: post.imageUrl),
          if (post.ratingCount > 0)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: _gold, size: 13),
                    const SizedBox(width: 2),
                    Text(
                      post.ratingAvg.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// One post: the photo, its stars, the caption and clients' comments
// -----------------------------------------------------------------------------

class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({super.key, required this.post});

  final PortfolioPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(postCommentsProvider(post.id));

    Future<void> deletePost() async {
      final ok = await confirmAction(
        context,
        title: 'Delete this post?',
        message: 'The photo, its comments and ratings are removed.',
        confirmLabel: 'Delete',
        destructive: true,
      );
      if (!ok || !context.mounted) return;
      final done = await runAction(
        context,
        () => ref.read(portfolioRepositoryProvider).deletePost(post),
        successMessage: 'Post deleted.',
      );
      if (done && context.mounted) {
        ref.invalidate(myPostsProvider);
        Navigator.of(context).pop();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        actions: [
          IconButton(
            tooltip: 'Delete post',
            icon: const Icon(Icons.delete_outline),
            onPressed: deletePost,
          ),
        ],
      ),
      body: ListView(
        children: [
          AspectRatio(aspectRatio: 1, child: LocalPhoto(source: post.imageUrl)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: _gold),
                const SizedBox(width: 4),
                Text(
                  post.ratingCount == 0
                      ? 'No ratings yet'
                      : '${post.ratingAvg.toStringAsFixed(1)} · '
                            '${post.ratingCount} rating'
                            '${post.ratingCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                const Icon(Icons.mode_comment_outlined, size: 20),
                const SizedBox(width: 4),
                Text('${post.commentCount}'),
              ],
            ),
          ),
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(post.caption, style: const TextStyle(fontSize: 15)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              DateFormat('d MMM yyyy, HH:mm').format(post.createdAt),
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(
              'Comments',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          switch (comments) {
            AsyncData(:final value) when value.isEmpty => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: EmptyBox('No comments yet.'),
            ),
            AsyncData(:final value) => Column(
              children: [
                for (final c in value)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE5E7EB),
                      child: Text(
                        c.authorName.isEmpty
                            ? '?'
                            : c.authorName[0].toUpperCase(),
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    title: Text(
                      c.authorName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(c.body),
                    trailing: IconButton(
                      tooltip: 'Remove comment',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        final done = await runAction(
                          context,
                          () => ref
                              .read(portfolioRepositoryProvider)
                              .deleteComment(c.id),
                        );
                        if (done) ref.invalidate(postCommentsProvider(post.id));
                      },
                    ),
                  ),
              ],
            ),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.all(16),
              child: EmptyBox(describeError(error)),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// New post: photo, caption, the client's consent
// -----------------------------------------------------------------------------

class NewPostScreen extends ConsumerStatefulWidget {
  const NewPostScreen({super.key});

  @override
  ConsumerState<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends ConsumerState<NewPostScreen> {
  final _caption = TextEditingController();
  XFile? _file;
  Uint8List? _photo;
  bool _consent = false;
  bool _posting = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      // The phone resizes and converts (e.g. iPhone HEIC) to JPEG first.
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _file = file;
        _photo = bytes;
      });
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Could not open the photo.', isError: true);
      }
    }
  }

  Future<void> _post() async {
    final link = ref.read(barberSessionProvider).link;
    final photo = _photo;
    if (link == null || photo == null || !_consent) return;
    setState(() => _posting = true);
    final ok = await runAction(
      context,
      () => ref
          .read(portfolioRepositoryProvider)
          .publish(
            barberId: link.barberId,
            photo: photo,
            caption: _caption.text,
          ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    return Scaffold(
      appBar: AppBar(title: const Text('New post')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: photo == null
                  ? InkWell(
                      onTap: () => _pick(ImageSource.gallery),
                      child: const ColoredBox(
                        color: Color(0xFFF3F4F6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 56,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Choose a photo of the cut',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Image.memory(photo, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _posting ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(_file == null ? 'Gallery' : 'Change'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _posting ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _caption,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Caption',
              hintText: 'e.g. Mid skin fade, textured top',
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consent,
            onChanged: _posting
                ? null
                : (v) => setState(() => _consent = v ?? false),
            title: const Text(
              'The client agreed to have this photo published',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Required: the photo shows a person (personal data law).',
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: photo != null && _consent && !_posting ? _post : null,
            icon: _posting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.send),
            label: Text(_posting ? 'Posting…' : 'Share'),
          ),
        ],
      ),
    );
  }
}
