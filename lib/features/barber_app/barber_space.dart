import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/ui/dashboard_widgets.dart';
import '../../core/ui/room_navigation_bar.dart';
import '../../core/ui/ui_helpers.dart';
import '../bookings/salon_bookings.dart';
import '../floor_plan/domain/station.dart';
import '../floor_plan/presentation/widgets/room/room_view.dart';
import '../queue/domain/queue_item.dart';
import 'barber_earnings_tab.dart';
import 'barber_portfolio_tab.dart';
import 'barber_link.dart';
import 'barber_salon.dart';
import 'barber_screens.dart';
import 'barber_session.dart';

/// A linked barber's app: the same bar as the owner, with their salon's live
/// floor as the home tab.
class BarberSpace extends StatefulWidget {
  const BarberSpace({super.key});

  @override
  State<BarberSpace> createState() => _BarberSpaceState();
}

class _BarberSpaceState extends State<BarberSpace> {
  static const _salonTab = 2;
  static const _agendaTab = 3;

  int _tab = _salonTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const BarberProfileTab(),
          const BarberEarningsTab(),
          _SalonTab(onShowQueue: () => setState(() => _tab = _agendaTab)),
          const _AgendaTab(),
          const BarberPortfolioTab(),
        ],
      ),
      bottomNavigationBar: RoomNavigationBar(
        items: const [
          RoomNavItem(Icons.person_outline, Icons.person, 'Profile'),
          RoomNavItem(
            Icons.account_balance_wallet_outlined,
            Icons.account_balance_wallet,
            'Earnings',
          ),
          RoomNavItem(Icons.chair_outlined, Icons.chair_outlined, 'Salon'),
          RoomNavItem(Icons.today_outlined, Icons.today, 'Agenda'),
          RoomNavItem(
            Icons.photo_camera_outlined,
            Icons.photo_camera,
            'Portfolio',
          ),
        ],
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Salon: the live floor, the barber's chair in green
// -----------------------------------------------------------------------------

class _SalonTab extends ConsumerWidget {
  const _SalonTab({required this.onShowQueue});

  final VoidCallback onShowQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floor = ref.watch(barberFloorProvider);
    final me = ref.watch(barberSessionProvider.select((s) => s.link));

    final Widget body = switch (floor) {
      AsyncData(:final value) => RoomView(
        shopName: value.shopName,
        established: value.established,
        stations: value.stations,
        totalChairs: value.totalChairs,
        waitingCount: value.queue.length,
        // Clients' names stay in the agenda; the floor shows barbers.
        anonymizeClients: true,
        highlightBarber: me?.barberName,
        reserveLabel: 'ADD A WALK-IN',
        onReserveTap: () => _addWalkIn(context, ref),
        onQueueViewTap: onShowQueue,
        onStationTap: (s) => showSnack(context, _describe(s, me)),
        onRefresh: () => _refresh(context, ref),
      ),
      AsyncError(:final error) => _LoadError(
        message: describeError(error),
        onRetry: () => ref.invalidate(barberFloorProvider),
      ),
      _ => const Center(child: CircularProgressIndicator(color: Colors.black)),
    };

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: false, child: body),
    );
  }

  static String _describe(Station s, BarberLink? me) {
    final barber = s.activeBarberName;
    final mine = me != null && s.activeBarberId == me.barberId;
    return switch (s.status) {
      ChairStatus.occupied when mine =>
        'Chair #${s.chairNumber}: you are with ${s.activeClientName ?? 'a client'}.',
      ChairStatus.occupied => 'Chair #${s.chairNumber}: $barber is cutting.',
      ChairStatus.available when mine =>
        'Chair #${s.chairNumber}: your chair, ready for the next client.',
      ChairStatus.available => 'Chair #${s.chairNumber}: $barber is ready.',
      ChairStatus.cleaning => 'Chair #${s.chairNumber} is being cleaned.',
      ChairStatus.empty => 'Chair #${s.chairNumber} is free.',
    };
  }
}

Future<void> _refresh(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(barberFloorProvider.notifier).refresh();
  } catch (e) {
    if (context.mounted) showSnack(context, describeError(e), isError: true);
  }
}

Future<void> _addWalkIn(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add a walk-in'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Client name'),
        onSubmitted: (v) => Navigator.pop(dialogContext, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.black),
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Add to the queue'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  await runAction(
    context,
    () => ref.read(barberFloorProvider.notifier).addWalkIn(name),
    successMessage: '${name.trim()} is in the queue.',
  );
}

