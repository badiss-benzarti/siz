import 'package:siz/features/client_app/client_directory.dart';
import 'package:siz/features/floor_plan/domain/station.dart';

/// One listed salon, Blade & Crown, with two barbers, prices and a photo.
class FakeClientDirectory implements ClientDirectory {
  static const blade = ClientSalon(
    id: 's1',
    name: 'Blade & Crown',
    address: 'Avenue Habib Bourguiba, Tunis',
    isOpen: true,
    waitingCount: 2,
    totalChairs: 4,
    established: 2026,
  );

  static final post = ClientPost(
    id: 'p1',
    shopId: 's1',
    shopName: 'Blade & Crown',
    barberName: 'Sami',
    imageUrl: 'art:fade',
    caption: 'Mid skin fade',
    ratingAvg: 4.5,
    ratingCount: 2,
    commentCount: 1,
    createdAt: DateTime(2026, 10, 8),
  );

  int salonRequests = 0;

  @override
  Future<List<ClientSalon>> salons() async {
    salonRequests++;
    return [blade];
  }

  @override
  Future<SalonDetails> salon(String shopId) async => SalonDetails(
    salon: blade,
    barbers: const [
      ClientBarber(
        id: 'b1',
        name: 'Sami',
        specialty: 'Skin fades',
        isOnDuty: true,
        ratingAvg: 4.8,
        ratingCount: 12,
      ),
      ClientBarber(
        id: 'b2',
        name: 'Karim',
        specialty: 'Beards',
        isOnDuty: true,
        ratingAvg: 0,
        ratingCount: 0,
      ),
    ],
    services: const [
      ClientService('Haircut', 25, 30),
      ClientService('Beard Trim', 15, 20),
    ],
    stations: [
      const Station(
        chairNumber: 1,
        shopId: 's1',
        status: ChairStatus.available,
        activeBarberId: 'b1',
        activeBarberName: 'Sami',
      ),
      Station(
        chairNumber: 2,
        shopId: 's1',
        status: ChairStatus.occupied,
        activeBarberId: 'b2',
        activeBarberName: 'Karim',
        serviceStartTime: DateTime.now(),
      ),
      const Station(chairNumber: 3, shopId: 's1'),
      const Station(chairNumber: 4, shopId: 's1'),
    ],
    posts: [post],
  );

  @override
  Future<List<ClientPost>> latestPosts({int limit = 30}) async => [post];

  @override
  Future<List<ClientComment>> comments(String postId) async => [
    ClientComment('Chedi', 'Clean work', DateTime(2026, 10, 8)),
  ];
}
