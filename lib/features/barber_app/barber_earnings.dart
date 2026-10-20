import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_service.dart';
import '../../core/providers/core_providers.dart';
import '../finance/domain/service_ticket.dart';
import 'barber_session.dart';

/// One of the barber's sales, as they see it: their share only.
class EarningLine {
  const EarningLine({
    required this.time,
    required this.clientName,
    required this.services,
    required this.commission,
    required this.tip,
    required this.paymentMethod,
    required this.chairNumber,
  });

  final DateTime time;
  final String clientName;
  final String services;
  final double commission;
  final double tip;
  final PaymentMethod paymentMethod;
  final int chairNumber;

  /// What the barber takes home from this sale.
  double get earned => commission + tip;
}

enum EarningsPeriod { today, last7Days, last30Days }

/// Totals for one period, plus the last 7 days for the chart.
class EarningsSummary {
  EarningsSummary._({
    required this.lines,
    required this.commission,
    required this.tips,
    required this.lastSevenDays,
  });

  /// [lines] cover at least the last 30 days; [now] fixes "today".
  factory EarningsSummary.of(
    List<EarningLine> lines,
    EarningsPeriod period,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (period) {
      EarningsPeriod.today => today,
      EarningsPeriod.last7Days => today.subtract(const Duration(days: 6)),
      EarningsPeriod.last30Days => today.subtract(const Duration(days: 29)),
    };
    final inPeriod = [
      for (final l in lines)
        if (!l.time.isBefore(from)) l,
    ]..sort((a, b) => b.time.compareTo(a.time));

    final week = List<double>.filled(7, 0);
    for (final l in lines) {
      final day = DateTime(l.time.year, l.time.month, l.time.day);
      final index = 6 - today.difference(day).inDays;
      if (index >= 0 && index < 7) week[index] += l.earned;
    }

    return EarningsSummary._(
      lines: inPeriod,
      commission: inPeriod.fold(0, (s, l) => s + l.commission),
      tips: inPeriod.fold(0, (s, l) => s + l.tip),
      lastSevenDays: week,
    );
  }

  /// Newest first.
  final List<EarningLine> lines;
  final double commission;
  final double tips;

  /// Earned per day, oldest first; the last entry is today.
  final List<double> lastSevenDays;

  double get earned => commission + tips;
  int get clientsServed => lines.length;
  double get averagePerClient => lines.isEmpty ? 0 : earned / lines.length;
}

/// The barber's own sales. Failures are thrown as `AppException`.
abstract class BarberEarningsRepository {
  Future<List<EarningLine>> since(String barberId, DateTime from);
}

/// [BarberEarningsRepository] reading the salon's tickets on this device.
class LocalBarberEarningsRepository implements BarberEarningsRepository {
  LocalBarberEarningsRepository(this._db);

  final DatabaseService _db;

  @override
  Future<List<EarningLine>> since(String barberId, DateTime from) async {
    final db = await _db.database;
    final rows = await db.query(
      'tickets',
      where: 'barber_id = ? AND timestamp >= ?',
      whereArgs: [barberId, from.toIso8601String()],
      orderBy: 'timestamp DESC',
    );
    return [
      for (final r in rows)
        EarningLine(
          time: DateTime.parse(r['timestamp'] as String),
          clientName: r['client_name'] as String,
          services: r['service_names'] as String,
          commission: (r['barber_cut'] as num).toDouble(),
          tip: (r['tip'] as num).toDouble(),
          paymentMethod:
              PaymentMethod.values.asNameMap()[r['payment_method']] ??
              PaymentMethod.cash,
          chairNumber: r['chair_number'] as int,
        ),
    ];
  }
}

final barberEarningsRepositoryProvider = Provider<BarberEarningsRepository>(
  (ref) => LocalBarberEarningsRepository(ref.watch(databaseServiceProvider)),
);

/// The last 30 days of the barber's sales, loaded once per visit; every
/// period and the chart are computed from it on the phone.
final barberEarningLinesProvider =
    FutureProvider.autoDispose<List<EarningLine>>((ref) async {
      final barberId = ref.watch(
        barberSessionProvider.select((s) => s.link?.barberId),
      );
      if (barberId == null) return const [];
      final now = DateTime.now();
      final from = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 29));
      return ref.read(barberEarningsRepositoryProvider).since(barberId, from);
    });

final barberEarningsPeriodProvider =
    NotifierProvider<EarningsPeriodNotifier, EarningsPeriod>(
      EarningsPeriodNotifier.new,
    );

class EarningsPeriodNotifier extends Notifier<EarningsPeriod> {
  @override
  EarningsPeriod build() => EarningsPeriod.today;

  void select(EarningsPeriod period) => state = period;
}
