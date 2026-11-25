import 'package:meta/meta.dart';
import 'package:trendline/domain/food.dart';

const int _day = 24 * 60;

/// When the user wakes and goes to sleep on one weekday, in minutes after
/// midnight. Sleep may be after midnight (earlier than wake).
@immutable
class DaySchedule {
  const new({
    required this.weekday,
    required this.wakeMinute,
    required this.sleepMinute,
  }) : isSet = true;

  /// The default for a weekday the user hasn't set: 07:00 to 23:00.
  const new standard(this.weekday)
    : wakeMinute = 7 * 60,
      sleepMinute = 23 * 60,
      isSet = false;

  static const int minAwakeMinutes = 8 * 60;
  static const int maxAwakeMinutes = 20 * 60;

  /// ISO weekday: 1 = Monday ... 7 = Sunday ([DateTime.weekday]).
  final int weekday;
  final int wakeMinute;
  final int sleepMinute;

  /// False for the [DaySchedule.standard] stand-in of a day the user hasn't
  /// set. Not part of equality: the times are what count.
  final bool isSet;

  /// Minutes awake, counting across midnight.
  int get awakeMinutes => (sleepMinute - wakeMinute + _day) % _day;

  @override
  bool operator ==(Object other) =>
      other is DaySchedule &&
      other.weekday == weekday &&
      other.wakeMinute == wakeMinute &&
      other.sleepMinute == sleepMinute;

  @override
  int get hashCode => Object.hash(weekday, wakeMinute, sleepMinute);
}

/// A problem with [s], or null if it's fine. Matches the database checks.
String? validateSchedule(DaySchedule s) {
  if (s.weekday < 1 || s.weekday > 7) return 'Unknown weekday.';
  for (final m in [s.wakeMinute, s.sleepMinute]) {
    if (m < 0 || m >= _day) return 'Times must be within the day.';
  }
  final awake = s.awakeMinutes;
  if (awake < DaySchedule.minAwakeMinutes) {
    return 'That’s under 8 hours awake. Check the times.';
  }
  if (awake > DaySchedule.maxAwakeMinutes) {
    return 'That’s over 20 hours awake. Check the times.';
  }
  return null;
}

/// All seven weekdays, Monday first: the user's saved ones, the standard
/// day for the rest.
List<DaySchedule> fullWeek(Iterable<DaySchedule> saved) {
  final byDay = {for (final s in saved) s.weekday: s};
  return [for (var d = 1; d <= 7; d++) byDay[d] ?? DaySchedule.standard(d)];
}

/// When each meal falls on a day with schedule [s], in minutes after
/// midnight (rounded to the quarter hour): breakfast half an hour after
/// waking, dinner three hours before sleep, lunch halfway between them and
/// the snack halfway between lunch and dinner.
Map<MealSlot, int> mealTimes(DaySchedule s) {
  // Work in minutes since waking, so a day crossing midnight is simple.
  const breakfast = 30;
  final dinner = s.awakeMinutes - 180;
  final lunch = (breakfast + dinner) / 2;
  final snack = (lunch + dinner) / 2;
  int clock(num sinceWaking) {
    final quarter = ((s.wakeMinute + sinceWaking) / 15).round() * 15;
    return quarter % _day;
  }

  return {
    MealSlot.breakfast: clock(breakfast),
    MealSlot.lunch: clock(lunch),
    MealSlot.snack: clock(snack),
    MealSlot.dinner: clock(dinner),
  };
}

/// "07:30"
String formatClock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:'
    '${(minute % 60).toString().padLeft(2, '0')}';
