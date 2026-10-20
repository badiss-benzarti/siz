import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/providers/data_revision.dart';
import '../../core/ui/dashboard_widgets.dart';
import '../../core/ui/ui_helpers.dart';
import '../client_app/client_activity.dart';

/// A salon's bookings from today on.
final shopBookingsProvider = FutureProvider.autoDispose
    .family<List<Booking>, String>((ref, shopId) {
      ref.watch(dataRevisionProvider);
      return ref.read(clientActivityProvider).shopBookings(shopId);
    });

/// A barber's bookings from today on, with the "any barber" ones.
final barberBookingsProvider = FutureProvider.autoDispose
    .family<List<Booking>, ({String shopId, String barberId})>((ref, key) {
      ref.watch(dataRevisionProvider);
      return ref
          .read(clientActivityProvider)
          .barberBookings(key.shopId, key.barberId);
    });

/// The salon's list of bookings, with what can be done on each: accept or
/// decline a request, check in a confirmed client (they join the line).
class SalonBookingsList extends StatelessWidget {
  const SalonBookingsList({
    super.key,
    required this.bookings,
    this.emptyMessage = 'No bookings yet. Clients book from their app.',
  });

  final AsyncValue<List<Booking>> bookings;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return switch (bookings) {
      AsyncData(:final value) when value.isEmpty => EmptyBox(emptyMessage),
      AsyncData(:final value) => Column(
        children: [for (final b in value) SalonBookingCard(booking: b)],
      ),
      AsyncError(:final error) => EmptyBox(describeError(error)),
      _ => const EmptyBox('Loading…'),
    };
  }
}

class SalonBookingCard extends ConsumerWidget {
  const SalonBookingCard({super.key, required this.booking});

  final Booking booking;

  static const _muted = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    final activity = ref.read(clientActivityProvider);
    final now = DateTime.now();
    final isToday = DateUtils.isSameDay(b.startsAt, now);

    Future<void> act(Future<void> Function() action, String done) async {
      await runAction(context, action, successMessage: done);
      ref.read(dataRevisionProvider.notifier).bump();
    }

    final (color, label) = switch (b.status) {
      BookingStatus.pending => (const Color(0xFFF59E0B), 'Request'),
      BookingStatus.accepted => (const Color(0xFF10B981), 'Confirmed'),
      BookingStatus.done => (const Color(0xFF2563EB), 'Checked in'),
      BookingStatus.declined => (const Color(0xFF9CA3AF), 'Declined'),
      BookingStatus.cancelled => (const Color(0xFF9CA3AF), 'Cancelled'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${DateFormat('EEE d MMM').format(b.startsAt)} · '
                    '${DateFormat('HH:mm').format(b.startsAt)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${b.clientName} · ${b.serviceName} (${b.durationMinutes} min)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              b.barberName == null ? 'Any barber' : 'With ${b.barberName}',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            if (b.status == BookingStatus.pending ||
                (b.status == BookingStatus.accepted && isToday))
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (b.status == BookingStatus.pending) ...[
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                      ),
                      onPressed: () => act(
                        () => activity.answerBooking(b.id, accept: false),
                        'Booking declined.',
                      ),
                      child: const Text('Decline'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                      ),
                      onPressed: () => act(
                        () => activity.answerBooking(b.id, accept: true),
                        'Booking confirmed.',
                      ),
                      child: const Text('Accept'),
                    ),
                  ] else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                      ),
                      onPressed: () => act(
                        () => activity.checkIn(b.id),
                        '${b.clientName} is in the waiting line.',
                      ),
                      icon: const Icon(Icons.how_to_reg, size: 18),
                      label: const Text('Check in'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
