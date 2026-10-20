import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/account_auth.dart';
import '../../core/providers/data_revision.dart';
import '../../core/ui/ui_helpers.dart';
import 'client_activity.dart';
import 'client_directory.dart';
import 'client_session.dart';

const _ink = Color(0xFF111111);
const _muted = Color(0xFF6B7280);
const _gold = Color(0xFFC9A227);

/// The signed-in client, or null after telling a guest to sign in.
AppUser? requireClient(BuildContext context, WidgetRef ref, String action) {
  final user = ref.read(clientSessionProvider).user;
  if (user == null) {
    showSnack(context, 'Create a free account in Profile to $action.');
  }
  return user;
}

/// Reloads every screen showing salon data after a change.
void dataChanged(WidgetRef ref) =>
    ref.read(dataRevisionProvider.notifier).bump();

/// Joins [shopId]'s line as the signed-in client.
Future<void> joinLine(
  BuildContext context,
  WidgetRef ref,
  String shopId,
) async {
  final user = requireClient(context, ref, 'join the line');
  if (user == null) return;
  await runAction(
    context,
    () => ref
        .read(clientActivityProvider)
        .joinQueue(client: user, shopId: shopId),
    successMessage: 'You are in the line. Follow your place in Bookings.',
  );
  dataChanged(ref);
}

// -----------------------------------------------------------------------------
// Favorites
// -----------------------------------------------------------------------------

