import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/ui/dashboard_widgets.dart';
import 'client_activity.dart';
import 'client_directory.dart';
import 'client_salon_page.dart';

const _ink = Color(0xFF111111);
const _muted = Color(0xFF6B7280);

Color loadColor(SalonLoad load) => switch (load) {
  SalonLoad.available => const Color(0xFF10B981),
  SalonLoad.busy => const Color(0xFFF59E0B),
  SalonLoad.closed => const Color(0xFF9CA3AF),
};

String loadLabel(ClientSalon s) => switch (s.load) {
  SalonLoad.closed => 'Closed',
  _ when s.waitingCount == 0 => 'No wait',
  _ => '${s.waitingCount} waiting',
};

/// Client home: every salon shown to clients, open ones with the shortest
/// line first. Search by name or address, or keep only open salons.
class ClientSalonsScreen extends ConsumerStatefulWidget {
  const ClientSalonsScreen({super.key});

  @override
  ConsumerState<ClientSalonsScreen> createState() => _ClientSalonsScreenState();
}

class _ClientSalonsScreenState extends ConsumerState<ClientSalonsScreen> {
  final _search = TextEditingController();
  bool _openOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ClientSalon> _visible(List<ClientSalon> all) {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final s in all)
        if ((!_openOnly || s.isOpen) &&
            (q.isEmpty ||
                s.name.toLowerCase().contains(q) ||
                s.address.toLowerCase().contains(q)))
          s,
    ]..sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      final byWait = a.waitingCount.compareTo(b.waitingCount);
      return byWait != 0 ? byWait : a.name.compareTo(b.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final salons = ref.watch(salonListProvider);
    final favorites = <String>{
      for (final s
          in ref.watch(favoriteSalonsProvider).value ?? <ClientSalon>[])
        s.id,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Salons')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(salonListProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search a salon or an area',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Open now'),
                selected: _openOnly,
                onSelected: (v) => setState(() => _openOnly = v),
              ),
            ),
            const SizedBox(height: 6),
            switch (salons) {
              AsyncData(:final value) => _list(_visible(value), favorites),
              AsyncError(:final error) => EmptyBox(describeError(error)),
              _ => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }

  Widget _list(List<ClientSalon> salons, Set<String> favorites) {
    if (salons.isEmpty) {
      return EmptyBox(
        _search.text.isEmpty && !_openOnly
            ? 'No salons yet. Owners appear here once their salon is set up.'
            : 'No salon matches.',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              salons.length == 1 ? '1 salon' : '${salons.length} salons',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        ),
        for (final s in salons)
          SalonCard(salon: s, isFavorite: favorites.contains(s.id)),
      ],
    );
  }
}

/// One salon in a list: name, address, its line and chairs.
class SalonCard extends StatelessWidget {
  const SalonCard({super.key, required this.salon, this.isFavorite = false});

  final ClientSalon salon;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ClientSalonPage(shopId: salon.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.content_cut, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            salon.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (isFavorite) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.favorite,
                            size: 15,
                            color: Color(0xFFE11D48),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      salon.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        LoadPill(salon),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.chair_outlined,
                          size: 15,
                          color: _muted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${salon.totalChairs} chairs',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill: colored dot and "No wait" / "3 waiting" / "Closed".
class LoadPill extends StatelessWidget {
  const LoadPill(this.salon, {super.key});

  final ClientSalon salon;

  @override
  Widget build(BuildContext context) {
    final color = loadColor(salon.load);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            loadLabel(salon),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
