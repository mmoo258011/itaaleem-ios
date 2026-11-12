import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/core/design/smart_brand_theme.dart';
import 'package:itaaleem/core/theme/app_colors.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// Curved bottom edge for the auth screens' gradient header.
class AuthWaveClipper extends CustomClipper<Path> {
  const AuthWaveClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..lineTo(0, h - 36)
      ..quadraticBezierTo(w * 0.25, h, w * 0.5, h - 20)
      ..quadraticBezierTo(w * 0.75, h - 40, w, h - 14)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Shared frame for login / register / forgot-password: a gradient header with
/// a wave edge (icon badge, title, subtitle) and a rounded sheet that overlaps
/// it and holds the form.
///
/// Entrance animation: header fades in, then each of [fields] slides up and
/// fades in 100ms after the previous one, then [action] scales in with
/// [footer]. Wrap the shell in a `Form` if the fields need one.
class AuthShell extends StatefulWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.action,
    this.footer,
    this.onBack,
    this.headerFactor = 0.35,
    this.badgeSize = 90,
  });

  final String title;
  final String subtitle;

  /// Staggered one by one. Keep the count constant for the screen's lifetime.
  final List<Widget> fields;
  final Widget action;
  final Widget? footer;

  /// Shows a transparent app bar with a white back button when set.
  final VoidCallback? onBack;

  /// Header height as a fraction of the screen — raised automatically if the
  /// content would not fit.
  final double headerFactor;

  /// Diameter of the white circle holding the app icon.
  final double badgeSize;

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell>
    with SingleTickerProviderStateMixin {
  static const _headerMs = 300;
  static const _startMs = 150;
  static const _stepMs = 100;
  static const _itemMs = 400;

  late final AnimationController _controller;
  bool _started = false;

  int get _totalMs => _startMs + _stepMs * (widget.fields.length + 1) + _itemMs;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _totalMs),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _interval(
    int startMs,
    int durationMs, [
    Curve curve = Curves.easeOut,
  ]) {
    final begin = startMs / _totalMs;
    final end = math.min(1.0, (startMs + durationMs) / _totalMs);
    return CurveTween(
      curve: Interval(begin, end, curve: curve),
    ).animate(_controller);
  }

  Widget _slideFade(int index, Widget child) {
    final start = _startMs + _stepMs * index;
    return FadeTransition(
      opacity: _interval(start, _itemMs),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(_interval(start, _itemMs, Curves.easeOutCubic)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      SmartBrandTheme(child: Builder(builder: _buildBranded));

  Widget _buildBranded(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final hasBack = widget.onBack != null;
    final topInset = padding.top + (hasBack ? kToolbarHeight : 20);
    // Short screens (360×640) get a smaller badge so the form stays close.
    final compact = size.height < 700;
    final badge = compact ? widget.badgeSize * 0.75 : widget.badgeSize;

    final actionStart = _startMs + _stepMs * widget.fields.length;
    final actionScale = Tween<double>(
      begin: 0.9,
      end: 1,
    ).animate(_interval(actionStart, _itemMs, Curves.easeOutCubic));
    // The card rides up over the bottom of the blue band.
    const overlap = 40.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status-bar icons over the blue band, in both modes.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        extendBodyBehindAppBar: true,
        appBar: hasBack
            ? AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                systemOverlayStyle: SystemUiOverlayStyle.light,
                // The theme's app-bar icon colour would win over
                // foregroundColor and fade the arrow on the blue band.
                iconTheme: const IconThemeData(color: Colors.white),
                leading: IconButton(
                  icon: const BackButtonIcon(),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: widget.onBack,
                ),
              )
            : null,
        body: SingleChildScrollView(
          // Clamping: the stretch overscroll throws "Build scheduled during
          // frame" when the keyboard resizes the viewport mid-drag.
          physics: const ClampingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: 24 + padding.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BrandBand(
                padding: EdgeInsets.fromLTRB(
                  24,
                  topInset,
                  24,
                  overlap + (compact ? 16 : 28),
                ),
                child: FadeTransition(
                  opacity: _interval(0, _headerMs),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1).animate(
                      _interval(0, _headerMs + 200, Curves.easeOutBack),
                    ),
                    child: _Header(
                      title: widget.title,
                      subtitle: widget.subtitle,
                      badgeSize: badge,
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -overlap),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          BrandCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < widget.fields.length; i++)
                                  _slideFade(
                                    i,
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: widget.fields[i],
                                    ),
                                  ),
                                const SizedBox(height: AppSpacing.xs),
                                FadeTransition(
                                  opacity: _interval(actionStart, _itemMs),
                                  child: ScaleTransition(
                                    scale: actionScale,
                                    child: widget.action,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.footer != null) ...[
                            const SizedBox(height: AppSpacing.base),
                            FadeTransition(
                              opacity: _interval(actionStart, _itemMs),
                              child: widget.footer,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The blue band behind the header: brand gradient, rounded bottom corners
/// and two soft circles (one gold) for depth.
class _BrandBand extends StatelessWidget {
  const _BrandBand({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [AppColors.smartBlue, Color(0xFF1B2FB0)],
          ),
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -60,
              end: -50,
              child: _Blob(size: 180, color: Colors.white, alpha: 0.08),
            ),
            // Low on the far side and small, so it never meets the text.
            PositionedDirectional(
              bottom: 52,
              end: -22,
              child: _Blob(size: 56, color: AppColors.smartGold, alpha: 0.9),
            ),
            PositionedDirectional(
              top: 96,
              start: 28,
              child: _Blob(size: 10, color: AppColors.smartGold, alpha: 0.9),
            ),
            // Full width: a loose Stack child would shrink to its content
            // and sit at the start edge instead of the centre.
            SizedBox(
              width: double.infinity,
              child: Padding(padding: padding, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color, required this.alpha});

  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: alpha),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.badgeSize,
  });

  final String title;
  final String subtitle;
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        // The app icon on a white rounded tile with a gold corner dot.
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: badgeSize,
              height: badgeSize,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(badgeSize * 0.3),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.smartNavy.withValues(alpha: 0.25),
                    blurRadius: 24,
                    spreadRadius: -6,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(badgeSize * 0.24),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.school_rounded,
                    size: badgeSize * 0.53,
                    color: AppColors.smartBlue,
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              top: -4,
              end: -4,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.smartGold,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          title,
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

/// Brand-gradient primary button (56 high, 16 radius) used by the auth
/// screens in place of the flat [AppButton.primary].
class AuthGradientButton extends StatelessWidget {
  const AuthGradientButton(
    this.text, {
    super.key,
    required this.onPressed,
    this.loading = false,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) => GradientButton(
    label: text,
    onPressed: withTapSound(onPressed),
    loading: loading,
  );
}

/// Divider plus a "prompt  link" row, e.g. "مفيش حساب؟ سجل حساب جديد".
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Divider(color: palette.divider, thickness: 1),
        const SizedBox(height: AppSpacing.sm),
        // Wraps instead of overflowing on narrow screens / large text.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              prompt,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(foregroundColor: palette.primary),
              child: Text(
                action,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Brand-gradient block with the same wave bottom edge as [AuthShell]'s
/// header, for the home and account tabs. The wave shaves up to ~40px off the
/// bottom, so keep [child] clear of that. An optional [imageUrl] (e.g. the
/// center's cover) is shown underneath a translucent brand tint.
class GradientWaveHeader extends StatelessWidget {
  const GradientWaveHeader({
    super.key,
    required this.child,
    this.height,
    this.imageUrl,
  });

  final Widget child;
  final double? height;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final isDark = context.palette.isDark;
    final colors = isDark
        ? [
            Theme.of(context).colorScheme.primaryContainer,
            context.palette.primary,
          ]
        : [context.palette.primary, Theme.of(context).colorScheme.secondary];
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return ClipPath(
      clipper: const AuthWaveClipper(),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (hasImage)
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: imageUrl!,
                  memCacheWidth: 360,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const SizedBox.shrink(),
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: hasImage
                        ? [for (final c in colors) c.withValues(alpha: 0.88)]
                        : colors,
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
