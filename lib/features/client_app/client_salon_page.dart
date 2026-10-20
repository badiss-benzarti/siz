import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/media/local_photo.dart';
import '../../core/ui/dashboard_widgets.dart';
import '../../core/ui/ui_helpers.dart';
import '../floor_plan/presentation/widgets/room/room_view.dart';
import 'client_directory.dart';
import 'client_actions.dart';

const _ink = Color(0xFF111111);
const _muted = Color(0xFF6B7280);
const _gold = Color(0xFFC9A227);

/// What a client sees after choosing a salon: its live floor, barbers,
/// prices and photos. Refreshed every 30 seconds while open.
class ClientSalonPage extends ConsumerStatefulWidget {
  const ClientSalonPage({super.key, required this.shopId});

  final String shopId;

  @override
  ConsumerState<ClientSalonPage> createState() => _ClientSalonPageState();
}

class _ClientSalonPageState extends ConsumerState<ClientSalonPage> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(
      const Duration(seconds: 30),
      (_) => ref.invalidate(salonDetailsProvider(widget.shopId)),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(salonDetailsProvider(widget.shopId));
    final value = details.value;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          actions: [FavoriteButton(shopId: widget.shopId)],
          title: Column(
            children: [
              Text(
                value?.salon.name ?? 'Salon',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              if (value != null)
                Text(
                  value.salon.address,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          bottom: const TabBar(
            labelColor: _ink,
            indicatorColor: _ink,
            labelStyle: TextStyle(fontWeight: FontWeight.w800),
            tabs: [
              Tab(text: 'Live'),
              Tab(text: 'Barbers'),
              Tab(text: 'Prices'),
              Tab(text: 'Photos'),
            ],
          ),
        ),
        body: switch (details) {
          AsyncValue(:final value?) => TabBarView(
            children: [
              _LiveTab(details: value),
              _BarbersTab(details: value),
              _PricesTab(details: value),
              _PhotosTab(posts: value.posts),
            ],
          ),
          AsyncError(:final error) => Center(
            child: TextButton(
              onPressed: () =>
                  ref.invalidate(salonDetailsProvider(widget.shopId)),
              child: Text('${describeError(error)}\nTap to retry.'),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
        bottomNavigationBar: value == null
            ? null
            : SalonActionBar(details: value),
      ),
    );
  }
}

class _LiveTab extends ConsumerWidget {
  const _LiveTab({required this.details});

  final SalonDetails details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salon = details.salon;
    if (!salon.isOpen) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: EmptyBox('Closed right now. Come back during opening hours.'),
        ),
      );
    }
    return ColoredBox(
      color: Colors.white,
      child: RoomView(
        shopName: salon.name,
        established: salon.established,
        stations: details.stations,
        totalChairs: salon.totalChairs,
        waitingCount: salon.waitingCount,
        anonymizeClients: true,
        reserveLabel: 'JOIN THE QUEUE',
        onReserveTap: () => joinLine(context, ref, salon.id),
        onQueueViewTap: () => showSnack(
          context,
          salon.waitingCount == 0
              ? 'Nobody is waiting.'
              : '${salon.waitingCount} waiting.',
        ),
        onStationTap: (s) => showSnack(
          context,
          s.activeBarberName == null
              ? 'Chair #${s.chairNumber} is free.'
              : 'Chair #${s.chairNumber}: ${s.activeBarberName}.',
        ),
      ),
    );
  }
}

class _BarbersTab extends StatelessWidget {
  const _BarbersTab({required this.details});

  final SalonDetails details;

  @override
  Widget build(BuildContext context) {
    if (details.barbers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyBox('No barbers listed yet.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final b in details.barbers)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: b.isOnDuty ? _ink : const Color(0xFFD1D5DB),
                child: Text(
                  b.name.isEmpty ? '?' : b.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(
                b.name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                [
                  if (b.specialty.isNotEmpty) b.specialty,
                  b.isOnDuty ? 'On duty' : 'Off today',
                ].join(' · '),
              ),
              trailing: RatingBadge(
                average: b.ratingAvg,
                count: b.ratingCount,
                emptyLabel: 'New',
              ),
            ),
          ),
        const SizedBox(height: 4),
        const Text(
          'Ratings come from clients after a real visit.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _PricesTab extends StatelessWidget {
  const _PricesTab({required this.details});

  final SalonDetails details;

  @override
  Widget build(BuildContext context) {
    if (details.services.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyBox('No prices listed yet.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              for (final s in details.services)
                ListTile(
                  leading: const Icon(Icons.content_cut),
                  title: Text(
                    s.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('${s.minutes} min'),
                  trailing: Text(
                    formatMoney(s.price),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotosTab extends StatelessWidget {
  const _PhotosTab({required this.posts});

  final List<ClientPost> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyBox('No photos yet.'),
      );
    }
    return PostGrid(posts: posts, columns: 3);
  }
}

// -----------------------------------------------------------------------------
// Photos: grid, and one post with its comments
// -----------------------------------------------------------------------------

/// Stars with their count, or [emptyLabel] when nobody rated yet.
class RatingBadge extends StatelessWidget {
  const RatingBadge({
    super.key,
    required this.average,
    required this.count,
    this.emptyLabel = 'No ratings',
  });

  final double average;
  final int count;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Text(
        emptyLabel,
        style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, color: _gold, size: 18),
        Text(
          average.toStringAsFixed(1),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        Text(' ($count)', style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }
}

class PostGrid extends StatelessWidget {
  const PostGrid({
    super.key,
    required this.posts,
    this.columns = 3,
    this.showSalon = false,
  });

  final List<ClientPost> posts;
  final int columns;
  final bool showSalon;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (context, i) {
        final post = posts[i];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ClientPostScreen(post: post),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              LocalPhoto(source: post.imageUrl),
              if (post.ratingCount > 0 || showSalon)
                Positioned(
                  left: 4,
                  right: 4,
                  bottom: 4,
                  child: Row(
                    children: [
                      if (showSalon)
                        Expanded(
                          child: Text(
                            post.shopName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              shadows: [Shadow(blurRadius: 4)],
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (post.ratingCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: _gold,
                                size: 13,
                              ),
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
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class ClientPostScreen extends ConsumerWidget {
  const ClientPostScreen({super.key, required this.post, this.openSalon});

  final ClientPost post;

  /// Shown in Social, to go from a photo to its salon.
  final VoidCallback? openSalon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(clientCommentsProvider(post.id));
    return Scaffold(
      appBar: AppBar(title: Text(post.barberName)),
      body: ListView(
        children: [
          AspectRatio(aspectRatio: 1, child: LocalPhoto(source: post.imageUrl)),
          ListTile(
            title: Text(
              post.barberName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: post.shopName == null ? null : Text(post.shopName!),
            trailing: RatingBadge(
              average: post.ratingAvg,
              count: post.ratingCount,
            ),
            onTap: openSalon,
          ),
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(post.caption, style: const TextStyle(fontSize: 15)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              DateFormat('d MMM yyyy').format(post.createdAt),
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
          PostReactions(postId: post.id),
        ],
      ),
    );
  }
}
