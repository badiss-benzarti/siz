import 'package:siz/features/barber_app/barber_earnings.dart';
import 'package:siz/features/finance/domain/service_ticket.dart';
import 'package:flutter_test/flutter_test.dart';

EarningLine _sale(DateTime time, double commission, {double tip = 0}) =>
    EarningLine(
      time: time,
      clientName: 'Client',
      services: 'Haircut',
      commission: commission,
      tip: tip,
      paymentMethod: PaymentMethod.cash,
      chairNumber: 1,
    );

void main() {
  final now = DateTime(2026, 10, 8, 18);
  final lines = [
    _sale(DateTime(2026, 10, 8, 10), 15, tip: 2), // today
    _sale(DateTime(2026, 10, 8, 9), 9), // today
    _sale(DateTime(2026, 10, 6, 15), 21, tip: 3), // 2 days ago
    _sale(DateTime(2026, 10, 1, 12), 12), // 7 days ago: outside the week
    _sale(DateTime(2026, 9, 20, 12), 10), // 18 days ago
  ];

  test('today counts commission and tips of today only', () {
    final s = EarningsSummary.of(lines, EarningsPeriod.today, now);
    expect(s.clientsServed, 2);
    expect(s.commission, 24);
    expect(s.tips, 2);
    expect(s.earned, 26);
    expect(s.averagePerClient, 13);
  });

  test('the last 7 days include today and the 6 days before', () {
    final s = EarningsSummary.of(lines, EarningsPeriod.last7Days, now);
    expect(s.clientsServed, 3);
    expect(s.earned, 50);
    // Newest first.
    expect(s.lines.first.time, DateTime(2026, 10, 8, 10));
  });

  test('the last 30 days include everything loaded', () {
    final s = EarningsSummary.of(lines, EarningsPeriod.last30Days, now);
    expect(s.clientsServed, 5);
    expect(s.earned, 72);
  });

  test('the chart has one bar per day, today last', () {
    final s = EarningsSummary.of(lines, EarningsPeriod.today, now);
    expect(s.lastSevenDays, [0, 0, 0, 0, 24, 0, 26]);
  });

  test('no sales: zero everywhere, no division by zero', () {
    final s = EarningsSummary.of(const [], EarningsPeriod.today, now);
    expect(s.earned, 0);
    expect(s.averagePerClient, 0);
    expect(s.lastSevenDays, everyElement(0));
  });
}
