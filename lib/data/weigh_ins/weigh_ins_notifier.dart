import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/snapshots/list_snapshot.dart';
import 'package:trendline/data/snapshots/snapshot_store.dart';
import 'package:trendline/data/weigh_ins/weigh_in_repository.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/trend.dart';
import 'package:trendline/domain/weigh_in.dart';

/// Weigh-ins from the last [WeighInsNotifier.historyDays] days, newest first,
/// cached in memory and on the device.
final weighInsProvider = AsyncNotifierProvider<WeighInsNotifier, List<WeighIn>>(
  WeighInsNotifier.new,
);

/// The daily weight trend up to today.
final trendProvider = Provider<List<TrendPoint>>((ref) {
  final weighIns = ref.watch(weighInsProvider).value ?? const [];
  return computeTrend(weighIns, until: DateTime.now());
});

class WeighInsNotifier extends AsyncNotifier<List<WeighIn>>
    with ListSnapshotMixin<WeighIn> {
  @override
  String get snapshotKey => SnapshotKeys.weighIns;

  @override
  Map<String, dynamic> toSnapshotRow(WeighIn item) => weighInToRow(item);

  @override
  WeighIn fromSnapshotRow(Map<String, dynamic> row) => weighInFromRow(row);

  /// Enough for a year's chart plus a lead-in for the trend to settle.
  static const int historyDays = 400;

  @override
  Future<List<WeighIn>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    final since = addDays(dayOf(DateTime.now()), -historyDays);
    final repository = ref.watch(weighInRepositoryProvider);
    // Older readings in the snapshot drop off as the window moves.
    return await loadWithSnapshot(
      userId,
      () => repository.fetchSince(since),
      keep: (w) => !w.measuredAt.isBefore(since),
    );
  }

  Future<void> add({
    required DateTime measuredAt,
    required double weightKg,
    double? bodyFatPct,
  }) async {
    final created = await ref
        .read(weighInRepositoryProvider)
        .add(
          measuredAt: measuredAt,
          weightKg: weightKg,
          bodyFatPct: bodyFatPct,
        );
    final current = state.value ?? const <WeighIn>[];
    state = AsyncData(_newestFirst([...current, created]));
  }

  /// Fetches the list again, keeping the current one on screen meanwhile.
  Future<void> reload() async {
    final since = addDays(dayOf(DateTime.now()), -historyDays);
    state = AsyncData(
      await ref.read(weighInRepositoryProvider).fetchSince(since),
    );
  }

  /// Removes the weigh-in straight away; puts it back if the delete fails.
  Future<void> delete(String id) async {
    final before = state.value ?? const <WeighIn>[];
    state = AsyncData([
      for (final w in before)
        if (w.id != id) w,
    ]);
    try {
      await ref.read(weighInRepositoryProvider).delete(id);
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }

  static List<WeighIn> _newestFirst(List<WeighIn> list) =>
      list..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
}
