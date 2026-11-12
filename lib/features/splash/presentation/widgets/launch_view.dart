import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/theme/dynamic_theme.dart';
import 'package:itaaleem/core/widgets/developer_credit.dart';
import 'package:itaaleem/features/center/presentation/providers/branding_provider.dart';
import 'package:itaaleem/features/splash/presentation/providers/app_startup.dart'
    show splashLogoAsset;

/// The launch screen's background in every phase and in both themes: the
/// native launch window (Android `splash_background`, iOS
/// `LaunchBackground`), the Flutter splash, the smart UI's loading screen
/// and the WebView behind it.
const launchBackground = Color(0xFFFFFFFF);

/// Same width as the native launch logo, so every phase lines up.
const launchLogoWidth = 140.0;

/// One launch screen from the native window until the first real page: white,
/// the logo at the exact centre of the screen (where the native launch window
/// draws it), the app name and a loading indicator under it, the center's
/// logo and the developer credit at the bottom.
///
/// The splash and the smart UI's loading screen both draw this, so going
/// from one to the other changes nothing on screen. Always light, even in
/// dark mode.
class LaunchView extends ConsumerWidget {
  const LaunchView({
    super.key,
    this.reveal,
    this.failed = false,
    this.onRetry,
    this.showCenterLogo = true,
  });

  /// Fades the name and the credit in (the splash's intro); null → shown.
  final Animation<double>? reveal;

  /// Startup timed out: the indicator gives way to an error with a retry.
  final bool failed;
  final VoidCallback? onRetry;
  final bool showCenterLogo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = ref.watch(brandingProvider.select((b) => b.primary));
    final centerLogo = ref.watch(brandingProvider.select((b) => b.logoUrl));
    final reveal = this.reveal ?? kAlwaysCompleteAnimation;

    return Theme(
      data: DynamicTheme.light(primary),
      child: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: launchBackground,
            ),
            child: ColoredBox(
              color: launchBackground,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Equal space above and below → the logo sits at the exact
                  // centre of the screen whatever is drawn under it.
                  Column(
                    children: [
                      const Spacer(),
                      Image.asset(
                        splashLogoAsset,
                        width: launchLogoWidth,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        semanticLabel: 'منصة أونلاين',
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.xl,
                              AppSpacing.lg,
                              AppSpacing.xl,
                              0,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FadeTransition(
                                    opacity: reveal,
                                    child: _Name(cs: cs),
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: failed
                                        ? _StartupError(onRetry: onRetry)
                                        : SizedBox(
                                            height: 24,
                                            child: Center(
                                              child: LaunchDots(
                                                color: cs.primary,
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 500),
                              switchInCurve: Curves.easeOutCubic,
                              child:
                                  showCenterLogo &&
                                      centerLogo != null &&
                                      centerLogo.isNotEmpty
                                  ? _CenterLogo(
                                      key: ValueKey(centerLogo),
                                      url: centerLogo,
                                    )
                                  : const SizedBox(height: 56),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FadeTransition(
                              opacity: reveal,
                              child: Text(
                                DeveloperCredit.credit,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Name extends StatelessWidget {
  const _Name({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'منصة أونلاين',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.2,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'تعليم بلا حدود',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Three dots rising and brightening in a wave. The phase comes from the
/// clock, not from the widget's own start, so a new [LaunchDots] (the smart
/// UI's loading screen taking over from the splash) carries on the same wave.
class LaunchDots extends StatefulWidget {
  const LaunchDots({super.key, required this.color});

  final Color color;

  static const _period = 1200;

  @override
  State<LaunchDots> createState() => _LaunchDotsState();
}

class _LaunchDotsState extends State<LaunchDots>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t =
        (DateTime.now().millisecondsSinceEpoch % LaunchDots._period) /
        LaunchDots._period;
    return Semantics(
      label: 'جارٍ التحميل',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < 3; i++) _dot((t - i / 3) % 1)],
      ),
    );
  }

  Widget _dot(double phase) {
    final wave = math.sin(phase * math.pi * 2) * 0.5 + 0.5;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Transform.translate(
        offset: Offset(0, -4 * wave),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.35 + 0.65 * wave),
          ),
        ),
      ),
    );
  }
}

/// Shown in place of the dots when startup timed out.
class _StartupError extends StatelessWidget {
  const _StartupError({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, color: cs.error, size: 32),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'تعذر الاتصال',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'تأكد من اتصالك بالإنترنت ثم حاول مرة أخرى',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'إعادة المحاولة',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterLogo extends StatelessWidget {
  const _CenterLogo({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          memCacheWidth: 360,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 300),
          placeholder: (context, url) => const SizedBox.shrink(),
          errorWidget: (context, url, error) =>
              Icon(Icons.school_rounded, color: cs.primary),
        ),
      ),
    );
  }
}
