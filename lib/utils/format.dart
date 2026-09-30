const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday', //
];

/// "Mon"
String weekdayShort(DateTime d) => _weekdays[d.weekday - 1].substring(0, 3);

/// "September"
String monthLong(DateTime d) => _months[d.month - 1];

/// "Sep"
String monthShort(DateTime d) => _months[d.month - 1].substring(0, 3);

/// "Monday, 28 September 2026"
String formatLongDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';

/// "22 – 28 Sep 2026", "29 Sep – 5 Oct 2026"
String formatWeekRange(DateTime monday) {
  final sunday = DateTime(monday.year, monday.month, monday.day + 6);
  final left = monday.month == sunday.month
      ? '${monday.day}'
      : '${monday.day} ${monthShort(monday)}';
  return '$left – ${sunday.day} ${monthShort(sunday)} ${sunday.year}';
}

/// Midnight at the start of [d]'s day.
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of [d]'s week, at midnight.
DateTime startOfWeek(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// 45 → "45m", 120 → "2h", 200 → "3h 20m"
String formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// "Today", "Yesterday", "3 days ago", or "12 Sep" for older dates.
String formatAgo(DateTime then, DateTime now) {
  final d = DateTime(now.year, now.month, now.day)
      .difference(DateTime(then.year, then.month, then.day))
      .inHours / 24;
  final days = d.round(); // round: a day can be 23 or 25 hours
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return '${then.day} ${monthShort(then)}';
}

/// "September 09, 2026"
String formatNoteDate(DateTime d) =>
    '${_months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';

/// "2026-09-28", used as a key for daily stats.
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "1 page" / "3 pages"
String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

int _seq = 0;

/// Short unique id for new items.
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';
