import 'package:intl/intl.dart';

/// A server UTC timestamp in the device's time zone, in plain Arabic:
/// "النهارده 3:15 م" / "امبارح 9:00 ص" / "16 أكتوبر 2026، 3:15 م".
String formatParentDate(DateTime? date) {
  if (date == null) return '—';
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final time = DateFormat('h:mm a', 'ar').format(local);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'النهارده $time';
  if (diff == 1) return 'امبارح $time';
  return '${DateFormat('d MMMM y', 'ar').format(local)}، $time';
}

/// `last_login_at`, or "لم يسجّل دخول بعد" when the student never signed in.
String formatLastLogin(DateTime? date) =>
    date == null ? 'لم يسجّل دخول بعد' : formatParentDate(date);

/// 37.5 → "37.5" ، 50 → "50".
String formatNumber(num value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(1);
