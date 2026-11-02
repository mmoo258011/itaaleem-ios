import 'package:itaaleem/features/subscriptions/presentation/providers/subscription_providers.dart';
import 'package:itaaleem/features/subscriptions/data/repositories/subscription_repository.dart';
import 'dart:async';

import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/update/presentation/providers/update_providers.dart';

import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/home/presentation/providers/banners_provider.dart';
import 'package:itaaleem/features/notifications/presentation/providers/notifications_providers.dart';
import 'package:itaaleem/features/subjects/presentation/providers/subjects_providers.dart';
import 'package:itaaleem/features/teachers/presentation/providers/teachers_providers.dart';
import 'package:itaaleem/features/exams/presentation/providers/exams_providers.dart';
import 'package:itaaleem/features/assignments/presentation/providers/assignments_providers.dart';

/// Drops every cached subject/lesson/attachment result so the next watch
/// refetches — lock state (`is_accessible`) lives in that data, so this is
/// what makes a subscription activated from the dashboard show up.
void invalidateContent(Ref ref) {
  ref.invalidate(subjectsByTermProvider);
  ref.invalidate(subjectsListProvider);
  ref.invalidate(subjectDetailsProvider);
  ref.invalidate(homeLessonsProvider);
  ref.invalidate(attachmentsProvider);
  ref.invalidate(lessonAttachmentsProvider);
  ref.invalidate(subjectSubscriptionProvider);
  ref.invalidate(mySubscriptionsProvider);
  ref.invalidate(examsListProvider);
  ref.invalidate(subjectExamsProvider);
  ref.invalidate(allAssignmentsProvider);
  ref.invalidate(subjectAssignmentsProvider);
  ref.invalidate(assignmentDetailsProvider);
}

/// Pull-to-refresh: re-reads the profile (subscription flags) and reloads
/// all content, completing once the main lists have reloaded.
Future<void> refreshAll(WidgetRef ref, {int? subjectId}) async {
  final profile = ref.read(authControllerProvider.notifier).refreshProfile();
  // The center may have switched the current term.
  ref.invalidate(subjectsByTermProvider);
  ref.invalidate(subjectsListProvider);
  ref.invalidate(subjectDetailsProvider);
  ref.invalidate(homeLessonsProvider);
  ref.invalidate(attachmentsProvider);
  ref.invalidate(lessonAttachmentsProvider);
  ref.invalidate(bannersProvider);
  reloadAppSettings(ref);
  if (ref.read(appVersionInfoProvider).hasError) {
    ref.invalidate(appVersionInfoProvider);
  }
  final centerId = ref.read(centerMembershipProvider).valueOrNull?.centerId;
  if (centerId != null) refreshCenter(ref, centerId);
  ref.invalidate(teachersProvider);
  ref.invalidate(notificationsControllerProvider);
  SubscriptionRepository.resetEndpointCheck();
  ref.invalidate(subjectSubscriptionProvider);
  ref.invalidate(mySubscriptionsProvider);
  ref.invalidate(examsListProvider);
  ref.invalidate(subjectExamsProvider);
  ref.invalidate(allAssignmentsProvider);
  ref.invalidate(subjectAssignmentsProvider);
  ref.invalidate(assignmentDetailsProvider);
  await Future.wait<Object?>([
    profile,
    if (subjectId != null)
      ref.read(subjectDetailsProvider(subjectId).future)
    else
      ref.read(subjectsListProvider.future),
  ]).catchError((_) => const <Object?>[]);
}

/// Whenever the profile's access flags change, all content is reloaded (see
/// [invalidateContent]) so a newly activated subscription unlocks lessons.
/// There is deliberately no polling: `GET /profile` is fetched on session
/// restore/login, on pull-to-refresh ([refreshAll]) and via [check] (e.g.
/// after the subscription sheet closes) — never on a timer.
class SubscriptionWatcher {
  SubscriptionWatcher(this._ref) {
    _ref.listen(
      authControllerProvider.select(
        (s) =>
            (s.valueOrNull?.hasPaidAccess, s.valueOrNull?.subscriptionStatus),
      ),
      (previous, next) {
        if (previous != null && previous != next) invalidateContent(_ref);
      },
    );
  }

  final Ref _ref;

  void check() {
    final student = _ref.read(authControllerProvider).valueOrNull;
    if (student == null || student.isDemo) return;
    unawaited(_ref.read(authControllerProvider.notifier).refreshProfile());
  }
}

final subscriptionWatcherProvider = Provider<SubscriptionWatcher>((ref) {
  return SubscriptionWatcher(ref);
});
