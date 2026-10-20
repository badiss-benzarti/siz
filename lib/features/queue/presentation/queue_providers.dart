import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/repositories/queue_repository.dart';
import '../../auth_onboarding/presentation/auth_providers.dart';
import '../domain/queue_item.dart';
import '../../../core/providers/data_revision.dart';

final queueRepositoryProvider = Provider<QueueRepository>((ref) {
  return QueueRepository(dbService: ref.watch(databaseServiceProvider));
});

class QueueNotifier extends AsyncNotifier<List<QueueItem>> {
  @override
  Future<List<QueueItem>> build() async {
    ref.watch(dataRevisionProvider);
    final shopId = ref.watch(currentShopIdProvider);
    if (shopId == null) return const [];
    return ref.read(queueRepositoryProvider).getWaitingQueue(shopId);
  }

  QueueRepository get _repository => ref.read(queueRepositoryProvider);
  String? get _shopId => ref.read(currentShopIdProvider);

  Future<void> loadQueue() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> addToQueue({
    required String clientName,
    String? clientPhone,
    String? requestedBarberId,
    String? notes,
  }) async {
    final shopId = _shopId;
    if (shopId == null) return;
    await _repository.addToQueue(
      shopId: shopId,
      clientName: clientName,
      clientPhone: clientPhone,
      requestedBarberId: requestedBarberId,
      notes: notes,
    );
    await loadQueue();
  }

  Future<void> removeFromQueue(String id) async {
    await _repository.removeFromQueue(id);
    await loadQueue();
  }
}

final queueProvider = AsyncNotifierProvider<QueueNotifier, List<QueueItem>>(
  QueueNotifier.new,
);
