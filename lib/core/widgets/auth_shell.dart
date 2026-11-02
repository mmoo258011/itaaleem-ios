import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itaaleem/core/design/design.dart';
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
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final hasBack = widget.onBack != null;
    final topInset = padding.top + (hasBack ? kToolbarHeight : 24);

    final actionStart = _startMs + _stepMs * widget.fields.length;
    final actionScale = Tween<double>(
      begin: 0.9,
      end: 1,
    ).animate(_interval(actionStart, _itemMs, Curves.easeOutCubic));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: scheme.surface,
        extendBodyBehindAppBar: true,
        appBar: hasBack
            ? AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: scheme.onSurface,
                leading: IconButton(
                  icon: const BackButtonIcon(),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: widget.onBack,
                ),
              )
            : null,
        body: AppBackground(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              // Clamping: the stretch overscroll throws "Build scheduled during frame"
              // when the keyboard resizes the viewport mid-drag.
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsetsDirectional.fromSTEB(
                20,
                topInset,
                20,
                24 + padding.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(
                    0,
                    constraints.maxHeight - topInset - 24 - padding.bottom,
                  ),
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FadeTransition(
                          opacity: _interval(0, _headerMs),
                          child: _Header(
                            title: widget.title,
                            subtitle: widget.subtitle,
                            badgeSize: widget.badgeSize,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        GlassCard(
                          blur: true,
                          radius: DesignTokens.radiusHero,
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < widget.fields.length; i++)
                                _slideFade(
                                  i,
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: widget.fields[i],
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.sm),
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
                          const SizedBox(height: AppSpacing.lg),
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
          ),
        ),
      ),
    );
  }
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        // Large app logo on a soft brand halo.
        Container(
          width: badgeSize + 16,
          height: badgeSize + 16,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: DesignTokens.brandGradient(scheme),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.35),
                blurRadius: 32,
                spreadRadius: -6,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipOval(
            child: ColoredBox(
              color: scheme.surface,
              child: Image.asset(
                'assets/icon/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.school_rounded,
                  size: badgeSize * 0.53,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          title,
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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
  Widget build(BuildContext context) =>
      GradientButton(label: text, onPressed: onPressed, loading: loading);
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              prompt,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: palette.textSecondary,
              ),
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
