import 'package:siz/core/repositories/shop_repository.dart';
import 'package:siz/core/ui/ui_helpers.dart';
import 'package:siz/features/auth_onboarding/domain/shop_profile.dart';
import 'package:siz/features/auth_onboarding/presentation/auth_providers.dart';
import 'package:siz/features/barbers/presentation/barber_providers.dart';
import 'package:siz/features/floor_plan/presentation/floor_plan_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int? _chairCount;
  bool _savingChairs = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final shop = authState.shop;

    if (shop == null) {
      return const Scaffold(body: Center(child: Text('No shop loaded')));
    }

    final chairCount = _chairCount ?? shop.totalChairs;

    return Scaffold(
      appBar: AppBar(title: const Text('Shop Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ShopProfileCard(shop: shop),
          const SizedBox(height: 16),
          _ClientsSeeCard(shop: shop),
          const SizedBox(height: 16),
          _ServicesCard(services: shop.services),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Floor Plan Chair Capacity',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Chairs serving a client cannot be removed. Barbers on '
                    'removed chairs are unassigned.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total Barber Chairs: $chairCount',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black,
                        ),
                        icon: const Icon(Icons.remove, color: Colors.white),
                        onPressed: chairCount > ShopRepository.minChairs
                            ? () => setState(() => _chairCount = chairCount - 1)
                            : null,
                      ),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black,
                        ),
                        icon: const Icon(Icons.add, color: Colors.white),
                        onPressed: chairCount < ShopRepository.maxChairs
                            ? () => setState(() => _chairCount = chairCount + 1)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: chairCount.toDouble(),
                    min: ShopRepository.minChairs.toDouble(),
                    max: ShopRepository.maxChairs.toDouble(),
                    divisions:
                        ShopRepository.maxChairs - ShopRepository.minChairs,
                    label: '$chairCount Chairs',
                    onChanged: (val) =>
                        setState(() => _chairCount = val.round()),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    onPressed: chairCount != shop.totalChairs && !_savingChairs
                        ? () => _applyChairCount(chairCount)
                        : null,
                    child: const Text('Apply Layout Changes'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _DataStorageCard(),
          const SizedBox(height: 24),
          if (authState.owner != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Signed in as ${authState.owner!.fullName} (${authState.owner!.email})',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Log Out'),
            onPressed: _logout,
          ),
        ],
      ),
    );
  }

  Future<void> _applyChairCount(int count) async {
    setState(() => _savingChairs = true);
    final ok = await runAction(context, () async {
      await ref.read(authProvider.notifier).updateChairCount(count);
      ref.invalidate(barberListProvider);
      await ref.read(floorPlanProvider.notifier).loadStations();
    }, successMessage: 'Floor plan updated to $count chairs.');
    if (!mounted) return;
    setState(() {
      _savingChairs = false;
      if (!ok) _chairCount = null; // Snap back to the saved value.
    });
  }

  Future<void> _logout() async {
    final confirmed = await confirmAction(
      context,
      title: 'Log out?',
      message: 'You will need your email and password to sign back in.',
      confirmLabel: 'Log out',
    );
    if (!confirmed) return;
    await ref.read(authProvider.notifier).logout();
  }
}

class _ShopProfileCard extends StatelessWidget {
  const _ShopProfileCard({required this.shop});

