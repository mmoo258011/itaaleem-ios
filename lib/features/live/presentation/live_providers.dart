import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/features/live/data/live_api.dart';
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';

/// Whether "البث المباشر" may show at all: `settings.live_enabled`. A
/// missing, `false` or failed settings fetch → off.
final liveEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return (await ref.watch(appSettingsProvider.future)).liveEnabled;
  } catch (_) {
    return false;
  }
});

/// `GET /live-sessions`, live first then upcoming. `null` = hide the whole
/// section: the switch is off, or the call failed in any way (403 for a
/// center without live) — silently, no message.
final liveSessionsProvider = FutureProvider.autoDispose<List<LiveSession>?>((
  ref,
) async {
  if (!await ref.watch(liveEnabledProvider.future)) return null;
  try {
    final list = await ref.read(liveApiProvider).getSessions();
    // The server already sorts; keep that, but make sure live comes first.
    return [...list.where((s) => s.isLive), ...list.where((s) => !s.isLive)];
  } catch (e) {
    if (kDebugMode) debugPrint('>>> live-sessions hidden: $e');
    return null;
  }
});

/// `h:mm ص/م` in device time.
String formatLiveTime(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${t.hour < 12 ? 'ص' : 'م'}';
}

/// "النهارده 8:00 م" / "بكرة 8:00 م" / "21 أكتوبر 8:00 م".
String formatLiveWhen(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  final time = formatLiveTime(t);
  if (diff == 0) return 'النهارده $time';
  if (diff == 1) return 'بكرة $time';
  final year = t.year == now.year ? '' : ' ${t.year}';
  return '${t.day} ${_months[t.month - 1]}$year $time';
}

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
