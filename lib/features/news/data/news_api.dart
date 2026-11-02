import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/features/news/domain/news_post.dart';

/// The channel is off for this student (403) or the server doesn't have it
/// (404): the whole feature hides itself.
class NewsUnavailable implements Exception {
  const NewsUnavailable();
}

/// `/news*`. Every call throws [NewsUnavailable] on 403/404 and rethrows
/// anything else (network, 5xx, 422).
class NewsApi {
  NewsApi(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) throw const NewsUnavailable();
      rethrow;
    }
  }

  Future<NewsPage> page(int page) => _guard(() async {
    final r = await _dio.get<Object?>(
      ApiEndpoints.news,
      queryParameters: {'page': page},
    );
    return NewsPage.fromJson(r.data);
  });

  /// `{count}`; 0 for anything unexpected (the server answers 0 when off).
  Future<int> unreadCount() => _guard(() async {
    final r = await _dio.get<Object?>(ApiEndpoints.newsUnreadCount);
    final data = r.data;
    final count = data is Map ? data['count'] : null;
    return count is num && count > 0 ? count.toInt() : 0;
  });

  Future<void> markSeen() => _guard(() async {
    await _dio.post<Object?>(ApiEndpoints.newsSeen);
  });

  /// The new `views_count`, or `null` when the answer had none.
  Future<int?> view(int id) => _guard(() async {
    final r = await _dio.post<Object?>(ApiEndpoints.newsView(id));
    final data = r.data;
    final n = data is Map ? data['views_count'] : null;
    return n is num ? n.toInt() : null;
  });

  /// Sets ([reaction]) or clears (`null`) the student's reaction; returns the
  /// server's `{reactions, my_reaction}`.
  Future<(Map<String, int>, String?)> react(int id, String? reaction) =>
      _guard(() async {
        final r = await _dio.post<Object?>(
          ApiEndpoints.newsReact(id),
          data: {'reaction': reaction},
        );
        final data = r.data is Map ? r.data as Map : const {};
        final mine = data['my_reaction'];
        return (
          reactionsFromJson(data['reactions']),
          mine is String ? mine : null,
        );
      });
}

final newsApiProvider = Provider<NewsApi>(
  (ref) => NewsApi(ref.watch(dioClientProvider)),
);
