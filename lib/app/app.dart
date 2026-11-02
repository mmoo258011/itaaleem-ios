import 'package:itaaleem/core/network/load_recovery.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:itaaleem/features/settings/presentation/rate_app.dart'
    show ratingWatcherProvider;
import 'package:itaaleem/features/grade_change/grade_change_refresh.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/theme/dynamic_theme.dart';
import 'package:itaaleem/features/center/presentation/providers/branding_provider.dart';
import 'package:itaaleem/core/localization/generated/app_localizations.dart';
import 'package:itaaleem/core/network/auth_events.dart';
import 'package:itaaleem/core/network/connectivity_provider.dart';
import 'package:itaaleem/core/network/device_lock_events.dart';
import 'package:itaaleem/core/services/fcm_service.dart';
import 'package:itaaleem/core/widgets/capture_guard.dart';
import 'package:itaaleem/core/widgets/no_connection_screen.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/auth/presentation/widgets/device_lock_dialog.dart';
import 'package:itaaleem/features/parent/presentation/guardian_controller.dart';
import 'package:itaaleem/features/parent/presentation/screens/parent_home_screen.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/settings/presentation/providers/theme_mode_provider.dart';
import 'package:itaaleem/features/video/data/offline/offline_license_checker.dart';
import 'package:itaaleem/features/video/data/offline/offline_progress_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Guards [App]'s device-lock listener against stacking dialogs.
bool _sessionEndedShowing = false;
bool _deviceLockShowing = false;

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final primary = ref.watch(brandingProvider.select((b) => b.primary));

    // FCM message listeners (foreground local notification, tap-to-navigate)
    // are set up exactly once regardless of auth state — `setupListeners` is
    // internally idempotent, so calling it on every rebuild is harmless.
    final fcm = ref.read(fcmServiceProvider);
    fcm.guardianHooks ??= GuardianPushHooks(
      isGuardianMode: () =>
          ref.read(guardianControllerProvider).valueOrNull != null,
      sendToken: (token) =>
          ref.read(guardianControllerProvider.notifier).api.sendFcmToken(token),
      openChild: (studentId) {
        final context = rootNavigatorKey.currentContext;
        if (context == null) return;
        context.go(parentHomePath);
        context.push(parentChildPath(studentId));
      },
    );
    fcm.setupListeners();

    // Keeps the offline-progress sync service alive (it listens to
    // connectivity and uploads pending progress whenever the network returns).
    ref.watch(offlineProgressSyncServiceProvider);

    // `GET /app-config` at launch and on every resume.
    ref.watch(appConfigLifecycleProvider);

    // A course move approved/reverted by the center: applied once, on
    // launch, resume or its push — no logout needed.
    ref.watch(gradeChangeWatcherProvider);
    ref.watch(loadRecoveryProvider);

    // Every 7 days (not the first 3 days / first minute / mid-lesson): our
    // sheet on Android, Apple's own requestReview on iOS.
    ref.watch(ratingWatcherProvider);

    // Once per app launch, right after the session restores (`GET
    // /profile` — see AuthController.build): re-validates offline downloads
    // against the student's real enrollment and flushes any progress
    // recorded while playing offline, and (a real, non-demo session only)
    // registers this device for push notifications — both `runOnceForSession`
    // and `FcmService.init()` are no-ops on a repeat call, so this covers
    // both "just logged in" and "app started already logged in" with the
    // same listener.
    ref.listen(authControllerProvider, (previous, next) {
      final student = next.valueOrNull;
      if (student != null) {
        ref.read(offlineLicenseCheckerProvider).runOnceForSession(student);
        if (!student.isDemo) {
          final fcm = ref.read(fcmServiceProvider);
          fcm.init(student.id);
          fcm.flushPendingNavigation();
        }
      }
    });

    // A 401 from any authenticated endpoint besides login/register/the
    // startup session restore (see `ErrorMappingInterceptor`) means an
    // established session's token was rejected mid-use — force the student
    // back to `/login` rather than leaving every screen stuck on a
    // "غير مصرح" error forever.
    ref.listen(unauthorizedStreamProvider, (previous, next) async {
      if (!next.hasValue) return;
      // Several in-flight requests may 401 at once — only the first counts.
      final wasLoggedIn = ref.read(authControllerProvider).valueOrNull != null;
      await ref.read(authControllerProvider.notifier).forceLogout();
      if (!wasLoggedIn || _sessionEndedShowing) return;
      _sessionEndedShowing = true;
      // Let the redirect to /login settle, then say why.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        AppToast.showError(context, 'انتهت الجلسة، سجّل الدخول مرة أخرى');
      }
      _sessionEndedShowing = false;
    });

    // This device was removed from the account (e.g. the center admin reset
    // the student's devices): log out cleanly, then say why. Several
    // in-flight requests may fail at once — only the first one shows it.
    ref.listen(deviceLockStreamProvider, (previous, next) async {
      final message = next.valueOrNull;
      if (message == null || _deviceLockShowing) return;
      if (ref.read(authControllerProvider).valueOrNull == null) return;
      _deviceLockShowing = true;
      final center = ref.read(joinedCenterProvider);
      await ref.read(authControllerProvider.notifier).forceLogout();
      // Let the redirect to /login settle before opening the dialog.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        await showDeviceLockDialog(
          context,
          ref,
          message: message,
          center: center,
        );
      }
      _deviceLockShowing = false;
    });

    return MaterialApp.router(
      title: 'منصة أونلاين',
      debugShowCheckedModeBanner: false,
      theme: DynamicTheme.light(primary),
      darkTheme: DynamicTheme.dark(primary),
      themeMode: themeMode,
      // The default 200ms cross-fade lerps the entire ThemeData and rebuilds
      // the whole tree every frame — the source of the light/dark freeze.
      // A short, cheap fade instead.
      themeAnimationDuration: const Duration(milliseconds: 80),
      themeAnimationCurve: Curves.easeOut,
      // Arabic-first per plan: `ar` is the default/primary locale, `en` is
      // the secondary. Flutter derives RTL Directionality from the active
      // locale automatically (Arabic is a right-to-left script) — verified
      // below in debug builds rather than left implicit.
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
      builder: (context, child) {
        if (kDebugMode) {
          final direction = Directionality.of(context);
          assert(
            direction == TextDirection.rtl,
            'Expected RTL Directionality for the default `ar` locale, '
            'got $direction.',
          );
        }
        return CaptureGuard(
          child: _ConnectivityGate(
            router: router,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

/// Paths that stay reachable with no connectivity for a logged-out user —
/// everywhere else [_ConnectivityGate] replaces the whole routed app with
/// [NoConnectionScreen] (a logged-in student is never blocked, see there). "المحمّلات" and a lecture player both need to work
/// offline (that's the entire point of `OfflineDownloadManager`/
/// `LocalRangeServer`); the lecture player itself already knows how to fall
/// back to an honest "not downloaded" message when there's nothing offline
/// to play.
const _offlineCapablePathPrefixes = ['/downloads', '/lectures/'];

/// Replaces the entire routed app with [NoConnectionScreen] whenever
/// [connectivityStatusProvider] reports no connectivity, so no screen is
/// reachable while offline — except the paths in
/// [_offlineCapablePathPrefixes]. Loading/error states fall back to showing
/// [child] rather than blocking the app on an inconclusive check.
class _ConnectivityGate extends ConsumerWidget {
  const _ConnectivityGate({required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(connectivityStatusProvider).valueOrNull ?? true;
    if (isOnline) return child;

    // A logged-in student (or one whose session is still being restored —
    // that path already falls back to the cached profile offline) always
    // gets in: cached subjects and downloaded videos work without internet.
    // Only a confirmed logged-out user is blocked, since login needs the
    // network.
    final auth = ref.watch(authControllerProvider);
    if (auth.isLoading || auth.valueOrNull != null) return child;
    final guardian = ref.watch(guardianControllerProvider);
    if (guardian.isLoading || guardian.valueOrNull != null) return child;

    // Read fresh on every rebuild this gate actually runs (driven by
    // connectivityStatusProvider changing) — covers the common case of
    // losing connection while already on an offline-capable screen. It
    // won't re-evaluate on an in-place navigation while already offline
    // (routeInformationProvider isn't itself watched here), which is an
    // accepted minor gap rather than restructuring this gate around
    // GoRouter's own listenable.
    final location = router.routeInformationProvider.value.uri.path;
    final isOfflineCapable = _offlineCapablePathPrefixes.any(
      location.startsWith,
    );
    return isOfflineCapable ? child : const NoConnectionScreen();
  }
}
