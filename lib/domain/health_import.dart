import 'package:meta/meta.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/weigh_in.dart';

/// One record read from a health platform such as Health Connect.
@immutable
class HealthReading {
  const new({required this.id, required this.at, required this.value});

  /// The platform's record ID, stable across reads.
  final String id;
  final DateTime at;
  final double value;
}

/// Body readings over a time range. Weight, body fat and lean mass are
/// separate records on the platform.
@immutable
class BodyReadings {
  const new({
    this.weightKg = const [],
    this.bodyFatPct = const [],
    this.leanMassKg = const [],
  });

  final List<HealthReading> weightKg;
  final List<HealthReading> bodyFatPct;
  final List<HealthReading> leanMassKg;
}

/// A weigh-in to import, built from one weight record and any body fat and
/// lean mass recorded with it.
@immutable
class ImportedWeighIn {
  const new({
    required this.externalId,
    required this.measuredAt,
    required this.weightKg,
    this.bodyFatPct,
    this.leanMassKg,
  });

  final String externalId;
  final DateTime measuredAt;
  final double weightKg;
  final double? bodyFatPct;
  final double? leanMassKg;
}

/// A smart scale writes body fat and lean mass at the same moment as the
/// weight; allow a little drift between them.
const Duration pairingWindow = Duration(minutes: 5);

/// When two apps sync the same scale, the same reading arrives twice with
/// different IDs. Readings this close in time and weight count as one.
const Duration duplicateWindow = Duration(minutes: 5);
const double duplicateToleranceKg = 0.15;

/// A manual weigh-in on the same day within this much is taken to be the
/// same reading, typed in by hand before the scale synced.
const double manualMatchToleranceKg = 0.5;

/// How far before the newest imported reading each sync looks again, for
/// scales that sync late.
const int resyncOverlapDays = 7;

/// Decides which readings to import, oldest first.
///
/// Skips readings already imported (by ID), readings that are invalid or in
/// the future, readings duplicated by another app, and readings that match a
/// manual weigh-in on the same day. Readings the user deleted are skipped by
/// the database, which remembers their IDs.
List<ImportedWeighIn> planHealthImport(
  BodyReadings readings, {
  required List<WeighIn> existing,
  required DateTime now,
}) {
  final known = {
    for (final w in existing)
      if (w.externalId != null) w.externalId!,
  };
  final manual = [
    for (final w in existing)
      if (w.source == WeighInSource.manual) w,
  ];
  // Readings already stored or accepted in this run, to catch duplicates.
  final accepted = <({DateTime at, double kg})>[
    for (final w in existing)
      if (w.source != WeighInSource.manual) (at: w.measuredAt, kg: w.weightKg),
  ];

  final latestAllowed = now.add(const Duration(minutes: 5));
  final weights = [...readings.weightKg]..sort((a, b) => a.at.compareTo(b.at));
  final result = <ImportedWeighIn>[];

  for (final r in weights) {
    final kg = r.value;
    if (known.contains(r.id)) continue;
    if (!kg.isFinite || !WeighIn.isValidWeight(kg)) continue;
    if (r.at.isAfter(latestAllowed)) continue;
    if (accepted.any((a) => _sameReading(a.at, a.kg, r.at, kg))) continue;
    final day = dayOf(r.at);
    if (manual.any(
      (m) =>
          dayOf(m.measuredAt) == day &&
          (m.weightKg - kg).abs() <= manualMatchToleranceKg,
    )) {
      continue;
    }

    final fat = _closest(readings.bodyFatPct, r.at)?.value;
    final lean = _closest(readings.leanMassKg, r.at)?.value;
    result.add(
      ImportedWeighIn(
        externalId: r.id,
        measuredAt: r.at,
        weightKg: kg,
        bodyFatPct: fat != null && fat.isFinite && WeighIn.isValidBodyFat(fat)
            ? fat
            : null,
        leanMassKg:
            lean != null &&
                lean.isFinite &&
                WeighIn.isValidLeanMass(lean, weightKg: kg)
            ? lean
            : null,
      ),
    );
    accepted.add((at: r.at, kg: kg));
  }
  return result;
}

/// Where the next sync should start reading from: a week before the newest
/// imported reading, or the whole history window if nothing is imported yet.
DateTime healthSyncStart(
  List<WeighIn> existing, {
  required DateTime now,
  required int historyDays,
}) {
  final earliest = addDays(dayOf(now), -historyDays);
  DateTime? newest;
  for (final w in existing) {
    if (w.source == WeighInSource.manual) continue;
    if (newest == null || w.measuredAt.isAfter(newest)) newest = w.measuredAt;
  }
  if (newest == null) return earliest;
  final start = addDays(dayOf(newest), -resyncOverlapDays);
  return start.isBefore(earliest) ? earliest : start;
}

bool _sameReading(DateTime aAt, double aKg, DateTime bAt, double bKg) =>
    aAt.difference(bAt).abs() <= duplicateWindow &&
    (aKg - bKg).abs() <= duplicateToleranceKg;

HealthReading? _closest(List<HealthReading> list, DateTime at) {
  HealthReading? best;
  Duration? bestGap;
  for (final r in list) {
    final gap = r.at.difference(at).abs();
    if (gap > pairingWindow) continue;
    if (bestGap == null || gap < bestGap) {
      best = r;
      bestGap = gap;
    }
  }
  return best;
}
