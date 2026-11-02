import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:itaaleem/features/news/presentation/news_providers.dart';
import 'package:itaaleem/features/news/presentation/news_routes.dart';

/// Home «📢 الأخبار» entry with the unread count. Nothing at all unless the
/// channel is available (see [newsAvailableProvider]).
class NewsHomeCard extends ConsumerWidget {
  const NewsHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(newsAvailableProvider)) return const SizedBox.shrink();
    final unread = ref.watch(newsUnreadProvider).valueOrNull ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final title = serverText(context, 'news_title', newsDefaultTitle);
    final radius = BorderRadius.circular(AppRadius.lg);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sectionSpacing,
        AppSpacing.screenHorizontal,
        0,
      ),
      child: Semantics(
        button: true,
        label: unread > 0 ? '$title، $unread جديد' : title,
        excludeSemantics: true,
        child: Material(
          color: scheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: () => context.push(newsPath),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Badge(
                    isLabelVisible: unread > 0,
                    backgroundColor: scheme.error,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: scheme.primary,
                      child: Icon(
                        Icons.campaign_rounded,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📢 $title',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          unread > 0
                              ? (unread == 1
                                    ? 'فيه خبر جديد'
                                    : 'فيه $unread أخبار جديدة')
                              : 'آخر أخبار السنتر وإعلاناته',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: unread > 0
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_left_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
