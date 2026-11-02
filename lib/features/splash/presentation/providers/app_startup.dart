import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/auth/presentation/providers/signed_in_before_provider.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:itaaleem/features/onboarding/presentation/providers/permissions_onboarding_provider.dart';
import 'package:itaaleem/features/parent/presentation/guardian_controller.dart';

/// The splash's logo — also the native launch screens' artwork, so the
/// native → Flutter handoff shows the same image in the same place.
const splashLogoAsset = 'assets/images/splash_logo.png';

/// The splash stays up at least this long (counted from launch), so it
/// reads as a deliberate branded moment rather than a flash. Kept short:
/// a cached session enters immediately (revalidated in the background), so
/// nothing else should hold the first screen back.
const minSplashDuration = Duration(milliseconds: 400);

/// Past this, the splash stops waiting and shows its "تعذر الاتصال" state
/// with a retry instead of hanging.
const _maxStartupWait = Duration(seconds: 12);

/// Center data is a nice-to-have for the first screen, never a blocker.
const _maxCenterWait = Duration(seconds: 4);

/// Set by [FirstFrameGate.hold] at the very top of `main`.
DateTime? _launchedAt;

/// The startup work outran [_maxStartupWait] (typically: no/very slow
/// network while the session restore has no cached profile to fall back on).
class StartupTimeoutException implements Exception {
  const StartupTimeoutException();
}

/// Everything the first real screen depends on, loaded behind the splash:
/// the session restore (token + `GET /profile`, falling back to the cached
/// profile), then the joined center, alongside the first-launch onboarding
/// flags the router needs to pick the right destination.
///
/// Fails only with [StartupTimeoutException]. Reads (not watches) its
/// inputs: it describes the one-time cold start and must never go back to
/// loading on a later login/logout.
final startupWorkProvider = FutureProvider<void>((ref) async {
  Future<void> settle(Future<Object?> future) =>
      future.then<void>((_) {}, onError: (Object _) {});

  Future<void> sessionAndCenter() async {
    await settle(ref.read(authControllerProvider.future));
    if (ref.read(authControllerProvider).valueOrNull == null) return;
    await settle(
      ref.read(centerMembershipProvider.future).timeout(_maxCenterWait),
    );
  }

  await Future.wait([
    sessionAndCenter(),
    settle(ref.read(guardianControllerProvider.future)),
    settle(ref.read(onboardingSeenProvider.future)),
    settle(ref.read(permissionsOnboardingSeenProvider.future)),
    settle(ref.read(signedInBeforeProvider.future)),
  ]).timeout(
    _maxStartupWait,
    onTimeout: () => throw const StartupTimeoutException(),
  );
});

/// Done once the startup work has succeeded **and** [minSplashDuration] has
/// passed since launch (a retry doesn't restart the minimum).
final appStartupProvider = FutureProvider<void>((ref) async {
  final shown = DateTime.now().difference(_launchedAt ??= DateTime.now());
  await Future.wait([
    ref.watch(startupWorkProvider.future),
    if (shown < minSplashDuration)
      Future<void>.delayed(minSplashDuration - shown),
  ]);
});

/// Flips to `true` once the splash may hand over — the router keeps the app
/// on the splash until then. The splash releases it after its fade-out
/// (so the next page fades in over a clean background instead of jumping);
/// as a safety net it also releases itself shortly after
/// [appStartupProvider] succeeds, splash or not.
final splashReleasedProvider = NotifierProvider<SplashReleaseController, bool>(
  SplashReleaseController.new,
);

class SplashReleaseController extends Notifier<bool> {
  static const _fallback = Duration(milliseconds: 350);

  @override
  bool build() {
    ref.listen(appStartupProvider, (previous, next) {
      if (next.hasValue && !next.isLoading) Timer(_fallback, release);
    }, fireImmediately: true);
    return false;
  }

  void release() {
    if (state) return;
    state = true;
    final launchedAt = _launchedAt;
    if (launchedAt != null && !kReleaseMode) {
      debugPrint(
        '[perf] app start → first screen: '
        '${DateTime.now().difference(launchedAt).inMilliseconds}ms',
      );
    }
  }
}

/// Retries a timed-out startup. The session restore is restarted too if it
/// is still stuck on its first attempt (e.g. the request hung while
/// offline); a settled session is kept as is.
void retryStartup(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  if (auth.isLoading && !auth.hasValue) {
    ref.invalidate(authControllerProvider);
  }
  ref.invalidate(startupWorkProvider);
}

/// Holds Flutter's first frame until the splash logo is decoded, so the
/// native launch screen hands over straight to the Flutter splash with the
/// logo already drawn — no blank frame in between.
///
/// Always releases after [_fallback], whatever happens, so it can't keep the
/// app on the native splash.
abstract final class FirstFrameGate {
  static const _fallback = Duration(milliseconds: 1500);
  static bool _deferred = false;
  static Timer? _timer;

  /// Call right after `WidgetsFlutterBinding.ensureInitialized()`.
  static void hold() {
    if (_deferred) return;
    _deferred = true;
    _launchedAt ??= DateTime.now();
    WidgetsBinding.instance.deferFirstFrame();
    _timer = Timer(_fallback, release);
  }

  /// Idempotent.
  static void release() {
    if (!_deferred) return;
    _deferred = false;
    _timer?.cancel();
    WidgetsBinding.instance.allowFirstFrame();
  }
}
