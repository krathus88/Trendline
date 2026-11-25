import 'dart:convert';

/// One file the user can save from the data export.
enum ExportFile {
  /// Everything, as returned by the database.
  everything,

  /// Weigh-ins as a spreadsheet.
  weighIns,

  /// The food log as a spreadsheet.
  foodLog;

  String get label => switch (this) {
    everything => 'Everything (JSON)',
    weighIns => 'Weigh-ins (CSV)',
    foodLog => 'Food log (CSV)',
  };

  String get description => switch (this) {
    everything =>
      'All your data in one file: profile, health data, foods, '
          'recipes, plans, prep, households and sharing',
    weighIns => 'Date, weight, body fat and lean mass, for a spreadsheet',
    foodLog => 'Everything you logged with its nutrition, for a spreadsheet',
  };

  String get mimeType => switch (this) {
    everything => 'application/json',
    weighIns || foodLog => 'text/csv',
  };

  /// A file name with the day it was exported, e.g.
  /// `trendline-weigh-ins-2026-11-25.csv`.
  String fileName(DateTime now) {
    final day =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return switch (this) {
      everything => 'trendline-data-$day.json',
      weighIns => 'trendline-weigh-ins-$day.csv',
      foodLog => 'trendline-food-log-$day.csv',
    };
  }

  /// The file's contents, from the database's export.
  String build(Map<String, Object?> export) => switch (this) {
    everything => const JsonEncoder.withIndent('  ').convert(export),
    weighIns => toCsv(_weighInColumns, _rows(export, 'weigh_ins')),
    foodLog => toCsv(_foodLogColumns, _rows(export, 'food_logs')),
  };
}

const _weighInColumns = [
  'measured_at',
  'weight_kg',
  'body_fat_pct',
  'lean_mass_kg',
  'source',
];

const _foodLogColumns = [
  'eaten_on',
  'eaten_at',
  'slot',
  'food_name',
  'food_brand',
  'grams',
  'kcal',
  'protein_g',
  'carbs_g',
  'fat_g',
  'fibre_g',
];

List<Map<String, Object?>> _rows(Map<String, Object?> export, String table) {
  final rows = export[table];
  if (rows is! List) return const [];
  return [
    for (final row in rows)
      if (row is Map) row.cast<String, Object?>(),
  ];
}

/// A CSV file (RFC 4180, CRLF line ends) with a header row and one line per
/// row. Missing values are left empty.
///
/// A cell that a spreadsheet would read as a formula (starting with `=`,
/// `+`, `-`, `@`, tab or carriage return) gets a leading apostrophe, so a
/// food name typed in the app can't run as one when the file is opened.
/// Numbers are written as they are.
String toCsv(List<String> columns, List<Map<String, Object?>> rows) {
  final out = StringBuffer()..write(columns.map(_cell).join(','));
  for (final row in rows) {
    out
      ..write('\r\n')
      ..write(columns.map((c) => _cell(row[c])).join(','));
  }
  return (out..write('\r\n')).toString();
}

String _cell(Object? value) {
  if (value == null) return '';
  if (value is num || value is bool) return '$value';
  var text = value.toString();
  if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) text = "'$text";
  final needsQuotes =
      text.contains(',') ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r');
  return needsQuotes ? '"${text.replaceAll('"', '""')}"' : text;
}
