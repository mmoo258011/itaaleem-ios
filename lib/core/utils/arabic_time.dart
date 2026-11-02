const _months = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// «الآن»، «منذ 5 دقائق»، «منذ ساعتين»، «أمس»، «12 أكتوبر» (and the year
/// when it isn't this year). Both times local.
String arabicRelativeTime(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(time);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) {
    return 'منذ ${_count(diff.inMinutes, 'دقيقة', 'دقيقتين', 'دقائق')}';
  }
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(time.year, time.month, time.day);
  final days = today.difference(day).inDays;
  if (days == 0) {
    return 'منذ ${_count(diff.inHours, 'ساعة', 'ساعتين', 'ساعات')}';
  }
  if (days == 1) return 'أمس';
  return arabicDate(time, now: n);
}

/// «12 أكتوبر», or «12 أكتوبر 2025» outside the current year.
String arabicDate(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final base = '${time.day} ${_months[time.month - 1]}';
  return time.year == n.year ? base : '$base ${time.year}';
}

/// Day header for a list: «اليوم»، «أمس»، or [arabicDate].
String arabicDayLabel(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(time.year, time.month, time.day)).inDays;
  if (days == 0) return 'اليوم';
  if (days == 1) return 'أمس';
  return arabicDate(time, now: n);
}

/// 1 → «دقيقة», 2 → «دقيقتين», 3–10 → «3 دقائق», 11+ → «11 دقيقة».
String _count(int n, String one, String two, String few) {
  if (n <= 1) return one;
  if (n == 2) return two;
  if (n <= 10) return '$n $few';
  return '$n $one';
}

/// 950 → «950», 1200 → «1.2 ألف», 3400000 → «3.4 مليون».
String compactCount(int n) {
  String trim(double v) =>
      v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  if (n >= 1000000) return '${trim(n / 1000000)} مليون';
  if (n >= 1000) return '${trim(n / 1000)} ألف';
  return '$n';
}
