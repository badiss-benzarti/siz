import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../auth_onboarding/presentation/auth_providers.dart';
import '../domain/finance_summary.dart';
import '../../../core/providers/data_revision.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(dbService: ref.watch(databaseServiceProvider));
});

enum FinancePeriod { today, last7Days, last30Days, custom }

/// The reporting period shown on the finance dashboard.
class FinanceRange {
  const FinanceRange(this.period, this.start, this.end);

  factory FinanceRange.preset(FinancePeriod period, {DateTime? now}) {
    final today = _startOfDay(now ?? DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    return switch (period) {
      FinancePeriod.last7Days => FinanceRange(
        period,
        today.subtract(const Duration(days: 6)),
        tomorrow,
      ),
      FinancePeriod.last30Days => FinanceRange(
        period,
        today.subtract(const Duration(days: 29)),
        tomorrow,
      ),
      _ => FinanceRange(FinancePeriod.today, today, tomorrow),
    };
  }

  /// A custom range covering whole days, inclusive of the picked end day.
  factory FinanceRange.custom(DateTimeRange range) {
    return FinanceRange(
      FinancePeriod.custom,
      _startOfDay(range.start),
      _startOfDay(range.end).add(const Duration(days: 1)),
    );
  }

  final FinancePeriod period;

  /// Inclusive start.
  final DateTime start;

  /// Exclusive end.
  final DateTime end;

  bool get isSingleDay => end.difference(start).inHours <= 24;

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
}

class FinanceRangeNotifier extends Notifier<FinanceRange> {
  @override
  FinanceRange build() => FinanceRange.preset(FinancePeriod.today);

  void select(FinancePeriod period) => state = FinanceRange.preset(period);

  void selectCustom(DateTimeRange range) => state = FinanceRange.custom(range);
}

final financeRangeProvider =
    NotifierProvider<FinanceRangeNotifier, FinanceRange>(
      FinanceRangeNotifier.new,
    );

class FinanceNotifier extends AsyncNotifier<FinanceSummary> {
  @override
  Future<FinanceSummary> build() async {
    ref.watch(dataRevisionProvider);
    final shopId = ref.watch(currentShopIdProvider);
    final range = ref.watch(financeRangeProvider);
    if (shopId == null) return FinanceSummary.fromTickets(const []);
    return ref
        .read(financeRepositoryProvider)
        .getSummary(shopId: shopId, start: range.start, end: range.end);
  }

  Future<void> loadSummary() async {
    // "Today" presets are recomputed so a dashboard left open overnight
    // rolls over to the new day on refresh.
    final range = ref.read(financeRangeProvider);
    if (range.period != FinancePeriod.custom) {
      ref.read(financeRangeProvider.notifier).select(range.period);
    }
    ref.invalidateSelf();
    await future;
  }
}

final financeProvider = AsyncNotifierProvider<FinanceNotifier, FinanceSummary>(
  FinanceNotifier.new,
);
