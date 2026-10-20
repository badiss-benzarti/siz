import 'package:siz/features/floor_plan/domain/station.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Station Entity State Tests', () {
    test('Default station state is empty', () {
      const station = Station(chairNumber: 1, shopId: 'shop-123');
      expect(station.status, equals(ChairStatus.empty));
      expect(station.activeBarberId, isNull);
      expect(station.activeClientName, isNull);
    });

    test('Assigning barber transitions chair to available', () {
      const initialStation = Station(chairNumber: 2, shopId: 'shop-123');
      final updatedStation = initialStation.copyWith(
        status: ChairStatus.available,
        activeBarberId: 'barber-1',
        activeBarberName: 'Sam Barber',
      );

      expect(updatedStation.status, equals(ChairStatus.available));
      expect(updatedStation.activeBarberId, equals('barber-1'));
      expect(updatedStation.activeBarberName, equals('Sam Barber'));
    });

    test('Seating client transitions chair to occupied with timestamp', () {
      final now = DateTime.now();
      const station = Station(
        chairNumber: 3,
        shopId: 'shop-123',
        status: ChairStatus.available,
        activeBarberId: 'b1',
      );

      final occupiedStation = station.copyWith(
        status: ChairStatus.occupied,
        activeClientName: 'Michael',
        serviceStartTime: now,
      );

      expect(occupiedStation.status, equals(ChairStatus.occupied));
      expect(occupiedStation.activeClientName, equals('Michael'));
      expect(occupiedStation.serviceStartTime, equals(now));
    });

    test('toMap and fromMap preserves all fields accurately', () {
      final now = DateTime.now();
      final original = Station(
        chairNumber: 4,
        shopId: 'shop-xyz',
        status: ChairStatus.occupied,
        activeBarberId: 'barber-42',
        activeClientName: 'David',
        activeTicketId: 'ticket-99',
        serviceStartTime: now,
      );

      final map = original.toMap();
      final restored = Station.fromMap(map, barberName: 'Master David');

      expect(restored.chairNumber, equals(4));
      expect(restored.shopId, equals('shop-xyz'));
      expect(restored.status, equals(ChairStatus.occupied));
      expect(restored.activeBarberId, equals('barber-42'));
      expect(restored.activeBarberName, equals('Master David'));
      expect(restored.activeClientName, equals('David'));
      expect(restored.activeTicketId, equals('ticket-99'));
    });
  });
}
