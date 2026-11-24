/// The local calendar day of [moment], at midnight.
DateTime dayOf(DateTime moment) {
  final local = moment.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// [day] moved by [days] calendar days. Uses calendar arithmetic rather than
/// adding 24-hour durations, so it stays correct across clock changes.
DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// Whole calendar days from [from] to [to] (negative if [to] is earlier).
int daysBetween(DateTime from, DateTime to) {
  // UTC midnights have no clock changes, so the division is exact.
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}
