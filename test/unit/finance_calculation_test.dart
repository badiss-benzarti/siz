import 'package:siz/features/finance/domain/finance_summary.dart';
import 'package:siz/features/finance/domain/service_ticket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Finance & Commission Calculations', () {
    test(
      'FinanceSummary accurately calculates splits, tips, and register totals',
      () {
        final now = DateTime.now();

        final tickets = [
          ServiceTicket(
            id: 't1',
            shopId: 's1',
            clientName: 'John Doe',
            barberId: 'b1',
            chairNumber: 1,
            serviceNames: ['Haircut'],
            totalPrice: 30.0,
            barberCut: 18.0, // 60%
            shopCut: 12.0, // 40%
            tip: 5.0,
            paymentMethod: PaymentMethod.cash,
            timestamp: now,
          ),
          ServiceTicket(
            id: 't2',
            shopId: 's1',
            clientName: 'Alex Smith',
            barberId: 'b2',
            chairNumber: 2,
            serviceNames: ['Beard Trim', 'Haircut'],
            totalPrice: 45.0,
            barberCut: 31.5, // 70%
            shopCut: 13.5, // 30%
            tip: 10.0,
            paymentMethod: PaymentMethod.card,
            timestamp: now,
          ),
        ];

        final summary = FinanceSummary.fromTickets(tickets);

        expect(summary.totalClientsServed, equals(2));
        expect(summary.grossRevenue, equals(75.0)); // 30 + 45
        expect(summary.barberPayouts, equals(49.5)); // 18 + 31.5
        expect(summary.shopNetRevenue, equals(25.5)); // 12 + 13.5
        expect(summary.tipsTotal, equals(15.0)); // 5 + 10
        expect(summary.cashTotal, equals(35.0)); // 30 + 5 tip
        expect(summary.cardTotal, equals(55.0)); // 45 + 10 tip
        expect(summary.transferTotal, equals(0.0));

        final payouts = {
          for (final p in summary.payoutsByBarber) p.barberId: p,
        };
        expect(payouts['b1']!.totalOwed, equals(23.0)); // 18 + 5 tip
        expect(payouts['b2']!.totalOwed, equals(41.5)); // 31.5 + 10 tip
        expect(payouts['b1']!.barberName, equals('Former barber'));
        expect(summary.averageTicket, equals(37.5));
      },
    );

    test('FinanceSummary handles empty tickets gracefully', () {
      final summary = FinanceSummary.fromTickets(const []);

      expect(summary.totalClientsServed, equals(0));
      expect(summary.grossRevenue, equals(0.0));
      expect(summary.shopNetRevenue, equals(0.0));
      expect(summary.barberPayouts, equals(0.0));
      expect(summary.cashTotal, equals(0.0));
      expect(summary.cardTotal, equals(0.0));
    });
  });
}
