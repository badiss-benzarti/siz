import 'package:siz/core/ui/ui_helpers.dart';
import 'package:siz/features/auth_onboarding/presentation/auth_providers.dart';
import 'package:siz/features/floor_plan/domain/station.dart';
import 'package:siz/features/floor_plan/presentation/floor_plan_providers.dart';
import 'package:siz/features/floor_plan/presentation/widgets/floor_modals.dart';
import 'package:siz/features/floor_plan/presentation/widgets/room/room_view.dart';
import 'package:siz/features/queue/presentation/queue_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class FloorPlanScreen extends ConsumerWidget {
  const FloorPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(authProvider).shop;
    final stationsAsync = ref.watch(floorPlanProvider);
    final queueItems = ref.watch(queueProvider).value ?? [];

    if (shop == null) {
      return const Scaffold(body: Center(child: Text('No shop loaded')));
    }

    Widget body;
    if (!stationsAsync.hasValue && stationsAsync.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!stationsAsync.hasValue && stationsAsync.hasError) {
      body = _ErrorView(
        onRetry: () => ref.read(floorPlanProvider.notifier).loadStations(),
      );
    } else {
      body = RoomView(
        shopName: shop.name,
        established: shop.createdAt.year,
        stations: stationsAsync.value ?? const [],
        totalChairs: shop.totalChairs,
        waitingCount: queueItems.length,
        onStationTap: (s) => _handleStationTap(context, ref, s),
        onReserveTap: () =>
            showAppSheet<void>(context, (_) => const _AddWaitingSheet()),
        onQueueViewTap: () =>
            showAppSheet<void>(context, (_) => const _QueueListSheet()),
        onRefresh: () async {
          ref.invalidate(queueProvider);
          await ref.read(floorPlanProvider.notifier).loadStations();
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: false, child: body),
    );
  }

  void _handleStationTap(BuildContext context, WidgetRef ref, Station station) {
    switch (station.status) {
      case ChairStatus.empty:
      case ChairStatus.cleaning:
        FloorModals.showAssignBarberDialog(context, ref, station.chairNumber);
      case ChairStatus.available:
        FloorModals.showSeatClientDialog(context, ref, station);
      case ChairStatus.occupied:
        FloorModals.showCheckoutDialog(context, ref, station);
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          const Text('Could not load the floor plan.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _AddWaitingSheet extends ConsumerStatefulWidget {
  const _AddWaitingSheet();

  @override
  ConsumerState<_AddWaitingSheet> createState() => _AddWaitingSheetState();
}

class _AddWaitingSheetState extends ConsumerState<_AddWaitingSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      children: [
        const Text(
          'Reserve Waiting Spot',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Client Name',
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone Number (Optional)',
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          onPressed: _busy ? null : _submit,
          child: const Text('Add to Waiting Couch'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Enter the client name.', isError: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref
          .read(queueProvider.notifier)
          .addToQueue(clientName: name, clientPhone: _phoneController.text),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }
}

class _QueueListSheet extends ConsumerWidget {
  const _QueueListSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueItems = ref.watch(queueProvider).value ?? [];

    return SheetBody(
      children: [
        const Text(
          'Waiting Area Queue',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap a chair with a free barber to seat the next client.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (queueItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No clients currently waiting.')),
          )
        else
          ...queueItems.asMap().entries.map((entry) {
            final item = entry.value;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.black,
                child: Text(
                  '${entry.key + 1}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(
                item.clientName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Waiting since ${DateFormat('h:mm a').format(item.createdAt)}',
              ),
              trailing: IconButton(
                tooltip: 'Remove from queue',
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () => runAction(
                  context,
                  () =>
                      ref.read(queueProvider.notifier).removeFromQueue(item.id),
                ),
              ),
            );
          }),
      ],
    );
  }
}