  final ShopProfile shop;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.storefront, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shop.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    shop.address,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  Text(
                    shop.phone,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit shop details',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showAppSheet<void>(
                context,
                (_) => _ShopDetailsSheet(shop: shop),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopDetailsSheet extends ConsumerStatefulWidget {
  const _ShopDetailsSheet({required this.shop});

  final ShopProfile shop;

  @override
  ConsumerState<_ShopDetailsSheet> createState() => _ShopDetailsSheetState();
}

class _ShopDetailsSheetState extends ConsumerState<_ShopDetailsSheet> {
  late final _nameCtrl = TextEditingController(text: widget.shop.name);
  late final _addressCtrl = TextEditingController(text: widget.shop.address);
  late final _phoneCtrl = TextEditingController(text: widget.shop.phone);
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      children: [
        const Text(
          'Shop Details',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Barbershop Name',
            prefixIcon: Icon(Icons.storefront),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressCtrl,
          decoration: const InputDecoration(
            labelText: 'Address',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref
          .read(authProvider.notifier)
          .updateShopDetails(
            name: _nameCtrl.text,
            address: _addressCtrl.text,
            phone: _phoneCtrl.text,
          ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }
}

class _ServicesCard extends ConsumerWidget {
  const _ServicesCard({required this.services});

  final List<ServiceItem> services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Services & Pricing',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => showAppSheet<void>(
                    context,
                    (_) => const _ServiceEditorSheet(),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (services.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Add at least one service to check out clients.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ...services.map(
              (s) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.content_cut),
                title: Text(
                  s.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${s.durationMinutes} min'),
                trailing: Text(
                  formatMoney(s.price),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                onTap: () => showAppSheet<void>(
                  context,
                  (_) => _ServiceEditorSheet(service: s),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceEditorSheet extends ConsumerStatefulWidget {
  const _ServiceEditorSheet({this.service});

  /// Null when adding a new service.
  final ServiceItem? service;

  @override
  ConsumerState<_ServiceEditorSheet> createState() =>
      _ServiceEditorSheetState();
}

class _ServiceEditorSheetState extends ConsumerState<_ServiceEditorSheet> {
  late final _nameCtrl = TextEditingController(text: widget.service?.name);
  late final _priceCtrl = TextEditingController(
    text: widget.service?.price.toStringAsFixed(2),
  );
  late final _durationCtrl = TextEditingController(
    text: '${widget.service?.durationMinutes ?? 30}',
  );
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.service != null;

    return SheetBody(
      children: [
        Text(
          isEditing ? 'Edit Service' : 'New Service',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Service Name'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Price',
                  prefixText: '$currencySymbol ',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _durationCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration',
                  suffixText: 'min',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          onPressed: _busy ? null : _save,
          child: const Text('Save Service'),
        ),
        if (isEditing) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete service'),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    final price = parseAmount(_priceCtrl.text);
    final duration = int.tryParse(_durationCtrl.text.trim());
    if (price == null || duration == null) {
      showSnack(context, 'Enter a valid price and duration.', isError: true);
      return;
    }
    await _run(
      () => ref
          .read(authProvider.notifier)
          .saveService(
            serviceId: widget.service?.id,
            name: _nameCtrl.text,
            price: price,
            durationMinutes: duration,
          ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete ${widget.service!.name}?',
      message: 'Past sales that used this service are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(authProvider.notifier).deleteService(widget.service!.id),
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

class _DataStorageCard extends StatelessWidget {
  const _DataStorageCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.phone_android_outlined),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data stored on this device',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Shop data lives in the app\'s private storage. Passwords '
                    'are hashed with PBKDF2 and your session is kept in the '
                    'system keychain.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether clients find the salon in their list, and whether it is open.
class _ClientsSeeCard extends ConsumerWidget {
  const _ClientsSeeCard({required this.shop});

  final ShopProfile shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authProvider.notifier);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'What clients see',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Clients find the salon in their list of salons, with its '
              'waiting line, barbers, prices and photos.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          SwitchListTile(
            title: const Text('Show my salon to clients'),
            subtitle: Text(
              shop.isListed
                  ? 'Clients can find you in the list of salons.'
                  : 'Hidden from clients.',
            ),
            value: shop.isListed,
            onChanged: (v) => runAction(context, () => auth.setShopListed(v)),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Open now'),
            subtitle: Text(
              shop.isOpen
                  ? 'Clients see the salon as open.'
                  : 'Clients see the salon as closed.',
            ),
            value: shop.isOpen,
            onChanged: (v) => runAction(context, () => auth.setShopOpen(v)),
          ),
        ],
      ),
    );
  }
}
