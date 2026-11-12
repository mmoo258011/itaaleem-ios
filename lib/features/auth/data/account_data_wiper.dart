import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/services/notification_history_service.dart';
import 'package:itaaleem/features/center/presentation/providers/branding_provider.dart';
import 'package:itaaleem/features/channel/presentation/providers/channel_providers.dart';
import 'package:itaaleem/features/chat/presentation/providers/chat_providers.dart';
import 'package:itaaleem/features/courses/presentation/providers/courses_providers.dart';
import 'package:itaaleem/features/home/presentation/providers/home_subjects_provider.dart';
import 'package:itaaleem/features/smart_ui/completion/link_referral.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_session.dart';
import 'package:itaaleem/features/video/data/offline/offline_download_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-level preferences that survive a logout — everything else in
/// SharedPreferences belongs to the account that was signed in.
const _devicePrefsKeys = {
  'theme_mode',
  'video_playback_quality_height',
  'yt_quality_height',
  'video_playback_speed',
  'youtube_player_kind',
  'onboarding_seen',
  'permissions_onboarding_seen',
  'has_signed_in_before',
  'install_first_run_done',
  'rate_prompt_completed_ids',
  'rate_prompt_shown',
  linkReferralCheckedKey,
  linkCenterCodeKey,
  linkRefKey,
};

/// Logout / forced logout: removes every trace of the signed-in account
/// from this device so the next account starts clean — offline videos
/// (encrypted files, rows and the AES key), cached PDFs and downloaded
/// files, saved notifications, chat, exam history, subject/center caches,
/// and the in-memory state of the user-scoped providers.
///
/// Kept: theme, preferred video quality/speed/player, onboarding flags and
/// the device id (secure storage, untouched here). The auth token and the
/// cached profile are cleared by the caller.
///
/// Every step is best effort — a failure never blocks the logout itself.
Future<void> wipeAccountData(Ref ref) async {
  Future<void> step(String name, Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      if (kDebugMode) debugPrint('[wipeAccountData] $name failed: $e');
    }
  }

  await step('smart UI session', clearSmartUiSession);
  await step(
    'offline videos',
    () => ref.read(offlineDownloadManagerProvider).deleteAllForLogout(),
  );
  await step('temp files (PDF cache)', () async {
    final tmp = await getTemporaryDirectory();
    await _emptyDirectory(tmp);
  });
  await step('downloaded files', () async {
    final docs = await getApplicationDocumentsDirectory();
    final downloads = Directory('${docs.path}/downloads');
    if (await downloads.exists()) await downloads.delete(recursive: true);
  });
  await step('preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (!_devicePrefsKeys.contains(key)) await prefs.remove(key);
    }
  });

  // User-scoped providers that aren't autoDispose (the `ref.cached` ones
  // already reload on a different student id). Through the container, not
  // `ref`: [ref] is the auth controller's, and several of these watch it —
  // `ref.invalidate` on a dependent trips Riverpod's debug-only circular
  // dependency assert (CircularDependencyError), which escaped logout /
  // forceLogout before they set the logged-out state. Release builds skip
  // that assert; the container call behaves the same in both.
  ref.container
    ..invalidate(notificationHistoryProvider)
    ..invalidate(chatControllerProvider)
    ..invalidate(channelMessagesProvider)
    ..invalidate(coursesProvider)
    ..invalidate(availableCoursesProvider)
    ..invalidate(homeSubjectsProvider)
    ..invalidate(brandingProvider);
}

Future<void> _emptyDirectory(Directory dir) async {
  if (!await dir.exists()) return;
  await for (final entity in dir.list(followLinks: false)) {
    try {
      await entity.delete(recursive: true);
    } catch (_) {
      // A file still in use (e.g. by the OS) — skip it.
    }
  }
}

/// Whether there are offline videos on this device — the logout dialog
/// warns before deleting them.
Future<bool> hasOfflineVideos(WidgetRef ref) async {
  try {
    final videos = await ref
        .read(offlineDownloadManagerProvider)
        .getDownloadedLessons();
    return videos.isNotEmpty;
  } catch (_) {
    return false;
  }
}
