/// Helpers for reading Supabase rows. Postgres `numeric` can arrive as a JSON
/// number or a string depending on the column, so numbers are read
/// defensively.
library;

double readDouble(Object? value) {
  final result = readDoubleOrNull(value);
  if (result == null) {
    throw FormatException('Expected a number, got ${value.runtimeType}');
  }
  return result;
}

double? readDoubleOrNull(Object? value) {
  final parsed = switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
  return parsed;
}

DateTime readDateTime(Object? value) {
  if (value is! String) {
    throw FormatException('Expected a timestamp, got ${value.runtimeType}');
  }
  return DateTime.parse(value).toLocal();
}

/// A Postgres `date` ("2026-11-24") as a local midnight.
DateTime readDate(Object? value) {
  if (value is! String) {
    throw FormatException('Expected a date, got ${value.runtimeType}');
  }
  final parsed = DateTime.parse(value);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// A local calendar day as a Postgres `date`.
String writeDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

String writeTimestamp(DateTime moment) => moment.toUtc().toIso8601String();
