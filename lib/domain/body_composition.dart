import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/weigh_in.dart';

/// How old body composition readings may be and still count.
const int bodyCompositionMaxAgeDays = 30;

/// Lean (fat-free) mass from recent scale readings, or null if there are
/// none in the last [maxAgeDays].
///
/// Uses each reading's lean mass, or works it out from its body fat when
/// only that was recorded. Takes the median: home body-fat scales swing by a
/// few percent from day to day, and the median ignores the odd wild reading.
double? recentLeanMassKg(
  List<WeighIn> weighIns, {
  required DateTime today,
  int maxAgeDays = bodyCompositionMaxAgeDays,
}) {
  final day = dayOf(today);
  final values = <double>[];
  for (final w in weighIns) {
    final age = daysBetween(dayOf(w.measuredAt), day);
    if (age < 0 || age > maxAgeDays) continue;
    final lean =
        w.leanMassKg ??
        (w.bodyFatPct == null ? null : w.weightKg * (1 - w.bodyFatPct! / 100));
    if (lean != null && lean > 0 && lean < w.weightKg) values.add(lean);
  }
  if (values.isEmpty) return null;
  values.sort();
  final mid = values.length ~/ 2;
  return values.length.isOdd
      ? values[mid]
      : (values[mid - 1] + values[mid]) / 2;
}
