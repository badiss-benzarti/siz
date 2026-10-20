import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth_onboarding/presentation/auth_providers.dart';
import '../../finance/domain/finance_summary.dart';
import '../../finance/presentation/finance_providers.dart';
import '../../../core/providers/data_revision.dart';

/// Clients served by the shop, derived from the ticket ledger.
final clientHistoryProvider = FutureProvider<List<ClientHistory>>((ref) async {
  ref.watch(dataRevisionProvider);
  final shopId = ref.watch(currentShopIdProvider);
  if (shopId == null) return const [];
  return ref.read(financeRepositoryProvider).getClientHistory(shopId);
});
