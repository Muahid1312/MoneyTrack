import 'package:intl/intl.dart';

/// Half-open local date range: [start, end).
class DateSpan {
  const DateSpan(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  /// Number of calendar days covered.
  int get days => Dates.daysBetween(start, end);

  factory DateSpan.month(DateTime anyDayInMonth) {
    final s = DateTime(anyDayInMonth.year, anyDayInMonth.month);
    return DateSpan(s, DateTime(s.year, s.month + 1));
  }

  factory DateSpan.lastDays(DateTime today, int days) {
    final end = Dates.dateOnly(today).add(const Duration(days: 1));
    return DateSpan(Dates.addDays(end, -days), end);
  }

  /// Inclusive day range (both days included).
  factory DateSpan.inclusive(DateTime first, DateTime last) => DateSpan(
      Dates.dateOnly(first), Dates.addDays(Dates.dateOnly(last), 1));

  DateTime get lastDay => Dates.addDays(end, -1);

  @override
  bool operator ==(Object other) =>
      other is DateSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

abstract final class Dates {
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Calendar-safe day arithmetic (immune to DST shifts).
  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  static int daysBetween(DateTime a, DateTime b) {
    final ua = DateTime.utc(a.year, a.month, a.day);
    final ub = DateTime.utc(b.year, b.month, b.day);
    return ub.difference(ua).inDays;
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  static String greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'Good evening';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// "Today", "Yesterday", or "Mon, Oct 19" (year added when not current).
  static String relativeDay(DateTime d, DateTime now) {
    final diff = daysBetween(d, now);
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff == -1) return 'Tomorrow';
    if (d.year == now.year) return DateFormat('EEEE, MMM d').format(d);
    return DateFormat('EEE, MMM d, y').format(d);
  }

  static String fullDate(DateTime d) => DateFormat('EEEE, MMMM d').format(d);
  static String shortDate(DateTime d) => DateFormat('MMM d, y').format(d);
  static String time(DateTime d) => DateFormat('h:mm a').format(d);

  static String spanLabel(DateSpan s) {
    final last = s.lastDay;
    if (s.start.day == 1 &&
        s.end == DateTime(s.start.year, s.start.month + 1)) {
      return DateFormat('MMMM y').format(s.start);
    }
    if (s.start.year == last.year) {
      return '${DateFormat('MMM d').format(s.start)} – ${DateFormat('MMM d, y').format(last)}';
    }
    return '${shortDate(s.start)} – ${shortDate(last)}';
  }
}
