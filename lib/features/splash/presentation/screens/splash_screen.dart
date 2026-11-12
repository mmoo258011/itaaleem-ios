import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/smart_ui/smart_shell_state.dart';
import 'package:itaaleem/features/splash/presentation/providers/app_startup.dart';
import 'package:itaaleem/features/splash/presentation/widgets/launch_view.dart';

/// Branded cold-start screen. It never navigates: the router keeps the app
/// here until [splashReleasedProvider] flips, which this screen does after
/// [appStartupProvider] succeeds (session restored, center loaded,
/// onboarding flags read, at least [minSplashDuration] shown).
///
/// It draws [LaunchView]: the logo stays exactly where the native launch
/// window left it, the name fades in under it with the loading dots. A
/// student going to the smart UI keeps the same picture (its loading screen
/// is the same [LaunchView]), so there's no fade-out then; anyone else gets
/// a short fade-out before login / home fades in. If the startup work times
/// out (no/slow network) the dots give way to "تعذر الاتصال" with a retry.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  /// The name and the credit, 300ms after the logo (already on screen).
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.43, 1, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _exitFade = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(CurvedAnimation(parent: _exit, curve: Curves.easeOutCubic));

  bool _started = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(appStartupProvider, (previous, next) {
      if (next.hasValue && !next.isLoading) _handOver();
    }, fireImmediately: true);
    // A timed-out startup recovers by itself if the session restore settles
    // late (e.g. the network came back).
    ref.listenManual(authControllerProvider, (previous, next) {
      if (!next.isLoading && ref.read(startupWorkProvider).hasError) {
        ref.invalidate(startupWorkProvider);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_started) return;
    _started = true;
    // Decode the logo before Flutter's first frame is shown (see
    // FirstFrameGate) so the native splash hands straight over to it.
    precacheImage(
      const AssetImage(splashLogoAsset),
      context,
    ).whenComplete(FirstFrameGate.release);
    if (_reduceMotion) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  Future<void> _handOver() async {
    if (_exit.isAnimating || _exit.isCompleted) return;
    // The smart UI's loading screen is this same picture: no fade-out.
    if (!_reduceMotion && !ref.read(opensSmartShellProvider)) {
      try {
        // Let the intro finish first if startup was faster than it.
        if (_intro.isAnimating) await _intro.forward().orCancel;
        if (!mounted) return;
        await _exit.forward().orCancel;
      } on TickerCanceled {
        // Disposed mid-animation — the release below still goes through.
      }
    }
    ref.read(splashReleasedProvider.notifier).release();
  }

  @override
  void dispose() {
    _intro.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final work = ref.watch(startupWorkProvider);
    return Scaffold(
      backgroundColor: launchBackground,
      body: FadeTransition(
        opacity: _exitFade,
        child: LaunchView(
          reveal: _reveal,
          failed: work.hasError && !work.isLoading,
          onRetry: () => retryStartup(ref),
          showCenterLogo: work.hasValue,
        ),
      ),
    );
  }
}
