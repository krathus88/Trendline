import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:trendline/data/off/off_product.dart';

/// A problem talking to Open Food Facts, with a message safe to show.
class OffException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'OffException: $message';
}

/// Raised before a request would break Open Food Facts' rate limits.
class OffRateLimited extends OffException {
  const new(this.retryAfter)
    : super('Too many searches in a row. Try again in a moment.');

  final Duration retryAfter;
}

/// Client for the public Open Food Facts API.
///
/// * Barcode lookups use API v3; text search uses search.openfoodfacts.org,
///   filtered to products sold in the UK.
/// * Their limits are 15 product reads and 10 searches per minute per user,
///   and no search-as-you-type. The client enforces both limits itself and
///   caches results in memory, so repeated lookups cost nothing.
/// * Every request identifies the app with a User-Agent, as they ask.
class OffClient {
  new({
    required this.userAgent,
    http.Client? httpClient,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 10),
  }) : _http = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now;

  static const int searchesPerMinute = 10;
  static const int lookupsPerMinute = 15;
  static const int pageSize = 20;

  static const String _fields =
      'code,product_name,product_name_en,brands,serving_quantity,nutriments';

  final String userAgent;
  final Duration timeout;
  final http.Client _http;
  final DateTime Function() _clock;

  final _searchTimes = <DateTime>[];
  final _lookupTimes = <DateTime>[];
  final _searchCache = <String, List<OffProduct>>{};
  final _lookupCache = <String, OffProduct?>{};

  /// Products sold in the UK matching [query]. Results with missing or
  /// implausible nutrition are left out.
  Future<List<OffProduct>> search(String query) async {
    final cleaned = cleanSearchQuery(query);
    if (cleaned.length < 2) return const [];

    final cached = _searchCache[cleaned];
    if (cached != null) return cached;

    _checkLimit(_searchTimes, searchesPerMinute);
    final uri = Uri.https('search.openfoodfacts.org', '/search', {
      'q': '$cleaned countries_tags:"en:united-kingdom"',
      'page_size': '$pageSize',
      'langs': 'en',
      'fields': _fields,
    });
    final body = await _get(uri);
    final hits = body['hits'];
    final results = hits is List
        ? hits.map(parseOffProduct).whereType<OffProduct>().toList()
        : const <OffProduct>[];
    _searchCache[cleaned] = results;
    return results;
  }

  /// The product with [barcode], or null if Open Food Facts doesn't have it
  /// (or its data is unusable).
  Future<OffProduct?> lookup(String barcode) async {
    final code = barcode.trim();
    if (!RegExp(r'^[0-9]{6,14}$').hasMatch(code)) {
      throw const OffException('That doesn’t look like a product barcode.');
    }
    if (_lookupCache.containsKey(code)) return _lookupCache[code];

    _checkLimit(_lookupTimes, lookupsPerMinute);
    final uri = Uri.https('world.openfoodfacts.org', '/api/v3/product/$code', {
      'fields': _fields,
    });
    final body = await _get(uri, notFoundIsNull: true);
    final product = body.isEmpty ? null : parseOffProduct(body['product']);
    _lookupCache[code] = product;
    return product;
  }

  void close() => _http.close();

  void _checkLimit(List<DateTime> times, int perMinute) {
    final now = _clock();
    times.removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
    if (times.length >= perMinute) {
      final retryAfter = const Duration(minutes: 1) - now.difference(times[0]);
      throw OffRateLimited(retryAfter);
    }
    times.add(now);
  }

  Future<Map<String, dynamic>> _get(
    Uri uri, {
    bool notFoundIsNull = false,
  }) async {
    final http.Response response;
    try {
      response = await _http
          .get(uri, headers: {'User-Agent': userAgent})
          .timeout(timeout);
    } on TimeoutException {
      throw const OffException(
        'Open Food Facts is taking too long. Try again.',
      );
    } on Exception {
      throw const OffException(
        'Couldn’t reach Open Food Facts. Check your connection.',
      );
    }

    if (response.statusCode == 404 && notFoundIsNull) return const {};
    if (response.statusCode == 429 || response.statusCode == 503) {
      throw const OffRateLimited(Duration(minutes: 1));
    }
    if (response.statusCode != 200) {
      throw const OffException('Open Food Facts had a problem. Try again.');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Fall through.
    }
    throw const OffException('Open Food Facts sent an unexpected response.');
  }
}

/// Keeps a search to plain words, so user input can't change the meaning of
/// the search query (it uses a query language with `field:value` syntax).
String cleanSearchQuery(String query) => query
    .replaceAll(RegExp(r"[^\p{L}\p{N}\s'&-]", unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// `Trendline/0.1.0 (contact)`, or without the contact if none is set.
String offUserAgent(String version, String contact) => contact.trim().isEmpty
    ? 'Trendline/$version'
    : 'Trendline/$version (${contact.trim()})';
