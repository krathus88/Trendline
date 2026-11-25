import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trendline/data/off/off_client.dart';
import 'package:trendline/data/off/off_product.dart';
import 'package:trendline/data/snapshots/off_lookup_cache.dart';
import 'package:trendline/data/snapshots/snapshot_store.dart';
import 'package:trendline/domain/nutrition.dart';

import '../../helpers/fakes.dart';

final Map<String, Object> _milk = {
  'code': '01219494',
  'product_name': 'Semi skimmed milk',
  'brands': "Sainsbury's",
  'serving_quantity': 200,
  'nutriments': {
    'energy-kcal_100g': 50,
    'proteins_100g': 3.6,
    'carbohydrates_100g': 4.8,
    'fat_100g': 1.8,
    'sugars_100g': 4.8,
    'salt_100g': 0.1,
  },
};

void main() {
  late FakeSnapshotStore store;
  late DateTime now;
  late String? user;
  late int requests;

  /// A fresh client (as after an app restart) sharing the device store.
  OffClient client({int status = 200}) {
    return OffClient(
      userAgent: 'Trendline/test',
      clock: () => now,
      httpClient: MockClient((_) async {
        requests++;
        final body = status == 404
            ? {'status': 'failure'}
            : {'product': _milk};
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      deviceCache: DeviceOffLookupCache(
        store: store,
        userId: () => user,
        clock: () => now,
      ),
    );
  }

  setUp(() {
    store = FakeSnapshotStore();
    now = DateTime(2026, 11, 25, 12);
    user = 'user-1';
    requests = 0;
  });

  test('the cached form reads back as the same product', () {
    final product = parseOffProduct(_milk)!;
    final back = parseOffProduct(offProductToJson(product))!;
    expect(back.barcode, '01219494');
    expect(back.name, 'Semi skimmed milk');
    expect(back.brand, "Sainsbury's");
    expect(back.per100g.kcal, 50);
    expect(back.per100g.fibreUnknown, isTrue);
    expect(back.sugarG, 4.8);
    expect(back.saltG, 0.1);
    expect(back.servingG, 200);
  });

  test('a product looked up before needs no request after a restart', () async {
    expect((await client().lookup('01219494'))?.name, 'Semi skimmed milk');
    expect(requests, 1);
    expect(store.values[SnapshotKeys.openFoodFacts], contains('user-1'));

    final again = await client().lookup('01219494');
    expect(again?.per100g.proteinG, 3.6);
    expect(requests, 1);
  });

  test('products are looked up again after 30 days', () async {
    await client().lookup('01219494');
    now = now.add(const Duration(days: 31));
    await client().lookup('01219494');
    expect(requests, 2);
  });

  test('"not found" is kept for a day only', () async {
    expect(await client(status: 404).lookup('01219494'), isNull);
    expect(await client(status: 404).lookup('01219494'), isNull);
    expect(requests, 1);
    now = now.add(const Duration(days: 2));
    await client(status: 404).lookup('01219494');
    expect(requests, 2);
  });

  test('another account’s lookups are never used, and deleted', () async {
    await client().lookup('01219494');
    user = 'user-2';
    await client().lookup('01219494');
    expect(requests, 2);
    final stored = store.values[SnapshotKeys.openFoodFacts]!;
    expect(stored, contains('user-2'));
    expect(stored, isNot(contains('user-1')));
  });

  test('nothing is kept when nobody is signed in', () async {
    user = null;
    await client().lookup('01219494');
    expect(store.values, isEmpty);
  });

  test('only the latest lookups are kept', () async {
    final cache = DeviceOffLookupCache(
      store: store,
      userId: () => user,
      clock: () => now,
    );
    final product = parseOffProduct(_milk);
    for (var i = 0; i < DeviceOffLookupCache.maxEntries + 5; i++) {
      now = now.add(const Duration(minutes: 1));
      await cache.put('${10000000 + i}', product);
    }
    final stored =
        jsonDecode(store.values[SnapshotKeys.openFoodFacts]!)
            as Map<String, dynamic>;
    final entries = stored['entries'] as Map<String, dynamic>;
    expect(entries, hasLength(DeviceOffLookupCache.maxEntries));
    expect(entries.containsKey('10000000'), isFalse);
    expect(entries.containsKey('${10000000 + 104}'), isTrue);
  });

  test('a damaged cache is dropped, and a broken one never stops a '
      'lookup', () async {
    store.values[SnapshotKeys.openFoodFacts] = 'not json';
    expect((await client().lookup('01219494'))?.name, 'Semi skimmed milk');
    expect(requests, 1);

    final off = OffClient(
      userAgent: 'Trendline/test',
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'product': _milk}), 200),
      ),
      deviceCache: _BrokenCache(),
    );
    expect((await off.lookup('01219494'))?.per100g, isA<Nutrition>());
  });
}

class _BrokenCache implements OffLookupCache {
  @override
  Future<({OffProduct? product})?> get(String barcode) =>
      throw StateError('storage unavailable');

  @override
  Future<void> put(String barcode, OffProduct? product) =>
      throw StateError('storage unavailable');
}
