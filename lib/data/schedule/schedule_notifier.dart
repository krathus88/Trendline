import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/schedule.dart';

/// All seven weekdays (saved ones, the standard day for the rest), Monday
/// first, cached in memory.
final scheduleProvider =
    AsyncNotifierProvider<ScheduleNotifier, List<DaySchedule>>(
      ScheduleNotifier.new,
    );

class ScheduleNotifier extends AsyncNotifier<List<DaySchedule>> {
  @override
  Future<List<DaySchedule>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return fullWeek(const []);
    return fullWeek(await ref.watch(scheduleRepositoryProvider).fetchAll());
  }

  /// Saves [days] (one or more weekdays). Shows them straight away;
  /// reverts if saving fails.
  Future<void> save(List<DaySchedule> days) async {
    final before = state.value ?? fullWeek(const []);
    final changed = {for (final d in days) d.weekday: d};
    state = AsyncData([for (final d in before) changed[d.weekday] ?? d]);
    try {
      final repo = ref.read(scheduleRepositoryProvider);
      for (final d in days) {
        await repo.save(d);
      }
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }
}
