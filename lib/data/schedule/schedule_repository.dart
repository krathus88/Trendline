import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/domain/schedule.dart';

abstract interface class ScheduleRepository {
  /// The weekdays the user has set (others use the standard day).
  Future<List<DaySchedule>> fetchAll();

  /// Saves one weekday, replacing what was there.
  Future<void> save(DaySchedule schedule);
}

class SupabaseScheduleRepository implements ScheduleRepository {
  const new(this._db);

  final SupabaseClient _db;

  @override
  Future<List<DaySchedule>> fetchAll() async {
    final rows = await _db
        .from('day_schedules')
        .select('weekday, wake_time, sleep_time')
        .order('weekday');
    return [for (final r in rows) ?scheduleFromRow(r)];
  }

  @override
  Future<void> save(DaySchedule schedule) async {
    // One row per weekday: the primary key is (user_id, weekday).
    await _db
        .from('day_schedules')
        .upsert(scheduleToRow(schedule), onConflict: 'user_id,weekday');
  }
}

/// A schedule row, or null if it can't be read.
DaySchedule? scheduleFromRow(Map<String, dynamic> row) {
  final weekday = row['weekday'];
  final wake = readClock(row['wake_time']);
  final sleep = readClock(row['sleep_time']);
  if (weekday is! int || wake == null || sleep == null) return null;
  return DaySchedule(weekday: weekday, wakeMinute: wake, sleepMinute: sleep);
}

Map<String, dynamic> scheduleToRow(DaySchedule s) => {
  'weekday': s.weekday,
  'wake_time': formatClock(s.wakeMinute),
  'sleep_time': formatClock(s.sleepMinute),
};

/// A Postgres `time` ("07:30:00") as minutes after midnight.
int? readClock(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{2}):(\d{2})').firstMatch(value);
  if (match == null) return null;
  final minutes = int.parse(match[1]!) * 60 + int.parse(match[2]!);
  return minutes < 24 * 60 ? minutes : null;
}
