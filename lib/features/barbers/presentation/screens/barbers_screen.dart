import 'package:siz/core/ui/ui_helpers.dart';
import 'package:siz/features/barbers/domain/barber.dart';
import 'package:siz/features/barbers/presentation/barber_providers.dart';
import 'package:siz/features/barbers/presentation/screens/barber_invite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BarbersScreen extends ConsumerWidget {
  const BarbersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final barbersAsync = ref.watch(barberListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barbers & Staff Roster'),
        actions: [
          IconButton(
            tooltip: 'Add barber',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      body: barbersAsync.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(barberListProvider),
            child: const Text('Could not load barbers. Tap to retry.'),
          ),
        ),
        data: (barbers) {
          if (barbers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.group_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No Barbers Registered Yet',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => _openEditor(context),
                    child: const Text('Add First Barber'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: barbers.length,
            itemBuilder: (ctx, index) => _BarberCard(
              barber: barbers[index],
              onEdit: () => _openEditor(context, barber: barbers[index]),
            ),
          );
        },
      ),
    );
  }

  void _openEditor(BuildContext context, {Barber? barber}) {
    showAppSheet<void>(context, (_) => _BarberEditorSheet(barber: barber));
  }
}

class _BarberCard extends ConsumerWidget {
  const _BarberCard({required this.barber, required this.onEdit});

  final Barber barber;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commissionPercent = (barber.commissionRate * 100).round();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: barber.isOnDuty
                    ? Colors.black
                    : const Color(0xFFD1D5DB),
                child: Text(
                  barber.name.isNotEmpty ? barber.name[0].toUpperCase() : 'B',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            barber.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _DutyBadge(isOnDuty: barber.isOnDuty),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (barber.phone.isNotEmpty) barber.phone,
                        'Commission: $commissionPercent%',
                      ].join(' • '),
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                    if (barber.assignedChair != null)
                      Text(
                        'Assigned to Chair #${barber.assignedChair}',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 4),
                    BarberAppLink(barber: barber),
                  ],
                ),
              ),
              Switch(
                value: barber.isOnDuty,
                onChanged: (val) => runAction(
                  context,
                  () => ref
                      .read(barberListProvider.notifier)
                      .toggleDuty(barber.id, val),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DutyBadge extends StatelessWidget {
  const _DutyBadge({required this.isOnDuty});

  final bool isOnDuty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isOnDuty ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isOnDuty ? 'ON DUTY' : 'OFF DUTY',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: isOnDuty ? const Color(0xFF166534) : const Color(0xFF6B7280),
        ),
      ),
    );
  }
}

class _BarberEditorSheet extends ConsumerStatefulWidget {
  const _BarberEditorSheet({this.barber});

  /// Null when adding a new barber.
  final Barber? barber;

  @override
  ConsumerState<_BarberEditorSheet> createState() => _BarberEditorSheetState();
}

class _BarberEditorSheetState extends ConsumerState<_BarberEditorSheet> {
  late final _nameCtrl = TextEditingController(text: widget.barber?.name);
  late final _phoneCtrl = TextEditingController(text: widget.barber?.phone);
  late double _commissionRate = widget.barber?.commissionRate ?? 0.60;
  bool _busy = false;

  bool get _isEditing => widget.barber != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_commissionRate * 100).round();

    return SheetBody(
      children: [
        Text(
          _isEditing ? 'Edit Barber' : 'Add Barber Staff',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Barber Full Name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone Number'),
        ),
        const SizedBox(height: 16),
        Text(
          'Commission Rate: $percent%',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Share of service revenue paid to the barber. Tips go fully to the barber.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        Slider(
          value: _commissionRate,
          min: 0,
          max: 1,
          divisions: 20,
          label: '$percent%',
          onChanged: (val) => setState(() => _commissionRate = val),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          onPressed: _busy ? null : _save,
          child: Text(_isEditing ? 'Save Changes' : 'Save Barber'),
        ),
        if (_isEditing) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _busy ? null : _archive,
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Remove from roster'),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Enter the barber name.', isError: true);
      return;
    }
    final notifier = ref.read(barberListProvider.notifier);
    final barber = widget.barber;
    await _run(
      () => barber == null
          ? notifier.addBarber(
              name: name,
              phone: _phoneCtrl.text,
              commissionRate: _commissionRate,
            )
          : notifier.updateBarber(
              barberId: barber.id,
              name: name,
              phone: _phoneCtrl.text,
              commissionRate: _commissionRate,
            ),
    );
  }

  Future<void> _archive() async {
    final barber = widget.barber!;
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${barber.name}?',
      message:
          'They will leave the roster and their chair will be freed. '
          'Their past sales stay in your financial reports.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(barberListProvider.notifier).archiveBarber(barber.id),
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
