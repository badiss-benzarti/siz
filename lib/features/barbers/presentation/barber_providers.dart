import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/repositories/barber_repository.dart';
import '../../auth_onboarding/presentation/auth_providers.dart';
import '../../floor_plan/presentation/floor_plan_providers.dart';
import '../domain/barber.dart';
import '../../../core/providers/data_revision.dart';

final barberRepositoryProvider = Provider<BarberRepository>((ref) {
  return BarberRepository(dbService: ref.watch(databaseServiceProvider));
});

class BarberNotifier extends AsyncNotifier<List<Barber>> {
  @override
  Future<List<Barber>> build() async {
    ref.watch(dataRevisionProvider);
    final shopId = ref.watch(currentShopIdProvider);
    if (shopId == null) return const [];
    return ref.read(barberRepositoryProvider).getBarbers(shopId);
  }

  BarberRepository get _repository => ref.read(barberRepositoryProvider);
  String? get _shopId => ref.read(currentShopIdProvider);

  Future<void> loadBarbers() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> addBarber({
    required String name,
    required String phone,
    required double commissionRate,
  }) async {
    final shopId = _shopId;
    if (shopId == null) return;
    await _repository.addBarber(
      shopId: shopId,
      name: name,
      phone: phone,
      commissionRate: commissionRate,
    );
    await loadBarbers();
  }

  Future<void> updateBarber({
    required String barberId,
    required String name,
    required String phone,
    required double commissionRate,
  }) async {
    await _repository.updateBarber(
      barberId: barberId,
      name: name,
      phone: phone,
      commissionRate: commissionRate,
    );
    await _reloadWithFloor();
  }

  Future<void> toggleDuty(String barberId, bool isOnDuty) async {
    await _repository.setOnDuty(barberId, isOnDuty);
    await _reloadWithFloor();
  }

  Future<void> archiveBarber(String barberId) async {
    await _repository.archiveBarber(barberId);
    await _reloadWithFloor();
  }

  /// Barber changes can free chairs or rename the barber shown on them.
  Future<void> _reloadWithFloor() async {
    ref.invalidate(floorPlanProvider);
    await loadBarbers();
  }
}

final barberListProvider = AsyncNotifierProvider<BarberNotifier, List<Barber>>(
  BarberNotifier.new,
);
