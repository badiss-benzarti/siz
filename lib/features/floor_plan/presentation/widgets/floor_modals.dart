import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:siz/core/ui/ui_helpers.dart';
import 'package:siz/features/auth_onboarding/presentation/auth_providers.dart';
import 'package:siz/features/barbers/presentation/barber_providers.dart';
import 'package:siz/features/finance/domain/service_ticket.dart';
import 'package:siz/features/floor_plan/domain/station.dart';
import 'package:siz/features/floor_plan/presentation/floor_plan_providers.dart';
import 'package:siz/features/queue/presentation/queue_providers.dart';

class FloorModals {
  /// Sheet to put an on-duty barber at a chair.
  static Future<void> showAssignBarberDialog(
    BuildContext context,
    WidgetRef ref,
    int chairNumber,
  ) {
    return showAppSheet<void>(
      context,
      (_) => _AssignBarberSheet(chairNumber: chairNumber),
    );
  }

  /// Sheet to seat a client from the waiting list or as a walk-in.
  static Future<void> showSeatClientDialog(
    BuildContext context,
    WidgetRef ref,
    Station station,
  ) {
    return showAppSheet<void>(
      context,
      (_) => _SeatClientSheet(station: station),
    );
  }

  /// Sheet to check out a finished service and record the sale.
  static Future<void> showCheckoutDialog(
    BuildContext context,
    WidgetRef ref,
    Station station,
  ) {
    return showAppSheet<void>(context, (_) => _CheckoutSheet(station: station));
  }
}

const _titleStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
const _subtitleStyle = TextStyle(color: Colors.grey, fontSize: 13);
const _labelStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 13);

// -----------------------------------------------------------------------------
// Assign barber
// -----------------------------------------------------------------------------

class _AssignBarberSheet extends ConsumerStatefulWidget {
  const _AssignBarberSheet({required this.chairNumber});

  final int chairNumber;

  @override
  ConsumerState<_AssignBarberSheet> createState() => _AssignBarberSheetState();
}

class _AssignBarberSheetState extends ConsumerState<_AssignBarberSheet> {
  String? _busyBarberId;

  @override
  Widget build(BuildContext context) {
    final barbers = ref.watch(barberListProvider).value ?? const [];
    final stations = ref.watch(floorPlanProvider).value ?? const <Station>[];
    final servingIds = stations
        .where((s) => s.status == ChairStatus.occupied)
        .map((s) => s.activeBarberId)
        .toSet();
    final onDuty = barbers.where((b) => b.isOnDuty).toList();
    final offDutyCount = barbers.length - onDuty.length;

    return SheetBody(
      children: [
        Text(
          'Assign Barber to Chair #${widget.chairNumber}',
          style: _titleStyle,
        ),
        const SizedBox(height: 12),
        if (onDuty.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              barbers.isEmpty
                  ? 'No barbers registered yet. Add staff in the Barbers tab.'
                  : 'No barbers are on duty. Switch someone on duty in the Barbers tab.',
              style: const TextStyle(color: Colors.grey),
            ),
          )
        else
          ...onDuty.map((b) {
            final isServing = servingIds.contains(b.id);
            final isHere = b.assignedChair == widget.chairNumber;
            final subtitle = isServing
                ? 'Serving a client at chair #${b.assignedChair}'
                : b.assignedChair != null
                ? 'Currently at chair #${b.assignedChair} (will move here)'
                : '${(b.commissionRate * 100).round()}% commission';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.black,
                child: Text(
                  b.name.isNotEmpty ? b.name[0].toUpperCase() : 'B',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(
                b.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(subtitle),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                onPressed: isServing || isHere || _busyBarberId != null
                    ? null
                    : () => _assign(b.id),
                child: _busyBarberId == b.id
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Assign'),
              ),
            );
          }),
        if (offDutyCount > 0 && onDuty.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '$offDutyCount barber(s) off duty are hidden.',
              style: _subtitleStyle,
            ),
          ),
      ],
    );
  }

  Future<void> _assign(String barberId) async {
    setState(() => _busyBarberId = barberId);
    final ok = await runAction(
      context,
      () => ref
          .read(floorPlanProvider.notifier)
          .assignBarber(chairNumber: widget.chairNumber, barberId: barberId),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busyBarberId = null);
    }
  }
}

