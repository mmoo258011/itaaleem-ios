import 'package:itaaleem/features/app_config/app_config.dart';

/// Whether to ask for a rating now (Android: our sheet; iOS: Apple's own
/// `requestReview`, which may or may not show). Never in the first 3 days
/// after install, the first minute of a session, during a video / exam /
/// live session, after the student rated, or more often than
/// `rating.interval_days` (7).
bool shouldPromptRating({
  required DateTime now,
  required DateTime installedAt,
  required DateTime? lastShown,
  required bool rated,
  required Duration sessionAge,
  required bool busy,
  required RatingConfig config,
}) {
  if (!config.enabled || rated || busy) return false;
  if (sessionAge < const Duration(minutes: 1)) return false;
  if (now.difference(installedAt) < const Duration(days: 3)) return false;
  if (lastShown != null &&
      now.difference(lastShown) < Duration(days: config.intervalDays)) {
    return false;
  }
  return true;
}

/// Screens where an interruption would hurt: the player, an exam in
/// progress, a live session.
bool isBusyLocation(String path) =>
    path.startsWith('/lesson-video') ||
    path.startsWith('/exam-taking') ||
    RegExp(r'^/live-sessions/\d').hasMatch(path) ||
    RegExp(r'^/lectures/\d').hasMatch(path) ||
    RegExp(r'^/lessons/\d').hasMatch(path) ||
    path.startsWith('/lesson-pdf') ||
    path.startsWith('/exams/');
