import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/features/notifications/data/models/app_notification_mapper.dart';
import 'package:itaaleem/features/notifications/domain/entities/app_notification.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One page of `GET /notifications`.
class NotificationsPage {
  const NotificationsPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  final List<AppNotification> items;
  final int page;
  final bool hasMore;
}

/// Raw Dio calls against `/notifications`. Errors propagate (Dio exceptions
/// are mapped to `Failure` by `failureOf`) — nothing is swallowed here.
class NotificationsRemoteDataSource {
  NotificationsRemoteDataSource(this._dio);

  final Dio _dio;

  static const perPage = 20;

  /// Accepts `{data: {items, meta}}`, `{data: [...], meta}` (Laravel
  /// paginator / resource collection), `{items, meta}` or a bare list.
  Future<NotificationsPage> getNotifications({int page = 1}) async {
    final response = await _dio.get<dynamic>(
      ApiEndpoints.notifications,
      queryParameters: {'page': page, 'per_page': perPage},
    );
    final body = response.data;
    if (kDebugMode) {
      debugPrint('>>> GET ${ApiEndpoints.notifications}?page=$page: $body');
    }

    Object? list;
    Object? meta;
    if (body is List) {
      list = body;
    } else if (body is Map) {
      final data = body['data'];
      if (data is List) {
        list = data;
        meta = body['meta'] ?? body;
      } else if (data is Map) {
        list = data['items'] ?? data['notifications'] ?? data['data'];
        meta = data['meta'] ?? data;
      } else {
        list = body['items'] ?? body['notifications'];
        meta = body['meta'] ?? body;
      }
    }

    final hidden = await _hidden();
    final items = (list is List ? list : const [])
        .whereType<Map>()
        .map((e) => appNotificationFromJson(Map<String, dynamic>.from(e)))
        .where((n) => !hidden.contains(n.id))
        .toList();

    final metaMap = meta is Map ? meta : const {};
    final current = _int(metaMap['current_page']) ?? page;
    final last = _int(metaMap['last_page']);
    final hasMore = last != null
        ? current < last
        : (metaMap['next_page_url'] != null || items.length >= perPage);
    return NotificationsPage(items: items, page: current, hasMore: hasMore);
  }

  /// `GET /notifications/unread-count` — tolerant of `{count}`,
  /// `{unread_count}` and either nested under `data`, or a bare number.
  Future<int> getUnreadCount() async {
    final response = await _dio.get<dynamic>(
      ApiEndpoints.notificationsUnreadCount,
    );
    final body = response.data;
    if (body is num) return body.toInt();
    if (body is! Map) return 0;
    final data = body['data'];
    final source = data is Map ? data : body;
    final raw = data is num
        ? data
        : (source['unread_count'] ?? source['count'] ?? source['unread']);
    return _int(raw) ?? 0;
  }

  Future<void> markAsRead(String id) async {
    await _dio.post<dynamic>(ApiEndpoints.notificationRead(id));
  }

  Future<void> markAllAsRead() async {
    try {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.notificationsReadAll,
      );
      if (kDebugMode) {
        debugPrint(
          '>>> POST ${ApiEndpoints.notificationsReadAll}: '
          '${response.statusCode} ${response.data}',
        );
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '>>> POST ${ApiEndpoints.notificationsReadAll} FAILED: '
          '${e.response?.statusCode} ${e.response?.data ?? e.message}',
        );
      }
      rethrow;
    }
  }

  /// The API has no per-notification delete for students: the item is
  /// marked read on the server and hidden on this device.
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getStringList(_hiddenKey) ?? const [];
    // Bounded: the oldest hidden ids drop off long after they left page 1.
    await prefs.setStringList(_hiddenKey, [
      ...hidden
          .where((h) => h != id)
          .toList()
          .reversed
          .take(499)
          .toList()
          .reversed,
      id,
    ]);
    try {
      await markAsRead(id);
    } catch (_) {}
  }

  static const _hiddenKey = 'notifications_hidden_v1';

  static Future<Set<String>> _hidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {...?prefs.getStringList(_hiddenKey)};
    } catch (_) {
      return const {};
    }
  }

  static int? _int(Object? raw) =>
      raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
}

final notificationsRemoteDataSourceProvider =
    Provider<NotificationsRemoteDataSource>((ref) {
      final dio = ref.watch(dioClientProvider);
      return NotificationsRemoteDataSource(dio);
    });