// -----------------------------------------------------------------------------
// Agenda: duty, my chair, the queue
// -----------------------------------------------------------------------------

class _AgendaTab extends ConsumerWidget {
  const _AgendaTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(barberSessionProvider.select((s) => s.link));
    final floor = ref.watch(barberFloorProvider);
    if (me == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Agenda'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context, ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _DutyCard(onDuty: me.isOnDuty),
            const SectionHeading('My chair'),
            switch (floor) {
              AsyncData(:final value) => _MyChairCard(
                station: value.stations
                    .where((s) => s.activeBarberId == me.barberId)
                    .firstOrNull,
              ),
              AsyncError(:final error) => EmptyBox(describeError(error)),
              _ => const EmptyBox('Loading…'),
            },
            const SectionHeading('My bookings'),
            SalonBookingsList(
              bookings: ref.watch(
                barberBookingsProvider((
                  shopId: me.shopId,
                  barberId: me.barberId,
                )),
              ),
              emptyMessage: 'No bookings for you yet.',
            ),
            SectionHeading(
              switch (floor) {
                AsyncData(:final value) => 'Waiting (${value.queue.length})',
                _ => 'Waiting',
              },
              trailing: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.black),
                onPressed: () => _addWalkIn(context, ref),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Walk-in'),
              ),
            ),
            if (floor case AsyncData(:final value))
              if (value.queue.isEmpty)
                const EmptyBox('Nobody is waiting.')
              else
                for (final (i, item) in value.queue.indexed)
                  _QueueCard(
                    position: i + 1,
                    item: item,
                    forMe: item.requestedBarberId == me.barberId,
                    requestedName: _barberName(
                      value.stations,
                      item.requestedBarberId,
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  /// Name of a requested barber, when they sit at a chair right now.
  static String? _barberName(List<Station> stations, String? barberId) {
    if (barberId == null) return null;
    return stations
        .where((s) => s.activeBarberId == barberId)
        .firstOrNull
        ?.activeBarberName;
  }
}

class _DutyCard extends ConsumerWidget {
  const _DutyCard({required this.onDuty});

  final bool onDuty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: onDuty ? const Color(0xFFECFDF5) : null,
      child: SwitchListTile(
        secondary: Icon(
          onDuty ? Icons.check_circle : Icons.pause_circle_outline,
          color: onDuty ? const Color(0xFF10B981) : Colors.grey,
        ),
        title: Text(
          onDuty ? 'On duty' : 'Off duty',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          onDuty
              ? 'Your salon can seat clients with you.'
              : 'Going off duty frees your chair.',
        ),
        value: onDuty,
        onChanged: (v) => runAction(
          context,
          () => ref.read(barberFloorProvider.notifier).setDuty(onDuty: v),
          successMessage: v ? 'You are on duty.' : 'You are off duty.',
        ),
      ),
    );
  }
}

class _MyChairCard extends StatelessWidget {
  const _MyChairCard({required this.station});

  final Station? station;

  @override
  Widget build(BuildContext context) {
    final s = station;
    if (s == null) {
      return const EmptyBox(
        'No chair yet. Your salon owner assigns you one on the floor.',
      );
    }
    final busy = s.status == ChairStatus.occupied;
    final minutes = s.serviceStartTime == null
        ? null
        : DateTime.now().difference(s.serviceStartTime!).inMinutes;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: busy ? Colors.black : const Color(0xFF10B981),
          child: Text(
            '${s.chairNumber}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        title: Text(
          busy ? 'With ${s.activeClientName ?? 'a client'}' : 'Ready',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          busy
              ? 'Chair #${s.chairNumber} · ${minutes ?? 0} min so far'
              : 'Chair #${s.chairNumber} · waiting for the next client',
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.position,
    required this.item,
    required this.forMe,
    required this.requestedName,
  });

  final int position;
  final QueueItem item;
  final bool forMe;
  final String? requestedName;

  static const _green = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final waited = DateTime.now().difference(item.createdAt).inMinutes;
    final note = forMe
        ? 'Asked for you'
        : requestedName != null
        ? 'For $requestedName'
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: forMe
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: _green, width: 2.5),
            )
          : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.black,
          child: Text(
            '$position',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          item.clientName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          [
            'Since ${DateFormat('HH:mm').format(item.createdAt)} '
                '($waited min)',
            if (item.notes != null) item.notes!,
          ].join(' · '),
        ),
        trailing: note == null
            ? null
            : Text(
                note,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: forMe ? const Color(0xFF166534) : Colors.grey,
                ),
              ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
