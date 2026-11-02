import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/features/live/data/live_api.dart';
import 'package:itaaleem/features/live/presentation/live_providers.dart';
import 'package:itaaleem/features/live/presentation/live_routes.dart';

/// Home "بث مباشر" card, above the subjects. Nothing at all unless the
/// switch is on and `GET /live-sessions` returned a non-empty list.
class LiveHomeCard extends ConsumerWidget {
  const LiveHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(liveSessionsProvider).valueOrNull;
    if (sessions == null || sessions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final session = sessions.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sectionSpacing,
        AppSpacing.screenHorizontal,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'بث مباشر',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push(liveSessionsPath),
                child: const Text(
                  'كل البثوث',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                ),
              ),
            ],
          ),
          LiveSessionTile(session: session, prominent: session.isLive),
        ],
      ),
    );
  }
}

/// One session row — prominent (pulsing "🔴 مباشر الآن") when live,
/// otherwise its start time in device time.
class LiveSessionTile extends StatelessWidget {
  const LiveSessionTile({
    super.key,
    required this.session,
    this.prominent = false,
  });

  final LiveSession session;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = session.isLive;
    final bg = live && prominent
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final fg = live && prominent ? scheme.onErrorContainer : scheme.onSurface;
    final subtitle = [
      if (session.subjectName != null) session.subjectName!,
      if (!live) formatLiveWhen(session.startsAt),
    ].where((s) => s.isNotEmpty).join(' • ');
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            context.push(liveSessionPath(session.id), extra: session.subjectId),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              if (live)
                const _PulsingDot()
              else
                Icon(Icons.event_rounded, color: scheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (live)
                      Text(
                        '🔴 مباشر الآن',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.error,
                        ),
                      ),
                    Text(
                      session.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: fg.withValues(alpha: 0.75),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return SizedBox(
      width: 28,
      height: 28,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 14 + 14 * _controller.value,
              height: 14 + 14 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.35 * (1 - _controller.value)),
              ),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
