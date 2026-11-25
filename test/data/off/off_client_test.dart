import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trendline/data/off/off_client.dart';

final Map<String, Object> _milk = {
  'code': '01219494',
  'product_name': 'Semi skimmed milk',
  'brands': "Sainsbury's",
  'nutriments': {
    'energy-kcal_100g': 50,
    'proteins_100g': 3.6,
    'carbohydrates_100g': 4.8,
    'fat_100g': 1.8,
  },
};

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late List<http.Request> requests;
  late DateTime now;

  OffClient client(FutureOr<http.Response> Function(http.Request) respond) {
    requests = [];
    now = DateTime(2026, 11, 24, 12);
    return OffClient(
      userAgent: 'Trendline/0.1.0 (test)',
      clock: () => now,
      httpClient: MockClient((r) async {
        requests.add(r);
        return await respond(r);
      }),
    );
  }

  group('search', () {
    test('searches UK products with nutrition filled in', () async {
      // The search index has no nutriments: hits are barcode, name, brands.
      final off = client(
        (_) => json({
          'hits': [
            {
              'code': '01219494',
              'product_name': 'Semi skimmed milk',
              'brands': ["Sainsbury's"],
            },
            {
              'code': '7613034310156',
              'product_name': 'Cappuccino Skinny',
              'brands': ['xx:nescafe'],
            },
            {'code': '1', 'product_name': 'bad barcode'},
            {'code': '01219495'},
          ],
        }),
      );

      final results = await off.search('semi skimmed milk');

      expect(results, hasLength(2));
      final hit = results.first;
      expect(hit.barcode, '01219494');
      expect(hit.name, 'Semi skimmed milk');
      expect(hit.brand, "Sainsbury's");
      expect(hit.product, isNull);
      expect(results.last.brand, 'nescafe', reason: 'tag prefix dropped');
      final uri = requests.single.url;
      expect(uri.host, 'search.openfoodfacts.org');
      expect(
        uri.queryParameters['q'],
        'semi skimmed milk countries:"en:united-kingdom" '
        'states:"en:nutrition-facts-completed"',
      );
      expect(uri.queryParameters['fields'], isNot(contains('nutriments')));
      expect(requests.single.headers['User-Agent'], 'Trendline/0.1.0 (test)');
    });

    test('keeps nutrition a hit happens to carry, if usable', () async {
      final off = client(
        (_) => json({
          'hits': [
            _milk,
            {
              ..._milk,
              'code': '01219495',
              'nutriments': {'energy-kcal_100g': 9000},
            },
          ],
        }),
      );

      final results = await off.search('milk');

      expect(results.first.product?.per100g.kcal, 50);
      expect(results.last.product, isNull, reason: 'implausible values');
    });

    test('caches results for the same query', () async {
      final off = client(
        (_) => json({
          'hits': [_milk],
        }),
      );
      await off.search('Milk');
      await off.search('  milk ');
      expect(requests, hasLength(1));
    });

    test('ignores queries shorter than two characters', () async {
      final off = client((_) => json({'hits': <Object>[]}));
      expect(await off.search(' a '), isEmpty);
      expect(requests, isEmpty);
    });

    test('stops at 10 searches a minute, then allows more later', () async {
      final off = client((_) => json({'hits': <Object>[]}));
      for (var i = 0; i < OffClient.searchesPerMinute; i++) {
        await off.search('query $i');
      }
      await expectLater(off.search('one more'), throwsA(isA<OffRateLimited>()));
      expect(requests, hasLength(OffClient.searchesPerMinute));

      now = now.add(const Duration(minutes: 1));
      await off.search('one more');
      expect(requests, hasLength(OffClient.searchesPerMinute + 1));
    });

    test('server rate limiting becomes a friendly error', () async {
      final off = client((_) => http.Response('slow down', 429));
      await expectLater(off.search('milk'), throwsA(isA<OffRateLimited>()));
    });

    test('server errors and bad JSON become friendly errors', () async {
      final down = client((_) => http.Response('oops', 500));
      await expectLater(down.search('milk'), throwsA(isA<OffException>()));

      final garbage = client((_) => http.Response('<html>', 200));
      await expectLater(garbage.search('milk'), throwsA(isA<OffException>()));
    });

    test('network failures become friendly errors', () async {
      final off = client((_) => throw http.ClientException('offline'));
      await expectLater(
        off.search('milk'),
        throwsA(
          isA<OffException>().having(
            (e) => e.message,
            'message',
            contains('connection'),
          ),
        ),
      );
    });
  });

  group('lookup', () {
    test('finds a product by barcode with API v3', () async {
      final off = client((_) => json({'status': 'success', 'product': _milk}));

      final product = await off.lookup('01219494');

      expect(product!.brand, "Sainsbury's");
      expect(requests.single.url.path, '/api/v3/product/01219494');
    });

    test('a 404 means not found, and is cached', () async {
      final off = client((_) => json({'status': 'failure'}, 404));
      expect(await off.lookup('5000000000000'), isNull);
      expect(await off.lookup('5000000000000'), isNull);
      expect(requests, hasLength(1));
    });

    test('rejects malformed barcodes without a request', () async {
      final off = client((_) => json({}));
      await expectLater(off.lookup('12ab'), throwsA(isA<OffException>()));
      expect(requests, isEmpty);
    });

    test('stops at 15 lookups a minute', () async {
      final off = client((_) => json({}, 404));
      for (var i = 0; i < OffClient.lookupsPerMinute; i++) {
        await off.lookup('${5000000000000 + i}');
      }
      await expectLater(
        off.lookup('5000000000999'),
        throwsA(isA<OffRateLimited>()),
      );
    });
  });

  group('cleanSearchQuery', () {
    test('keeps words, strips query syntax', () {
      expect(cleanSearchQuery('Nescafé Cappuccino'), 'nescafé cappuccino');
      expect(
        cleanSearchQuery('milk countries_tags:"en:france" OR (x)'),
        'milk countries tags en france or x',
      );
      expect(
        cleanSearchQuery("M&S Love Life 0% yoghurt's"),
        "m&s love life 0 yoghurt's",
      );
    });
  });

  test('user agent includes the contact only when set', () {
    expect(offUserAgent('0.1.0', ''), 'Trendline/0.1.0');
    expect(
      offUserAgent('0.1.0', ' me@example.com '),
      'Trendline/0.1.0 (me@example.com)',
    );
  });
}
