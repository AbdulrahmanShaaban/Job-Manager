import 'package:intl/intl.dart';

/// Display helpers for Arabic (Egypt) dates.
///
/// The API returns date-only strings (`YYYY-MM-DD`) that already represent a
/// calendar day in Africa/Cairo, so they are never converted through UTC here.
class AppFormat {
  const AppFormat._();

  static final DateFormat _dayMonth = DateFormat('d MMM', 'ar');
  static final DateFormat _full = DateFormat('EEEE d MMMM yyyy', 'ar');
  static final DateFormat _short = DateFormat('d MMM yyyy', 'ar');
  static final DateFormat _time = DateFormat('h:mm a', 'ar');

  /// Parses a date-only string as a local calendar date (no timezone shift).
  static DateTime? parseDateOnly(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  static String isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// Today's calendar date on this device, formatted as `YYYY-MM-DD`.
  ///
  /// The server is the authority for "today in Cairo" (it returns `today` in
  /// the overview payload); this is only used to prefill offline drafts.
  static String todayIso() => isoDate(DateTime.now());

  static String dayMonth(String? isoDate) {
    final date = parseDateOnly(isoDate);
    if (date == null) return '—';
    return _dayMonth.format(date);
  }

  static String fullDate(String? isoDate) {
    final date = parseDateOnly(isoDate);
    if (date == null) return '—';
    return _full.format(date);
  }

  static String shortDate(String? isoDate) {
    final date = parseDateOnly(isoDate);
    if (date == null) return '—';
    return _short.format(date);
  }

  static String dateTime(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    return '${_short.format(local)} • ${_time.format(local)}';
  }

  /// Human relative label such as «النهارده», «امبارح», «من 3 أيام».
  static String relativeDay(String? isoDate) {
    final date = parseDateOnly(isoDate);
    if (date == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(date).inDays;
    return switch (diff) {
      0 => 'النهارده',
      1 => 'امبارح',
      2 => 'أول امبارح',
      < 0 => 'بعد ${-diff} يوم',
      < 7 => 'من $diff أيام',
      < 30 => 'من ${(diff / 7).floor()} أسابيع',
      _ => shortDate(isoDate),
    };
  }

  static String relativeTime(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'دلوقتي';
    if (diff.inMinutes < 60) return 'من ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'من ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'من ${diff.inDays} يوم';
    return shortDate(isoDate(local));
  }
}