/// Heart in a salon's app bar.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteSalonsProvider).value ?? const [];
    final isFavorite = favorites.any((s) => s.id == shopId);
    return IconButton(
      tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? const Color(0xFFE11D48) : null,
      ),
      onPressed: () async {
        final user = requireClient(context, ref, 'save favorites');
        if (user == null) return;
        var added = false;
        await runAction(context, () async {
          added = await ref
              .read(clientActivityProvider)
              .toggleFavorite(user.id, shopId);
        });
        dataChanged(ref);
        if (context.mounted) {
          showSnack(
            context,
            added ? 'Added to your favorites.' : 'Removed from favorites.',
          );
        }
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Bottom bar of a salon: status, Book, Join / Leave the line
// -----------------------------------------------------------------------------

class SalonActionBar extends ConsumerWidget {
  const SalonActionBar({super.key, required this.details});

  final SalonDetails details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salon = details.salon;
    final spot = ref.watch(myQueueSpotProvider).value;
    final waitingHere = spot != null && spot.shopId == salon.id;

    Future<void> joinOrLeave() async {
      final user = requireClient(context, ref, 'join the line');
      if (user == null) return;
      final activity = ref.read(clientActivityProvider);
      await runAction(
        context,
        () => waitingHere
            ? activity.leaveQueue(user.id)
            : activity.joinQueue(client: user, shopId: salon.id),
        successMessage: waitingHere
            ? 'You left the line.'
            : 'You are in the line. Follow your place in Bookings.',
      );
      dataChanged(ref);
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              waitingHere
                  ? 'You are #${spot.position} in the line'
                  : salon.isOpen
                  ? '${salon.waitingCount} waiting · ${details.barbersOnDuty} '
                        'barber${details.barbersOnDuty == 1 ? '' : 's'} on duty'
                  : 'Closed now · you can still book',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () {
                      if (requireClient(context, ref, 'book') == null) return;
                      showBookingSheet(context, details);
                    },
                    icon: const Icon(Icons.event_available, size: 18),
                    label: const Text('Book'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: waitingHere
                          ? const Color(0xFFB91C1C)
                          : _ink,
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: salon.isOpen || waitingHere ? joinOrLeave : null,
                    icon: Icon(
                      waitingHere ? Icons.logout : Icons.event_seat,
                      size: 18,
                    ),
                    label: Text(
                      waitingHere ? 'Leave the line' : 'Join the line',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Booking sheet
// -----------------------------------------------------------------------------

Future<void> showBookingSheet(BuildContext context, SalonDetails details) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BookingSheet(details: details),
  );
}

class _BookingSheet extends ConsumerStatefulWidget {
  const _BookingSheet({required this.details});

  final SalonDetails details;

  @override
  ConsumerState<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<_BookingSheet> {
  static const _firstHour = 9;
  static const _lastSlot = TimeOfDay(hour: 19, minute: 30);

  late ClientService? _service = widget.details.services.firstOrNull;
  ClientBarber? _barber;
  late DateTime _day = _days.first;
  TimeOfDay? _time;
  bool _saving = false;

  /// Today (if slots remain) and the next 13 days.
  List<DateTime> get _days {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = _slotsFor(today).isEmpty
        ? today.add(const Duration(days: 1))
        : today;
    return [for (var i = 0; i < 14; i++) start.add(Duration(days: i))];
  }

  List<TimeOfDay> _slotsFor(DateTime day) {
    final now = DateTime.now();
    return [
      for (
        var m = _firstHour * 60;
        m <= _lastSlot.hour * 60 + _lastSlot.minute;
        m += 30
      )
        if (day
            .add(Duration(minutes: m))
            .isAfter(now.add(const Duration(minutes: 15))))
          TimeOfDay(hour: m ~/ 60, minute: m % 60),
    ];
  }

  Future<void> _submit() async {
    final user = ref.read(clientSessionProvider).user;
    final service = _service;
    final time = _time;
    if (user == null || service == null || time == null) return;
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => ref
          .read(clientActivityProvider)
          .book(
            client: user,
            shopId: widget.details.salon.id,
            barberId: _barber?.id,
            serviceName: service.name,
            durationMinutes: service.minutes,
            startsAt: _day.add(
              Duration(hours: time.hour, minutes: time.minute),
            ),
          ),
      successMessage: 'Booking sent. The salon will confirm it.',
    );
    dataChanged(ref);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    final slots = _slotsFor(_day);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ChipTheme(
          // Green, like the highlight on the salon floor.
          data: ChipTheme.of(context).copyWith(
            selectedColor: const Color(0xFFDCFCE7),
            checkmarkColor: const Color(0xFF166534),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Book at ${details.salon.name}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                const _Label('Service'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in details.services)
                      ChoiceChip(
                        label: Text('${s.name} · ${formatMoney(s.price)}'),
                        selected: _service == s,
                        onSelected: (_) => setState(() => _service = s),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const _Label('Barber'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Any barber'),
                      selected: _barber == null,
                      onSelected: (_) => setState(() => _barber = null),
                    ),
                    for (final b in details.barbers)
                      ChoiceChip(
                        label: Text(b.name),
                        selected: _barber == b,
                        onSelected: (_) => setState(() => _barber = b),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const _Label('Day'),
                SizedBox(
                  height: 64,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final d in _days)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(DateFormat('EEE').format(d)),
                                Text(
                                  DateFormat('d MMM').format(d),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            selected: _day == d,
                            onSelected: (_) => setState(() {
                              _day = d;
                              _time = null;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const _Label('Time'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in slots)
                      ChoiceChip(
                        label: Text(t.format(context)),
                        selected: _time == t,
                        onSelected: (_) => setState(() => _time = t),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _saving || _service == null || _time == null
                      ? null
                      : _submit,
                  child: Text(
                    _time == null ? 'Pick a time' : 'Send booking request',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
    ),
  );
}

// -----------------------------------------------------------------------------
// Stars, and a post's stars + comment box
// -----------------------------------------------------------------------------

/// Five tappable stars.
class StarPicker extends StatelessWidget {
  const StarPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 30,
  });

  final int? value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          InkResponse(
            radius: size * 0.7,
            onTap: () => onChanged(i),
            child: Icon(
              i <= (value ?? 0)
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: _gold,
              size: size,
            ),
          ),
      ],
    );
  }
}

/// Under a photo: the client's stars for it and a comment box.
class PostReactions extends ConsumerStatefulWidget {
  const PostReactions({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostReactions> createState() => _PostReactionsState();
}

class _PostReactionsState extends ConsumerState<PostReactions> {
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _rate(int stars) async {
    final user = requireClient(context, ref, 'rate photos');
    if (user == null) return;
    await runAction(
      context,
      () => ref
          .read(clientActivityProvider)
          .ratePhoto(clientId: user.id, postId: widget.postId, stars: stars),
      successMessage: 'Thanks for rating this cut.',
    );
    ref.invalidate(myPhotoRatingProvider(widget.postId));
    dataChanged(ref);
  }

  Future<void> _send() async {
    final user = requireClient(context, ref, 'comment');
    if (user == null) return;
    final ok = await runAction(
      context,
      () => ref
          .read(clientActivityProvider)
          .comment(author: user, postId: widget.postId, body: _comment.text),
    );
    if (!ok) return;
    _comment.clear();
    if (mounted) FocusScope.of(context).unfocus();
    dataChanged(ref);
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myPhotoRatingProvider(widget.postId)).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                mine == null ? 'Rate this cut' : 'Your rating',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              StarPicker(value: mine, onChanged: _rate, size: 28),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            maxLength: 500,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Add a comment…',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: 'Send',
                icon: const Icon(Icons.send),
                onPressed: _send,
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
        ],
      ),
    );
  }
}
