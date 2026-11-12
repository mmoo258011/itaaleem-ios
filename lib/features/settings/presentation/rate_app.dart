import 'dart:async';

import 'package:itaaleem/core/config/obf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/app_config/app_config.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/rating/rating_policy.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App Store id (the Play listing comes from the package name).
final _appStoreId = Obf.appStoreId;

// Device-level on purpose (kept out of the logout wipe): the prompt is about
// the app, not the account.
const _installedKey = 'rating_installed_at';
const _lastShownKey = 'rating_last_shown';
const _ratedKey = 'rating_done';

/// Whether «قيّم التطبيق» shows in the profile (`rating.enabled`, default on).
final rateAppEnabledProvider = Provider<bool>(
  (ref) => ref.watch(currentAppConfigProvider).rating.enabled,
);

/// The store page: App Store on iOS, Google Play on Android.
Future<void> openRateApp(BuildContext context) async {
  try {
    await InAppReview.instance.openStoreListing(appStoreId: _appStoreId);
  } catch (_) {
    if (context.mounted) AppToast.showError(context, 'تعذر فتح المتجر');
  }
}

/// Kept alive by the app: checks every couple of minutes (and on resume)
/// whether it's a good moment to ask for a rating — see
/// [shouldPromptRating].
final ratingWatcherProvider = Provider<void>((ref) {
  final sessionStart = DateTime.now();
  var asking = false;

  Future<void> check() async {
    if (asking) return;
    if (ref.read(authControllerProvider).valueOrNull == null) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final location = ref
        .read(appRouterProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
    asking = true;
    try {
      await _maybePrompt(
        context,
        config: ref.read(currentAppConfigProvider).rating,
        sessionAge: DateTime.now().difference(sessionStart),
        // Inside the smart UI: a lesson, an exam or a game.
        busy: isBusyLocation(location) || SmartShellHooks.busy.value,
      );
    } finally {
      asking = false;
    }
  }

  // Records the install date on the first run of this version.
  unawaited(_installedAt());
  final timer = Timer.periodic(
    const Duration(minutes: 2),
    (_) => unawaited(check()),
  );
  final lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
  // A good moment: a lesson finished, a game won (see SmartShellHooks).
  SmartShellHooks.onPositiveMoment = () => unawaited(check());
  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
    SmartShellHooks.onPositiveMoment = null;
  });
});

Future<DateTime> _installedAt() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getInt(_installedKey);
  if (stored != null) return DateTime.fromMillisecondsSinceEpoch(stored);
  final now = DateTime.now();
  await prefs.setInt(_installedKey, now.millisecondsSinceEpoch);
  return now;
}

Future<void> _maybePrompt(
  BuildContext context, {
  required RatingConfig config,
  required Duration sessionAge,
  required bool busy,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final last = prefs.getInt(_lastShownKey);
  final now = DateTime.now();
  final ok = shouldPromptRating(
    now: now,
    installedAt: await _installedAt(),
    lastShown: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    rated: prefs.getBool(_ratedKey) ?? false,
    sessionAge: sessionAge,
    busy: busy,
    config: config,
  );
  if (!ok || !context.mounted) return;
  // Counted as shown up front: closing the sheet = «بعدين» (7 days).
  await prefs.setInt(_lastShownKey, now.millisecondsSinceEpoch);

  // The stores' own in-app review, on both platforms (no custom sheet:
  // Apple 5.6.1, and Google wants no question before it). They decide
  // whether it actually shows; «قيّم التطبيق» in «حسابي» opens the store
  // page whenever the student wants.
  try {
    if (await InAppReview.instance.isAvailable()) {
      await InAppReview.instance.requestReview();
    }
  } catch (_) {}
}
