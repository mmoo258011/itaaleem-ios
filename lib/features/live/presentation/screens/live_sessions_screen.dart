import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/features/live/data/live_api.dart';
import 'package:itaaleem/features/live/presentation/live_providers.dart';
import 'package:itaaleem/features/live/presentation/widgets/live_home_card.dart';

/// "كل البثوث": live on top, upcoming below, pull to refresh.
class LiveSessionsScreen extends ConsumerWidget {
  const LiveSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(liveSessionsProvider);
    final sessions = async.valueOrNull ?? const <LiveSession>[];
    final live = sessions.where((s) => s.isLive).toList();
    final upcoming = sessions.where((s) => !s.isLive).toList();

    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.base,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text(
          'البث المباشر',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(liveSessionsProvider.future),
        child: async.isLoading && !async.hasValue
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                children: [
                  if (sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 120),
                      child: Column(
                        children: [
                          Icon(
                            Icons.live_tv_rounded,
                            size: 56,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'مفيش بث دلوقتي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (live.isNotEmpty) header('شغال دلوقتي'),
                  for (final s in live)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: LiveSessionTile(session: s, prominent: true),
                    ),
                  if (upcoming.isNotEmpty) header('البثوث الجاية'),
                  for (final s in upcoming)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: LiveSessionTile(session: s),
                    ),
                ],
              ),
      ),
    );
  }
}
