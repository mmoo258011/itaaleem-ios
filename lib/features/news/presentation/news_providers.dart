import 'dart:async';
import 'package:itaaleem/core/services/fcm_service.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/news/data/news_api.dart';
import 'package:itaaleem/features/news/domain/news_post.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The signed-in student's id (cache key), or `null` for a guest.
final newsSignedInProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider).valueOrNull?.id.toString(),
);

/// Set when an endpoint answered 403/404 — the channel hides itself until
/// the config changes (e.g. the center turns it back on).
final newsDisabledProvider = StateProvider<bool>((ref) {
  ref.watch(currentAppConfigProvider);
  ref.watch(newsSignedInProvider);
  return false;
});

/// Whether the home card, menu entry and screen exist at all:
/// `features.news_channel == true`, signed in, and no 403/404 so far.
final newsAvailableProvider = Provider<bool>((ref) {
  if (ref.watch(newsSignedInProvider) == null) return false;
  final config = ref.watch(currentAppConfigProvider);
  if (configFeature(config, 'news_channel') != true) return false;
  return !ref.watch(newsDisabledProvider);
});

/// Red-dot count on the home card. 0 when hidden or on any failure.
final newsUnreadProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(newsAvailableProvider)) return 0;
  // Fresh on resume and when a news push lands while the app is open.
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  final pushes = FcmService.foregroundTypes
      .where((t) => t == 'news')
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(() {
    lifecycle.dispose();
    pushes.cancel();
  });
  try {
    return await ref.read(newsApiProvider).unreadCount();
  } on NewsUnavailable {
    ref.read(newsDisabledProvider.notifier).state = true;
    return 0;
  } catch (_) {
    return 0;
  }
});

class NewsFeed {
  const NewsFeed({
    required this.posts,
    required this.page,
    required this.lastPage,
    required this.reactionsAvailable,
    this.loadingMore = false,
    this.fromCache = false,
  });

  final List<NewsPost> posts;
  final int page;
  final int lastPage;
  final List<String> reactionsAvailable;
  final bool loadingMore;

  /// Still showing the stored copy; a fresh one is on its way.
  final bool fromCache;

  bool get hasMore => page < lastPage;

  NewsFeed copyWith({
    List<NewsPost>? posts,
    int? page,
    int? lastPage,
    bool? loadingMore,
  }) => NewsFeed(
    posts: posts ?? this.posts,
    page: page ?? this.page,
    lastPage: lastPage ?? this.lastPage,
    reactionsAvailable: reactionsAvailable,
    loadingMore: loadingMore ?? this.loadingMore,
    fromCache: fromCache,
  );

  static NewsFeed fromPage(NewsPage p, {bool fromCache = false}) => NewsFeed(
    posts: p.posts,
    page: p.currentPage,
    lastPage: p.lastPage,
    reactionsAvailable: p.reactionsAvailable,
    fromCache: fromCache,
  );
}

/// The channel: first page from the per-student cache at once (then fresh in
/// the background), infinite scroll, optimistic reactions, one view per post.
class NewsFeedController extends AsyncNotifier<NewsFeed> {
  final _viewed = <int>{};

  /// Latest react call per post — an older answer never overwrites a newer
  /// tap.
  final _reactSeq = <int, int>{};

  String? get _cacheKey {
    final id = ref.read(newsSignedInProvider);
    return id == null ? null : 'news_cache_v1_$id';
  }

  @override
  Future<NewsFeed> build() async {
    ref.watch(newsSignedInProvider);
    final cached = await _readCache();
    if (cached != null) {
      unawaited(refresh());
      return cached;
    }
    return _fetchFirst();
  }

  Future<NewsFeed> _fetchFirst() async {
    try {
      final page = await ref.read(newsApiProvider).page(1);
      unawaited(_writeCache(page));
      return NewsFeed.fromPage(page);
    } on NewsUnavailable {
      ref.read(newsDisabledProvider.notifier).state = true;
      unawaited(_clearCache());
      rethrow;
    }
  }

  /// Pull-to-refresh, and the background refresh after a cached start. On
  /// failure the current list stays (the cached copy beats an error).
  Future<void> refresh() async {
    try {
      final fresh = await _fetchFirst();
      _viewed.clear();
      state = AsyncData(fresh);
    } catch (e, st) {
      if (!state.hasValue || e is NewsUnavailable) state = AsyncError(e, st);
    }
  }

  Future<void> loadMore() async {
    final feed = state.valueOrNull;
    if (feed == null || feed.loadingMore || !feed.hasMore) return;
    state = AsyncData(feed.copyWith(loadingMore: true));
    try {
      final next = await ref.read(newsApiProvider).page(feed.page + 1);
      final seen = {for (final p in feed.posts) p.id};
      state = AsyncData(
        feed.copyWith(
          posts: [
            ...feed.posts,
            ...next.posts.where((p) => !seen.contains(p.id)),
          ],
          page: next.currentPage,
          lastPage: next.lastPage,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(feed.copyWith(loadingMore: false));
    }
  }

  /// `POST /news/seen` on opening the channel; the red dot goes away.
  Future<void> markSeen() async {
    try {
      await ref.read(newsApiProvider).markSeen();
    } catch (_) {}
    ref.invalidate(newsUnreadProvider);
  }

  /// Once per post per session, when it shows on screen.
  Future<void> markViewed(int id) async {
    if (!_viewed.add(id)) return;
    try {
      final count = await ref.read(newsApiProvider).view(id);
      if (count != null) _update(id, (p) => p.copyWith(viewsCount: count));
    } catch (_) {}
  }

  /// Picks [reaction] (tapping the current one clears it). Optimistic; rolls
  /// back if the server says no. Returns whether it stuck.
  Future<bool> react(int id, String reaction) async {
    final before = _post(id);
    if (before == null) return false;
    final next = before.myReaction == reaction ? null : reaction;
    final seq = (_reactSeq[id] ?? 0) + 1;
    _reactSeq[id] = seq;
    _update(id, (p) => p.withReaction(next));
    try {
      final (counts, mine) = await ref.read(newsApiProvider).react(id, next);
      if (_reactSeq[id] == seq) {
        _update(
          id,
          (p) => p.copyWith(
            reactions: counts.isEmpty ? null : counts,
            myReaction: () => mine,
          ),
        );
      }
      return true;
    } catch (_) {
      if (_reactSeq[id] == seq) _update(id, (_) => before);
      return false;
    }
  }

  NewsPost? _post(int id) {
    for (final p in state.valueOrNull?.posts ?? const <NewsPost>[]) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _update(int id, NewsPost Function(NewsPost) change) {
    final feed = state.valueOrNull;
    if (feed == null) return;
    state = AsyncData(
      feed.copyWith(
        posts: [for (final p in feed.posts) p.id == id ? change(p) : p],
      ),
    );
  }

  Future<NewsFeed?> _readCache() async {
    final key = _cacheKey;
    if (key == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      return NewsFeed.fromPage(
        NewsPage.fromJson(jsonDecode(raw)),
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(NewsPage page) async {
    final key = _cacheKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode({
          'posts': [for (final p in page.posts) p.toJson()],
          'pagination': {
            'current_page': page.currentPage,
            'last_page': page.lastPage,
          },
          'reactions_available': page.reactionsAvailable,
        }),
      );
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    final key = _cacheKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}

final newsFeedProvider = AsyncNotifierProvider<NewsFeedController, NewsFeed>(
  NewsFeedController.new,
);
