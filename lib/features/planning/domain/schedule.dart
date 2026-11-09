/// Floating device-local civil dates, intentionally not elapsed 24-hour periods.
/// Stored dates and occurrence keys remain stable across DST and timezone changes.
abstract final class CivilSchedule {
  static String key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime parse(String text) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) throw const FormatException('Use YYYY-MM-DD');
    final parts = text.split('-').map(int.parse).toList();
    final date = DateTime(parts[0], parts[1], parts[2]);
    if (key(date) != text) throw const FormatException('Invalid calendar date');
    return date;
  }
  static DateTime at(DateTime anchor, String frequency, int index) {
    if (index < 0) throw ArgumentError('Invalid occurrence index');
    switch (frequency) {
      case 'daily': return DateTime(anchor.year, anchor.month, anchor.day + index);
      case 'weekly': return DateTime(anchor.year, anchor.month, anchor.day + index * 7);
      case 'monthly':
        final first = DateTime(anchor.year, anchor.month + index);
        final last = DateTime(first.year, first.month + 1, 0).day;
        return DateTime(first.year, first.month, anchor.day > last ? last : anchor.day);
      case 'yearly':
        final year = anchor.year + index;
        final last = DateTime(year, anchor.month + 1, 0).day;
        return DateTime(year, anchor.month, anchor.day > last ? last : anchor.day);
      default: throw ArgumentError('Invalid frequency');
    }
  }
}
