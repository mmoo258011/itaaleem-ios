import 'dart:async';

import 'package:itaaleem/core/config/obf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/app_config/app_config.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/rating/rating_policy.dart';
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
        busy: isBusyLocation(location),
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
  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
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

  if (PlatformUtils.isIOS) {
    // Apple 5.6.1: no custom prompt — Apple decides whether to show its own.
    try {
      if (await InAppReview.instance.isAvailable()) {
        await InAppReview.instance.requestReview();
      }
    } catch (_) {}
    return;
  }

  if (!context.mounted) return;
  final rate = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final text = Theme.of(sheetContext).textTheme;
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.star_rounded, size: 44, color: scheme.primary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'عاجبك التطبيق؟ قيّمنا على جوجل بلاي ⭐',
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'رأيك بيفرق معانا وبيساعد طلاب تانيين يلاقونا',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.base),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('قيّم الآن'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: const Text('بعدين'),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (rate != true) return;
  await prefs.setBool(_ratedKey, true);
  await waitForRouteExit();
  if (context.mounted) await openRateApp(context);
}