// -----------------------------------------------------------------------------
// Seat client
// -----------------------------------------------------------------------------

class _SeatClientSheet extends ConsumerStatefulWidget {
  const _SeatClientSheet({required this.station});

  final Station station;

  @override
  ConsumerState<_SeatClientSheet> createState() => _SeatClientSheetState();
}

class _SeatClientSheetState extends ConsumerState<_SeatClientSheet> {
  final _nameController = TextEditingController();
  bool _busy = false;

  Station get station => widget.station;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queueItems = ref.watch(queueProvider).value ?? const [];

    return SheetBody(
      children: [
        Text(
          'Seat Client at Chair #${station.chairNumber}',
          style: _titleStyle,
        ),
        Text(
          'Barber: ${station.activeBarberName ?? 'Assigned'}',
          style: _subtitleStyle,
        ),
        const SizedBox(height: 16),
        if (queueItems.isNotEmpty) ...[
          const Text('Seat from Waiting List:', style: _labelStyle),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: queueItems.length,
              itemBuilder: (c, idx) {
                final item = queueItems[idx];
                return Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${idx + 1}. ${item.clientName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: const Size(double.infinity, 28),
                        ),
                        onPressed: _busy
                            ? null
                            : () =>
                                  _seat(item.clientName, queueItemId: item.id),
                        child: const Text(
                          'Seat Now',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
        ],
        const Text('Or Seat New Walk-in Client:', style: _labelStyle),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          autofocus: queueItems.isEmpty,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _seatWalkIn(),
          decoration: const InputDecoration(
            hintText: 'Enter Client Name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _vacate,
                child: const Text('Vacate Chair'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _seatWalkIn,
                child: const Text('Start Service'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _seatWalkIn() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Enter the client name.', isError: true);
      return;
    }
    await _seat(name);
  }

  Future<void> _seat(String clientName, {String? queueItemId}) {
    return _run(
      () => ref
          .read(floorPlanProvider.notifier)
          .seatClient(
            chairNumber: station.chairNumber,
            clientName: clientName,
            queueItemId: queueItemId,
          ),
    );
  }

  Future<void> _vacate() {
    return _run(
      () => ref
          .read(floorPlanProvider.notifier)
          .unassignBarber(chairNumber: station.chairNumber),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final ok = await runAction(context, action);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }
}

// -----------------------------------------------------------------------------
// Checkout
// -----------------------------------------------------------------------------

class _CheckoutSheet extends ConsumerStatefulWidget {
  const _CheckoutSheet({required this.station});

  final Station station;

  @override
  ConsumerState<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<_CheckoutSheet> {
  static const _tipPercents = [0, 10, 15, 20];

  final _customTipController = TextEditingController();
  final Set<String> _selectedServiceIds = {};
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  int? _tipPercent = 0;
  bool _busy = false;

  Station get station => widget.station;

  @override
  void initState() {
    super.initState();
    final services = ref.read(authProvider).shop?.services ?? const [];
    if (services.isNotEmpty) _selectedServiceIds.add(services.first.id);
  }

  @override
  void dispose() {
    _customTipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(authProvider).shop?.services ?? const [];
    final barbers = ref.watch(barberListProvider).value ?? const [];
    final commissionRate = barbers
        .where((b) => b.id == station.activeBarberId)
        .map((b) => b.commissionRate)
        .firstOrNull;

    final subtotal = services
        .where((s) => _selectedServiceIds.contains(s.id))
        .fold<double>(0, (sum, s) => sum + s.price);
    final tip = _tipPercent != null
        ? subtotal * _tipPercent! / 100
        : (parseAmount(_customTipController.text) ?? 0);
    final barberCut = commissionRate == null ? null : subtotal * commissionRate;
    final totalPayable = subtotal + tip;

    return SheetBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Checkout: ${station.activeClientName ?? 'Client'}',
                    style: _titleStyle,
                  ),
                  Text(
                    'Chair #${station.chairNumber} • Barber: ${station.activeBarberName ?? '—'}',
                    style: _subtitleStyle,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                formatMoney(totalPayable),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Services', style: _labelStyle),
        const SizedBox(height: 8),
        if (services.isEmpty)
          const Text(
            'No services configured. Add services in Settings.',
            style: TextStyle(color: Colors.red),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: services.map((s) {
              return FilterChip(
                selected: _selectedServiceIds.contains(s.id),
                label: Text('${s.name} (${formatMoney(s.price)})'),
                onSelected: (val) => setState(() {
                  if (val) {
                    _selectedServiceIds.add(s.id);
                  } else {
                    _selectedServiceIds.remove(s.id);
                  }
                }),
              );
            }).toList(),
          ),
        const SizedBox(height: 16),
        const Text('Payment', style: _labelStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final method in PaymentMethod.offered)
              ChoiceChip(
                label: Text(_paymentLabel(method)),
                selected: _paymentMethod == method,
                onSelected: (_) => setState(() => _paymentMethod = method),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Tip', style: _labelStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final percent in _tipPercents)
              ChoiceChip(
                label: Text(percent == 0 ? 'No tip' : '$percent%'),
                selected: _tipPercent == percent,
                onSelected: (_) => setState(() => _tipPercent = percent),
              ),
            ChoiceChip(
              label: const Text('Custom'),
              selected: _tipPercent == null,
              onSelected: (_) => setState(() => _tipPercent = null),
            ),
          ],
        ),
        if (_tipPercent == null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _customTipController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Tip amount',
              prefixText: '$currencySymbol ',
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _amount('Services', formatMoney(subtotal)),
              _amount(
                'Barber Cut',
                barberCut == null ? '—' : formatMoney(barberCut),
              ),
              _amount(
                'Shop Cut',
                barberCut == null ? '—' : formatMoney(subtotal - barberCut),
              ),
              _amount('Tip', formatMoney(tip)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          onPressed: _busy || _selectedServiceIds.isEmpty
              ? null
              : () => _checkout(tip),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Complete Cut & Collect Payment'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _cancelService,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Cancel service (no charge)'),
        ),
      ],
    );
  }

  Widget _amount(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  static String _paymentLabel(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.card => 'Card',
    PaymentMethod.transfer => 'Transfer',
  };

  Future<void> _checkout(double tip) async {
    if (tip.isNaN || tip < 0) {
      showSnack(context, 'Enter a valid tip amount.', isError: true);
      return;
    }
    setState(() => _busy = true);
    final services = ref.read(authProvider).shop?.services ?? const [];
    // Keep the catalog order so receipts read consistently.
    final serviceIds = services
        .map((s) => s.id)
        .where(_selectedServiceIds.contains)
        .toList();
    final ok = await runAction(
      context,
      () => ref
          .read(floorPlanProvider.notifier)
          .checkoutService(
            chairNumber: station.chairNumber,
            serviceIds: serviceIds,
            paymentMethod: _paymentMethod,
            tip: tip,
          ),
      successMessage:
          'Payment recorded for ${station.activeClientName ?? 'client'}.',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _cancelService() async {
    final confirmed = await confirmAction(
      context,
      title: 'Cancel service?',
      message:
          'The chair will be freed without recording a payment. '
          'Use this only if the client left or was seated by mistake.',
      confirmLabel: 'Cancel service',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref
          .read(floorPlanProvider.notifier)
          .cancelService(chairNumber: station.chairNumber),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }
}
