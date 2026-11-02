import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/content/content_policy.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/courses/presentation/providers/courses_providers.dart';
import 'package:itaaleem/features/exams/presentation/providers/exams_providers.dart';
import 'package:itaaleem/features/home/presentation/providers/home_subjects_provider.dart';
import 'package:itaaleem/features/subjects/presentation/providers/subjects_providers.dart';

/// After a successful `POST /activate-code`: reload everything whose lock
/// state may have changed (subjects, lectures, exams, files, watermark) and
/// the student's profile, so newly unlocked content shows up right away.
void invalidateAfterActivation(WidgetRef ref) {
  invalidateContent(ref.invalidate);
  unawaited(ref.read(authControllerProvider.notifier).refreshProfile());
}

/// Every provider holding course content (subjects, lectures, exams, files,
/// watermark) — after an activation or a move to another grade.
void invalidateContent(void Function(ProviderOrFamily) invalidate) {
  invalidate(coursesProvider);
  invalidate(availableCoursesProvider);
  invalidate(homeSubjectsProvider);
  invalidate(subjectsListProvider);
  invalidate(subjectDetailsProvider);
  invalidate(homeLessonsProvider);
  invalidate(attachmentsProvider);
  invalidate(lessonAttachmentsProvider);
  invalidate(examsListProvider);
  invalidate(subjectExamsProvider);
  invalidate(lectureExamsProvider);
  invalidate(examDetailsProvider);
  invalidate(lessonWatermarkProvider);
}
