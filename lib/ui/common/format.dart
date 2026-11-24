import 'package:intl/intl.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';

final NumberFormat _whole = NumberFormat('#,##0');
final NumberFormat _oneDecimal = NumberFormat('#,##0.#');

/// "1,240"
String formatKcal(double kcal) => _whole.format(kcal.round());

/// "12.5 g" or "120 g"
String formatGrams(double grams) => '${_oneDecimal.format(grams)} g';

/// "Today", "Yesterday", "Tomorrow" or "Mon 23 Nov" (with the year if it
/// isn't this year).
String formatDayLabel(DateTime day, {DateTime? now}) {
  final today = dayOf(now ?? DateTime.now());
  final diff = daysBetween(today, day);
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  if (diff == 1) return 'Tomorrow';
  final pattern = day.year == today.year ? 'EEE d MMM' : 'EEE d MMM y';
  return DateFormat(pattern).format(day);
}

/// "23 Nov"
String formatShortDate(DateTime day) => DateFormat('d MMM').format(day);

/// "23 Nov, 07:41"
String formatDateTime(DateTime moment) =>
    DateFormat('d MMM, HH:mm').format(moment);

String mealSlotLabel(MealSlot slot) => switch (slot) {
  MealSlot.breakfast => 'Breakfast',
  MealSlot.lunch => 'Lunch',
  MealSlot.dinner => 'Dinner',
  MealSlot.snack => 'Snacks',
};

/// Parses a number typed by the user, accepting a comma as the decimal
/// separator. Returns null for anything that isn't a finite number.
double? parseDecimal(String input) {
  final value = double.tryParse(input.trim().replaceAll(',', '.'));
  if (value == null || value.isNaN || value.isInfinite) return null;
  return value;
}
