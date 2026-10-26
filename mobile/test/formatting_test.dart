import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:job_manager/core/formatting.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
  });

  group('AppFormat', () {
    test('parseDateOnly keeps the calendar day without a timezone shift', () {
      final date = AppFormat.parseDateOnly('2026-10-26');
      expect(date, DateTime(2026, 10, 26));
    });

    test('isoDate pads month and day', () {
      expect(AppFormat.isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('fullDate renders Arabic month names', () {
      expect(AppFormat.fullDate('2026-10-26'), contains('أكتوبر'));
    });

    test('relativeDay labels today and yesterday', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);

      expect(AppFormat.relativeDay(AppFormat.isoDate(today)), 'النهارده');
      expect(AppFormat.relativeDay(AppFormat.isoDate(yesterday)), 'امبارح');
    });

    test('relativeDay labels future dates', () {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      expect(AppFormat.relativeDay(AppFormat.isoDate(tomorrow)), 'بعد 1 يوم');
    });

    test('invalid or missing dates render a dash', () {
      expect(AppFormat.shortDate(null), '—');
      expect(AppFormat.shortDate('not-a-date'), '—');
      expect(AppFormat.parseDateOnly('2026-13'), isNull);
      expect(AppFormat.parseDateOnly(''), isNull);
    });

    test('todayIso is a valid date-only string', () {
      final value = AppFormat.todayIso();
      expect(value, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(AppFormat.parseDateOnly(value), isNotNull);
    });
  });
}
