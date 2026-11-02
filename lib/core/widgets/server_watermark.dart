import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/content/content_policy.dart';
import 'package:itaaleem/core/theme/app_typography.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';

/// The watermark layer over protected content (video / PDF).
///
/// * No server config (`lesson.watermark`, then `center.watermark`) →
///   [legacy] exactly as before.
/// * Video: `on_video` (falls back to `enabled` on an older server) false →
///   nothing. PDF: `on_pdf` false → nothing.
/// * Otherwise → [ServerWatermark].
///
/// Always a positioned-fill sibling of the content: never takes touches and
/// is clipped to the content's bounds.
class ProtectedWatermark extends ConsumerWidget {
  const ProtectedWatermark({
    super.key,
    required this.lessonId,
    required this.legacy,
    this.isPdf = false,
    this.config,
  });

  /// A watermark object already in hand (e.g. `live_session.watermark`) —
  /// used instead of looking one up by [lessonId].
  final WatermarkConfig? config;

  /// The lesson/lecture (same id space) — `null` when unknown.
  final int? lessonId;

  /// The built-in watermark widgets, used when the server sends none.
  final List<Widget> legacy;
  final bool isPdf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config =
        this.config ?? ref.watch(effectiveWatermarkProvider(lessonId));
    if (config == null) {
      return Stack(
        fit: StackFit.expand,
        children: [for (final w in legacy) Positioned.fill(child: w)],
      );
    }
    if (isPdf ? !config.showOnPdf : !config.showOnVideo) {
      return const SizedBox.shrink();
    }
    var text = config.text;
    if (text.isEmpty) {
      final student = ref.watch(authControllerProvider).valueOrNull;
      text = [
        student?.fullName ?? '',
        student?.mobile ?? '',
      ].where((s) => s.isNotEmpty).join(' • ');
    }
    if (text.isEmpty) return const SizedBox.shrink();
    return ServerWatermark(config: config, text: text);
  }
}

/// Renders a [WatermarkConfig]: fixed in the center, hopping between the
/// corners, or drifting to a random spot every `move_interval`.
class ServerWatermark extends StatefulWidget {
  const ServerWatermark({super.key, required this.config, required this.text});

  final WatermarkConfig config;
  final String text;

  @override
  State<ServerWatermark> createState() => _ServerWatermarkState();
}

class _ServerWatermarkState extends State<ServerWatermark> {
  final _random = Random();
  Timer? _timer;
  int _corner = 0;

  /// 0–1 fractions of the free space (moving mode).
  double _fx = 0.5;
  double _fy = 0.5;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(ServerWatermark old) {
    super.didUpdateWidget(old);
    if (old.config.position != widget.config.position ||
        old.config.moveInterval != widget.config.moveInterval) {
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.config.position == WatermarkPosition.center) return;
    if (widget.config.position == WatermarkPosition.moving) {
      _fx = _random.nextDouble();
      _fy = _random.nextDouble();
    }
    _timer = Timer.periodic(widget.config.moveInterval, (_) {
      if (!mounted) return;
      setState(() {
        _corner = (_corner + 1) % 4;
        _fx = _random.nextDouble();
        _fy = _random.nextDouble();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final base = c.centerColor
        ? Theme.of(context).colorScheme.primary
        : (c.color ?? Colors.white);
    final color = base.withValues(alpha: c.opacity);
    final style = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: c.fontSize,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: color,
      shadows: [
        Shadow(
          color: (base.computeLuminance() > 0.5 ? Colors.black : Colors.white)
              .withValues(alpha: c.opacity * 0.6),
          offset: const Offset(1, 1),
        ),
      ],
    );
    final direction = Directionality.of(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, box) {
              const pad = 12.0;
              final painter = TextPainter(
                text: TextSpan(text: widget.text, style: style),
                textDirection: direction,
                maxLines: 2,
              )..layout(maxWidth: max(0, box.maxWidth - pad * 2));
              final w = painter.width;
              final h = painter.height;
              final freeX = max(0.0, box.maxWidth - w - pad * 2);
              final freeY = max(0.0, box.maxHeight - h - pad * 2);
              final label = SizedBox(
                width: w + 1,
                child: Text(
                  widget.text,
                  style: style,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                ),
              );
              final (double left, double top) = switch (c.position) {
                WatermarkPosition.center => (freeX / 2, freeY / 2),
                WatermarkPosition.corner => switch (_corner) {
                  0 => (0.0, 0.0),
                  1 => (freeX, 0.0),
                  2 => (freeX, freeY),
                  _ => (0.0, freeY),
                },
                WatermarkPosition.moving => (freeX * _fx, freeY * _fy),
              };
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: c.position == WatermarkPosition.center
                        ? Duration.zero
                        : const Duration(milliseconds: 1200),
                    curve: Curves.easeInOut,
                    left: pad + left,
                    top: pad + top,
                    child: label,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
