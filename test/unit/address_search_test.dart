import 'package:siz/core/errors/app_exception.dart';
import 'package:siz/core/maps/address_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('finds places in Tunisia and reads their position', () async {
    late Uri asked;
    final search = AddressSearch(
      client: MockClient((request) async {
        asked = request.url;
        return http.Response(
          '[{"display_name": "Avenue Habib Bourguiba, Tunis",'
          ' "lat": "36.8008", "lon": "10.1800"}]',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final places = await search.search('Habib Bourguiba');
    expect(places.single.label, 'Avenue Habib Bourguiba, Tunis');
    expect(places.single.position.latitude, 36.8008);
    expect(asked.queryParameters['countrycodes'], 'tn');
  });

  test('very short searches do not hit the service', () async {
    var calls = 0;
    final search = AddressSearch(
      client: MockClient((_) async {
        calls++;
        return http.Response('[]', 200);
      }),
    );
    expect(await search.search('ab'), isEmpty);
    expect(calls, 0);
  });

  test('service errors become a readable message', () async {
    final search = AddressSearch(
      client: MockClient((_) async => http.Response('busy', 503)),
    );
    await expectLater(search.search('Tunis'), throwsA(isA<AppException>()));
  });
}
