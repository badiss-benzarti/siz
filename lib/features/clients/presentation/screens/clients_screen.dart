import 'package:siz/core/ui/ui_helpers.dart';
import 'package:siz/features/clients/presentation/client_providers.dart';
import 'package:siz/features/queue/presentation/queue_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ClientsScreen extends ConsumerWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Clients'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(queueProvider);
                ref.invalidate(clientHistoryProvider);
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.black,
            indicatorColor: Colors.black,
            tabs: [
              Tab(text: 'Waiting'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: const TabBarView(children: [_WaitingTab(), _HistoryTab()]),
      ),
    );
  }
}

class _WaitingTab extends ConsumerWidget {
  const _WaitingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(queueProvider);

    return queueAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => const Center(child: Text('Could not load the queue.')),
      data: (items) {
        if (items.isEmpty) {
          return const _EmptyState(
            icon: Icons.event_seat_outlined,
            title: 'No Clients in Waiting Area',
            message: 'Use "Reserve Waiting Spot" on the Floor Plan\nto register walk-in clients.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (ctx, index) {
            final item = items[index];
            final time = DateFormat('h:mm a').format(item.createdAt);
            final waited = DateTime.now().difference(item.createdAt).inMinutes;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.black,
                  child: Text(
                    '${index + 1}',
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
                    'Arrived $time ($waited min)',
                    if (item.clientPhone != null) item.clientPhone!,
                  ].join(' • '),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  tooltip: 'Remove from queue',
                  onPressed: () async {
                    final confirmed = await confirmAction(
                      context,
                      title: 'Remove ${item.clientName}?',
                      message: 'The client will be taken off the waiting list.',
                      confirmLabel: 'Remove',
                      destructive: true,
                    );
                    if (!confirmed || !context.mounted) return;
                    await runAction(
                      context,
                      () => ref
                          .read(queueProvider.notifier)
                          .removeFromQueue(item.id),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab();

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(clientHistoryProvider);

    return historyAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) =>
          const Center(child: Text('Could not load client history.')),
      data: (clients) {
        if (clients.isEmpty) {
          return const _EmptyState(
            icon: Icons.badge_outlined,
            title: 'No Clients Served Yet',
            message: 'Clients appear here after their first checkout.',
          );
        }

        final query = _query.toLowerCase();
        final filtered = query.isEmpty
            ? clients
            : clients
                  .where(
                    (c) =>
                        c.clientName.toLowerCase().contains(query) ||
                        (c.clientPhone ?? '').contains(query),
                  )
                  .toList();
        final dateFormat = DateFormat('d MMM yyyy');

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search by name or phone',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (ctx, index) {
                  final c = filtered[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFF3F4F6),
                        child: Text(
                          c.clientName.isNotEmpty
                              ? c.clientName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        c.clientName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        [
                          '${c.visits} visit${c.visits == 1 ? '' : 's'}',
                          'Last: ${dateFormat.format(c.lastVisit)}',
                          if (c.clientPhone != null) c.clientPhone!,
                        ].join(' • '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(
                        formatMoney(c.totalSpent),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
