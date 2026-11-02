import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/design/shimmer_box.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/arabic_time.dart';
import 'package:itaaleem/core/widgets/app_empty_state.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:itaaleem/features/news/data/news_api.dart';
import 'package:itaaleem/features/news/domain/news_post.dart';
import 'package:itaaleem/features/news/presentation/news_providers.dart';
import 'package:itaaleem/features/news/presentation/news_routes.dart';
import 'package:itaaleem/features/news/presentation/widgets/news_post_card.dart';

/// One row of the channel list.
sealed class NewsRow {
  const NewsRow();
}

class NewsPostRow extends NewsRow {
  const NewsPostRow(this.post);
  final NewsPost post;
}

/// «اليوم» / «أمس» / «12 أكتوبر» above the first post of a day.
class NewsDayRow extends NewsRow {
  const NewsDayRow(this.label);
  final String label;
}

/// «جديد» above the first unseen post.
class NewsUnreadRow extends NewsRow {
  const NewsUnreadRow(this.count);
  final int count;
}

/// Pinned posts first (as the server orders them), then the rest with a day
/// header whenever the day changes and «جديد» before the first `is_new`.
List<NewsRow> buildNewsRows(List<NewsPost> posts, {DateTime? now}) {
  final rows = <NewsRow>[];
  final unread = posts.where((p) => p.isNew && !p.isPinned).length;
  var unreadShown = false;
  String? lastDay;
  for (final p in posts) {
    if (p.isPinned) {
      rows.add(NewsPostRow(p));
      continue;
    }
    if (p.isNew && !unreadShown) {
      rows.add(NewsUnreadRow(unread));
      unreadShown = true;
    }
    final at = p.publishedAt;
    if (at != null) {
      final day = arabicDayLabel(at, now: now);
      if (day != lastDay) {
        rows.add(NewsDayRow(day));
        lastDay = day;
      }
    }
    rows.add(NewsPostRow(p));
  }
  return rows;
}

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key, this.focusPostId});

  /// Opened from a `type=news` push: scroll to this post.
  final int? focusPostId;

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  final _scroll = ScrollController();
  final _postKeys = <int, GlobalKey>{};
  int? _highlight;
  bool _focused = false;
  Timer? _viewCheck;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Opening the channel = seen: the red dot goes away.
    Future.microtask(() => ref.read(newsFeedProvider.notifier).markSeen());
  }

  @override
  void dispose() {
    _viewCheck?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scroll.position;
    if (pos.extentAfter < 800) {
      ref.read(newsFeedProvider.notifier).loadMore();
    }
    _scheduleViewCheck();
  }

  void _scheduleViewCheck() {
    _viewCheck?.cancel();
    _viewCheck = Timer(const Duration(milliseconds: 350), _checkViews);
  }

  /// A post counts as viewed once at least half of it (or half the screen,
  /// for a tall one) has been on screen; the controller sends it once.
  void _checkViews() {
    if (!mounted) return;
    final viewport = context.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    final notifier = ref.read(newsFeedProvider.notifier);
    _postKeys.forEach((id, key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) return;
      final y = box.localToGlobal(Offset.zero).dy;
      final h = box.size.height;
      final visible = (y + h).clamp(top, bottom) - y.clamp(top, bottom);
      final need = (h / 2).clamp(0, viewport.size.height / 2);
      if (visible >= need && h > 0) notifier.markViewed(id);
    });
  }

  void _focusIfNeeded(List<NewsPost> posts) {
    final id = widget.focusPostId;
    if (_focused || id == null) return;
    _focused = true;
    final index = posts.indexWhere((p) => p.id == id);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The list is lazy: get near it first, then exactly onto it.
      if (_scroll.hasClients) {
        _scroll.jumpTo(
          (index * 320.0).clamp(0, _scroll.position.maxScrollExtent),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final ctx = _postKeys[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.1,
          duration: const Duration(milliseconds: 300),
        );
      }
      if (!mounted) return;
      setState(() => _highlight = id);
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (mounted) setState(() => _highlight = null);
    });
  }

  Future<void> _react(NewsPost post, String emoji) async {
    HapticFeedback.selectionClick();
    final ok = await ref.read(newsFeedProvider.notifier).react(post.id, emoji);
    if (!ok && mounted) {
      AppToast.showError(context, 'تعذر تسجيل التفاعل، حاول تاني');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final feed = ref.watch(newsFeedProvider);
    final title = serverText(context, 'news_title', newsDefaultTitle);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primary,
              child: Icon(
                Icons.campaign_rounded,
                color: scheme.onPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'قناة السنتر',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: feed.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const _NewsSkeleton(),
        error: (error, _) => error is NewsUnavailable
            ? const AppEmptyState(
                icon: Icons.campaign_outlined,
                title: 'القناة مش متاحة دلوقتي',
              )
            : AppErrorState(
                title: 'تعذر تحميل الأخبار',
                message: failureOf(error).message,
                retryLabel: 'حاول تاني',
                onRetry: () => ref.invalidate(newsFeedProvider),
              ),
        data: (data) {
          if (data.posts.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.read(newsFeedProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  AppEmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'لسه مفيش أخبار',
                    subtitle: 'أول ما السنتر ينشر خبر جديد هيظهر هنا',
                  ),
                ],
              ),
            );
          }
          _focusIfNeeded(data.posts);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scheduleViewCheck(),
          );
          final rows = buildNewsRows(data.posts);
          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(newsFeedProvider.notifier).refresh();
              refreshAppConfig(ref);
            },
            child: ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.md,
                AppSpacing.screenHorizontal,
                AppSpacing.xxl,
              ),
              itemCount: rows.length + (data.hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == rows.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  );
                }
                return switch (rows[i]) {
                  NewsDayRow(:final label) => _DayChip(label: label),
                  NewsUnreadRow(:final count) => _UnreadDivider(count: count),
                  NewsPostRow(:final post) => Padding(
                    key: _postKeys.putIfAbsent(post.id, GlobalKey.new),
                    padding: const EdgeInsets.only(bottom: AppSpacing.base),
                    child: NewsPostCard(
                      post: post,
                      highlighted: _highlight == post.id,
                      reactionsAvailable: data.reactionsAvailable,
                      onReact: (emoji) => _react(post, emoji),
                    ),
                  ),
                };
              },
            ),
          );
        },
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = Expanded(
      child: Container(
        height: 1.5,
        color: scheme.primary.withValues(alpha: 0.5),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          line,
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              count > 1 ? 'جديد ($count)' : 'جديد',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimary,
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

class _NewsSkeleton extends StatelessWidget {
  const _NewsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i.isEven) ...[
            const ShimmerBox(height: 180, radius: AppRadius.lg),
            const SizedBox(height: AppSpacing.sm),
          ],
          const ShimmerBox(height: 14, width: 260),
          const SizedBox(height: 8),
          const ShimmerBox(height: 14, width: 200),
          const SizedBox(height: 8),
          const ShimmerBox(height: 14, width: 120),
          const SizedBox(height: AppSpacing.sm),
          const Row(
            children: [
              ShimmerBox(height: 32, width: 52, radius: 16),
              SizedBox(width: 6),
              ShimmerBox(height: 32, width: 52, radius: 16),
              SizedBox(width: 6),
              ShimmerBox(height: 32, width: 52, radius: 16),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ],
    );
  }
}
