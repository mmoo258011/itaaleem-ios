import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/features/app_config/app_config.dart'
    as app_config
    show mentionsPurchase;

/// One post of the news channel (`GET /news`). Parsing never throws: a field
/// with the wrong shape is dropped, a post without an id is skipped.
class NewsPost {
  const NewsPost({
    required this.id,
    required this.body,
    this.images = const [],
    this.link,
    this.video,
    this.isPinned = false,
    this.publishedAt,
    this.isNew = false,
    this.viewsCount = 0,
    this.reactions = const {},
    this.myReaction,
  });

  final int id;

  /// Plain text (never HTML); lines split by `\n`.
  final String body;
  final List<NewsImage> images;
  final NewsLink? link;
  final NewsVideo? video;
  final bool isPinned;
  final DateTime? publishedAt;
  final bool isNew;
  final int viewsCount;
  final Map<String, int> reactions;
  final String? myReaction;

  /// Body or link title mentions prices / subscribing / paying.
  bool get mentionsPurchase =>
      app_config.mentionsPurchase(body) ||
      app_config.mentionsPurchase(link?.title ?? '');

  static NewsPost? fromJson(Map json) {
    final id = _int(json['id']);
    if (id == null) return null;
    final rawImages = json['images'];
    final link = json['link'];
    final video = json['video'];
    return NewsPost(
      id: id,
      body: json['body'] is String ? json['body'] as String : '',
      images: [
        if (rawImages is List)
          for (final e in rawImages)
            if (e is Map) ?NewsImage.fromJson(e),
      ],
      link: link is Map ? NewsLink.fromJson(link) : null,
      video: video is Map ? NewsVideo.fromJson(video) : null,
      isPinned: json['is_pinned'] == true,
      publishedAt: json['published_at'] is String
          ? DateTime.tryParse(json['published_at'] as String)?.toLocal()
          : null,
      isNew: json['is_new'] == true,
      viewsCount: _int(json['views_count']) ?? 0,
      reactions: reactionsFromJson(json['reactions']),
      myReaction: json['my_reaction'] is String
          ? json['my_reaction'] as String
          : null,
    );
  }

  NewsPost copyWith({
    int? viewsCount,
    Map<String, int>? reactions,
    String? Function()? myReaction,
  }) => NewsPost(
    id: id,
    body: body,
    images: images,
    link: link,
    video: video,
    isPinned: isPinned,
    publishedAt: publishedAt,
    isNew: isNew,
    viewsCount: viewsCount ?? this.viewsCount,
    reactions: reactions ?? this.reactions,
    myReaction: myReaction != null ? myReaction() : this.myReaction,
  );

  /// The post with the student's reaction set to [next] (`null` = removed),
  /// counts adjusted locally — used for the optimistic update.
  NewsPost withReaction(String? next) {
    final counts = Map<String, int>.of(reactions);
    final prev = myReaction;
    if (prev != null) {
      counts[prev] = ((counts[prev] ?? 0) - 1).clamp(0, 1 << 30);
    }
    if (next != null) counts[next] = (counts[next] ?? 0) + 1;
    return copyWith(reactions: counts, myReaction: () => next);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'body': body,
    'images': [for (final i in images) i.toJson()],
    'link': link?.toJson(),
    'video': video?.toJson(),
    'is_pinned': isPinned,
    'published_at': publishedAt?.toUtc().toIso8601String(),
    'is_new': isNew,
    'views_count': viewsCount,
    'reactions': reactions,
    'my_reaction': myReaction,
  };
}

class NewsImage {
  const NewsImage({
    required this.url,
    required this.thumbUrl,
    this.width,
    this.height,
  });

  final String url;
  final String thumbUrl;
  final int? width;
  final int? height;

  /// width / height, or 4:3 when unknown — keeps the space before loading.
  double get aspectRatio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 4 / 3;
    return w / h;
  }

  static NewsImage? fromJson(Map json) {
    final url = _https(json['url']);
    if (url == null) return null;
    return NewsImage(
      url: url,
      thumbUrl: _https(json['thumb_url']) ?? url,
      width: _int(json['width']),
      height: _int(json['height']),
    );
  }

  Map<String, Object?> toJson() => {
    'url': url,
    'thumb_url': thumbUrl,
    'width': width,
    'height': height,
  };
}

class NewsLink {
  const NewsLink({required this.url, this.title});

  final String url;
  final String? title;

  static NewsLink? fromJson(Map json) {
    final url = _https(json['url']);
    if (url == null) return null;
    final title = json['title'];
    return NewsLink(
      url: url,
      title: title is String && title.trim().isNotEmpty ? title.trim() : null,
    );
  }

  Map<String, Object?> toJson() => {'url': url, 'title': title};
}

class NewsVideo {
  const NewsVideo({
    required this.url,
    required this.youtubeId,
    this.thumbnailUrl,
  });

  final String url;
  final String youtubeId;
  final String? thumbnailUrl;

  static NewsVideo? fromJson(Map json) {
    final id = json['youtube_id'];
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id)) {
      return null;
    }
    return NewsVideo(
      url: _https(json['url']) ?? 'https://www.youtube.com/watch?v=$id',
      youtubeId: id,
      thumbnailUrl:
          _https(json['thumbnail_url']) ??
          'https://i.ytimg.com/vi/$id/hqdefault.jpg',
    );
  }

  Map<String, Object?> toJson() => {
    'url': url,
    'youtube_id': youtubeId,
    'thumbnail_url': thumbnailUrl,
  };
}

/// A page of `GET /news`.
class NewsPage {
  const NewsPage({
    required this.posts,
    required this.currentPage,
    required this.lastPage,
    required this.reactionsAvailable,
  });

  final List<NewsPost> posts;
  final int currentPage;
  final int lastPage;
  final List<String> reactionsAvailable;

  static const defaultReactions = ['👍', '❤️', '🎉', '👏', '😮'];

  /// [hidePurchase] (default: on iOS) drops posts whose body or link title
  /// mentions prices / subscribing / paying — App Store rule, a second layer
  /// next to the server's own filtering.
  factory NewsPage.fromJson(Object? raw, {bool? hidePurchase}) {
    final dropPurchase = hidePurchase ?? PlatformUtils.isIOS;
    final json = raw is Map ? raw : const {};
    final rawPosts = json['posts'];
    final pagination = json['pagination'];
    final p = pagination is Map ? pagination : const {};
    final available = json['reactions_available'];
    final current = _int(p['current_page']) ?? 1;
    return NewsPage(
      posts: [
        if (rawPosts is List)
          for (final e in rawPosts)
            if (e is Map) ?NewsPost.fromJson(e),
      ].where((p) => !dropPurchase || !p.mentionsPurchase).toList(),
      currentPage: current,
      lastPage: _int(p['last_page']) ?? current,
      reactionsAvailable: available is List
          ? [
              for (final r in available)
                if (r is String) r,
            ]
          : defaultReactions,
    );
  }
}

Map<String, int> reactionsFromJson(Object? raw) {
  final out = <String, int>{};
  if (raw is Map) {
    raw.forEach((k, v) {
      final n = _int(v);
      if (k is String && n != null) out[k] = n < 0 ? 0 : n;
    });
  }
  return out;
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _https(Object? v) {
  if (v is! String) return null;
  final uri = Uri.tryParse(v.trim());
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? v.trim()
      : null;
}
