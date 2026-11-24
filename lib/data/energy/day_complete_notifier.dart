import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show AsyncNotifierProviderFamily;
import 'package:trendline/data/energy/energy_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/dates.dart';

/// Whether a day is marked as fully logged. Key it with `dayOf(...)` so equal
/// days share one cache entry.
final AsyncNotifierProviderFamily<DayCompleteNotifier, bool, DateTime>
dayCompleteProvider =
    AsyncNotifierProvider.family<DayCompleteNotifier, bool, DateTime>(
      DayCompleteNotifier.new,
    );

class DayCompleteNotifier extends AsyncNotifier<bool> {
  new(DateTime day) : _day = dayOf(day);

  final DateTime _day;

  @override
  Future<bool> build() async {
    if (ref.watch(currentUserIdProvider) == null) return false;
    final days = await ref
        .watch(energyRepositoryProvider)
        .fetchCompleteDays(_day, _day);
    return days.contains(_day);
  }

  /// Changes straight away; puts it back if saving fails.
  Future<void> set({required bool complete}) async {
    final before = state.value ?? false;
    state = AsyncData(complete);
    try {
      await ref
          .read(energyRepositoryProvider)
          .setComplete(_day, complete: complete);
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
    // The estimate's "days still needed" depends on this.
    ref.invalidate(energyProvider);
  }
}
