import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/repositories/floor_plan_repository.dart';
import '../../auth_onboarding/presentation/auth_providers.dart';
import '../../barbers/presentation/barber_providers.dart';
import '../../clients/presentation/client_providers.dart';
import '../../finance/domain/service_ticket.dart';
import '../../finance/presentation/finance_providers.dart';
import '../../queue/presentation/queue_providers.dart';
import '../domain/station.dart';
import '../../../core/providers/data_revision.dart';

final floorPlanRepositoryProvider = Provider<FloorPlanRepository>((ref) {
  return FloorPlanRepository(dbService: ref.watch(databaseServiceProvider));
});

class FloorPlanNotifier extends AsyncNotifier<List<Station>> {
  @override
  Future<List<Station>> build() async {
    ref.watch(dataRevisionProvider);
    final shopId = ref.watch(currentShopIdProvider);
    if (shopId == null) return const [];
    return ref.read(floorPlanRepositoryProvider).getStations(shopId);
  }

  FloorPlanRepository get _repository => ref.read(floorPlanRepositoryProvider);
  String? get _shopId => ref.read(currentShopIdProvider);

  Future<void> loadStations() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> assignBarber({
    required int chairNumber,
    required String barberId,
  }) async {
    final shopId = _shopId;
    if (shopId == null) return;
    await _repository.assignBarberToChair(
      shopId: shopId,
      chairNumber: chairNumber,
      barberId: barberId,
    );
    ref.invalidate(barberListProvider);
    await loadStations();
  }

  Future<void> unassignBarber({required int chairNumber}) async {
    final shopId = _shopId;
    if (shopId == null) return;
    await _repository.unassignBarber(shopId: shopId, chairNumber: chairNumber);
    ref.invalidate(barberListProvider);
    await loadStations();
  }

  Future<void> seatClient({
    required int chairNumber,
    required String clientName,
    String? queueItemId,
  }) async {
    final shopId = _shopId;
    if (shopId == null) return;
    await _repository.seatClient(
      shopId: shopId,
      chairNumber: chairNumber,
      clientName: clientName,
      queueItemId: queueItemId,
    );
    if (queueItemId != null) ref.invalidate(queueProvider);
    await loadStations();
  }

  Future<void> cancelService({required int chairNumber}) async {
    final shopId = _shopId;
    if (shopId == null) return;
    await _repository.cancelService(shopId: shopId, chairNumber: chairNumber);
    await loadStations();
  }

  Future<ServiceTicket?> checkoutService({
    required int chairNumber,
    required List<String> serviceIds,
    required PaymentMethod paymentMethod,
    double tip = 0.0,
  }) async {
    final shopId = _shopId;
    if (shopId == null) return null;
    final ticket = await _repository.checkoutService(
      shopId: shopId,
      chairNumber: chairNumber,
      serviceIds: serviceIds,
      paymentMethod: paymentMethod,
      tip: tip,
    );
    ref
      ..invalidate(financeProvider)
      ..invalidate(clientHistoryProvider);
    await loadStations();
    return ticket;
  }
}

final floorPlanProvider =
    AsyncNotifierProvider<FloorPlanNotifier, List<Station>>(
      FloorPlanNotifier.new,
    );
