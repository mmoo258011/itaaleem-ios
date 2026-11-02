import 'dart:async';

import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/services/fcm_service.dart';
import 'package:itaaleem/features/activation/presentation/providers/activation_invalidation.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/grade_change/grade_change_api.dart';
import 'package:itaaleem/features/subjects/data/datasources/subjects_remote_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _syncedKey = 'grade_change_synced_v1';

/// Whether [r] moved the student (approved) or moved them back (reverted).
bool changesGrade(GradeChangeRequest r) =>
    r.status == GradeChangeStatus.approved ||
    r.status == GradeChangeStatus.reverted;

/// Runs [apply] once per finished request (id + status), remembered across
/// launches. Returns whether it ran.
Future<bool> runOncePerGradeChange(
  GradeChangeRequest r,
  Future<void> Function() apply,
) async {
  if (!changesGrade(r)) return false;
  final mark = '${r.id}:${r.status.name}';
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_syncedKey) == mark) return false;
    await apply();
    await prefs.setString(_syncedKey, mark);
    return true;
  } catch (_) {
    return false;
  }
}

/// The student's grade changed (approved or reverted): the profile, the
/// center membership (`grade_id`), subjects, lessons, exams, files and their
/// offline cache all reload for the new course — no logout needed. The
/// app-config refetch follows from the membership's grade changing.
Future<void> refreshForNewGrade(
  void Function(ProviderOrFamily) invalidate,
  Future<void> Function() refreshProfile,
) async {
  await SubjectsCache.clear();
  await refreshProfile();
  invalidate(centerMembershipProvider);
  invalidate(gradeChangeOptionsProvider);
  invalidateContent(invalidate);
}

/// From a widget (the grade-change screen).
void syncAfterGradeChange(WidgetRef ref, GradeChangeRequest r) {
  unawaited(
    runOncePerGradeChange(
      r,
      () => refreshForNewGrade(
        ref.invalidate,
        ref.read(authControllerProvider.notifier).refreshProfile,
      ),
    ),
  );
}

/// Kept alive by the app: on launch, on resume, and when a grade-change
/// push arrives, asks `/grade-change/status` (only while the feature is on)
/// and applies a finished move once.
final gradeChangeWatcherProvider = Provider<void>((ref) {
  Future<void> check() async {
    if (ref.read(authControllerProvider).valueOrNull == null) return;
    if (ref.read(centerMembershipProvider).valueOrNull == null) return;
    final config = ref.read(currentAppConfigProvider);
    if (configFeature(config, 'grade_change') != true) return;
    try {
      final r = await ref.read(gradeChangeApiProvider).status();
      if (r == null) return;
      await runOncePerGradeChange(
        r,
        () => refreshForNewGrade(
          ref.invalidate,
          ref.read(authControllerProvider.notifier).refreshProfile,
        ),
      );
    } catch (_) {}
  }

  final lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
  final pushes = FcmService.foregroundTypes
      .where((t) => t == 'grade_change')
      .listen((_) {
        ref.invalidate(gradeChangeStatusProvider);
        unawaited(check());
      });
  ref.listen(authControllerProvider.select((s) => s.valueOrNull?.id), (
    _,
    next,
  ) {
    if (next != null) unawaited(check());
  }, fireImmediately: true);
  // The flag may arrive after login (app-config loads on its own).
  ref.listen(
    currentAppConfigProvider.select(
      (c) => configFeature(c, 'grade_change') == true,
    ),
    (prev, next) {
      if (next && prev != true) unawaited(check());
    },
  );
  ref.onDispose(() {
    lifecycle.dispose();
    pushes.cancel();
  });
});
