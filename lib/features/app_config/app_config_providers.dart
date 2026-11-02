import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/features/app_config/app_config.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/settings/domain/entities/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cacheKey = 'app_config_cache_v1';

/// A `GET /app-config` answer: `body == null` means 304 (cached copy still
/// current).
typedef AppConfigResponse = ({Map<String, dynamic>? body, String? etag});

/// Fetches `GET /app-config`. Throws on any failure; a 404 (a server without
/// the endpoint) is reported as [AppConfigUnavailable].
///
/// The token is optional for this endpoint: sent when the student is logged
/// in (center keys), absent for a guest (public keys only).
class AppConfigRemoteDataSource {
  AppConfigRemoteDataSource(this._dio);

  final Dio _dio;

  Future<AppConfigResponse> fetch({String? etag}) async {
    try {
      final response = await _dio.get<Object?>(
        ApiEndpoints.appConfig,
        options: Options(
          headers: {'If-None-Match': ?etag},
          validateStatus: (code) =>
              code != null && (code == 304 || (code >= 200 && code < 300)),
        ),
      );
      final newEtag = response.headers.value('etag');
      if (response.statusCode == 304) return (body: null, etag: etag);
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('app-config: not a JSON object');
      }
      return (body: data, etag: newEtag);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const AppConfigUnavailable();
      rethrow;
    }
  }
}

class AppConfigUnavailable implements Exception {
  const AppConfigUnavailable();
}

final appConfigRemoteDataSourceProvider = Provider<AppConfigRemoteDataSource>(
  (ref) => AppConfigRemoteDataSource(ref.watch(dioClientProvider)),
);

/// The current [AppConfig]. Never errors: anything that goes wrong resolves
/// to [AppConfig.empty] (or the last good copy), so the app behaves exactly
/// like before the endpoint existed.
///
/// Fetched on open, on resume ([refreshIfStale]) and on pull-to-refresh
/// ([refresh] with `force`), each time reusing the stored copy while it is
/// younger than `cache_ttl`.
class AppConfigController extends AsyncNotifier<AppConfig> {
  bool _inFlight = false;

  @override
  Future<AppConfig> build() => _load(force: false);

  /// On resume: refetch once the cached copy is older than `cache_ttl` —
  /// always while in maintenance, so the screen lifts as soon as it ends.
  Future<void> refreshIfStale() =>
      refresh(force: state.valueOrNull?.maintenance?.enabled ?? false);

  /// After login, logout, joining a center or a grade change: the answer
  /// depends on who is asking, so it's fetched in full (no ETag). The stored
  /// copy stays until that succeeds — it's the only one offline.
  Future<void> reset() async {
    _skipEtag = true;
    _inFlight = false;
    await refresh();
  }

  bool _skipEtag = false;

  Future<void> refresh({bool force = true}) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final next = await _load(force: force);
      state = AsyncData(next);
    } finally {
      _inFlight = false;
    }
  }

  Future<AppConfig> _load({required bool force}) async {
    final isIOS = PlatformUtils.isIOS;
    SharedPreferences? prefs;
    Map<String, dynamic>? cachedBody;
    DateTime? cachedAt;
    String? cachedEtag;
    try {
      prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && decoded['body'] is Map) {
          cachedBody = Map<String, dynamic>.from(decoded['body'] as Map);
          cachedAt = DateTime.fromMillisecondsSinceEpoch(
            (decoded['at'] as num?)?.toInt() ?? 0,
          );
          cachedEtag = decoded['etag'] as String?;
        }
      }
    } catch (_) {}

    final cached = cachedBody == null
        ? null
        : AppConfig.fromJson(cachedBody, isIOS: isIOS);
    if (!force &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < cached.cacheTtl) {
      return cached;
    }

    try {
      final answer = await ref
          .read(appConfigRemoteDataSourceProvider)
          .fetch(etag: cachedBody == null || _skipEtag ? null : cachedEtag);
      _skipEtag = false;
      final body = answer.body ?? cachedBody;
      if (body == null) throw const FormatException('app-config: 304, no copy');
      try {
        await prefs?.setString(
          _cacheKey,
          jsonEncode({
            'at': DateTime.now().millisecondsSinceEpoch,
            'body': body,
            'etag': answer.etag,
          }),
        );
      } catch (_) {}
      return AppConfig.fromJson(body, isIOS: isIOS);
    } on AppConfigUnavailable {
      try {
        await prefs?.remove(_cacheKey);
      } catch (_) {}
      return AppConfig.empty;
    } catch (e) {
      if (kDebugMode) debugPrint('>>> app-config failed: $e');
      // Offline / 5xx / bad JSON: keep the last good copy, but never lock the
      // app into maintenance on a stale answer.
      if (cached == null) return AppConfig.empty;
      return AppConfig.fromJson({
        ...cachedBody!,
        'maintenance': null,
      }, isIOS: isIOS);
    }
  }
}

final appConfigProvider = AsyncNotifierProvider<AppConfigController, AppConfig>(
  AppConfigController.new,
);

/// The loaded config, or [AppConfig.empty] while loading.
final currentAppConfigProvider = Provider<AppConfig>(
  (ref) => ref.watch(appConfigProvider).valueOrNull ?? AppConfig.empty,
);

/// `features[key]`, accepting both `live` and `live_enabled` spellings.
bool? configFeature(AppConfig config, String key) =>
    config.feature(key) ??
    (key.endsWith('_enabled')
        ? config.feature(key.substring(0, key.length - '_enabled'.length))
        : config.feature('${key}_enabled'));

/// [base] (`/public/settings`) with every value `app-config` sent laid over
/// it. Keys `app-config` doesn't send keep the old value.
AppSettings applyAppConfig(AppSettings base, AppConfig config) {
  String? link(String key, String? old) => config.links[key] ?? old;
  String? text(String key, String? old) => config.texts[key] ?? old;
  bool flag(String key, bool old) => configFeature(config, key) ?? old;

  final maintenance = config.maintenance;
  return AppSettings(
    appName: text('app_name', base.appName),
    whatsappGroup: link('whatsapp_group', base.whatsappGroup),
    whatsappNumber:
        _waNumber(config.links['support_whatsapp']) ??
        text('whatsapp_number', base.whatsappNumber),
    facebookUrl: link('facebook', link('facebook_url', base.facebookUrl)),
    youtubeUrl: link('youtube', link('youtube_url', base.youtubeUrl)),
    telegramUrl: link('telegram_url', base.telegramUrl),
    websiteUrl: link('website', link('website_url', base.websiteUrl)),
    supportPhone:
        config.links['support_phone']?.replaceFirst('tel:', '') ??
        text('support_phone', base.supportPhone),
    supportEmail:
        config.links['support_email']?.replaceFirst('mailto:', '') ??
        text('support_email', base.supportEmail),
    aboutText: text('about_text', base.aboutText),
    maintenanceMode: maintenance?.enabled ?? base.maintenanceMode,
    maintenanceTitle: maintenance?.title ?? base.maintenanceTitle,
    maintenanceMessage: maintenance?.message ?? base.maintenanceMessage,
    aiEnabled: flag('ai_enabled', base.aiEnabled),
    sequentialMode: flag('sequential_mode', base.sequentialMode),
    rateAppEnabled: flag('rate_app', base.rateAppEnabled),
    rateAppUrl: link('rate_app_url', base.rateAppUrl),
    parentAccessEnabled: flag(
      'parent_access_enabled',
      base.parentAccessEnabled,
    ),
    termsEnabled: flag('terms_enabled', base.termsEnabled),
    liveEnabled: flag('live_enabled', base.liveEnabled),
  );
}

/// `texts[key]` from `app-config`, or [fallback] (also outside a
/// [ProviderScope], e.g. in widget tests).
String serverText(BuildContext context, String key, String fallback) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(currentAppConfigProvider).text(key, fallback);
  } catch (_) {
    return fallback;
  }
}

/// `https://wa.me/201000000099` → `201000000099`.
String? _waNumber(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || uri.host != 'wa.me') return null;
  final digits = uri.pathSegments.firstOrNull;
  return digits != null && RegExp(r'^[0-9]{8,15}$').hasMatch(digits)
      ? digits
      : null;
}

/// Pull-to-refresh / resume helpers that don't need a [Ref] type.
void refreshAppConfig(WidgetRef ref, {bool force = true}) {
  unawaited(ref.read(appConfigProvider.notifier).refresh(force: force));
}

/// `null` = still loading. Only a change between two loaded values counts —
/// the first load at launch must keep the stored copy (offline fallback).
bool sessionChanged(Object? prev, Object? next) =>
    prev != null && next != null && prev != next;

/// Kept alive by [App]: loads the config at launch and re-checks it whenever
/// the app comes back from the background.
final appConfigLifecycleProvider = Provider<void>((ref) {
  ref.listen(appConfigProvider, (_, _) {});
  // Who is asking changes the answer (guest → public keys only; student →
  // + their center): refetch from scratch on login/logout, joining a
  // center and moving to another grade.
  // Not on the first load at launch (loading → the stored session): that
  // would drop the copy the app needs offline.
  void reset() => unawaited(ref.read(appConfigProvider.notifier).reset());
  ref.listen(
    authControllerProvider.select(
      (s) => s.hasValue ? (s.valueOrNull?.id,) : null,
    ),
    (prev, next) {
      if (sessionChanged(prev, next)) reset();
    },
  );
  ref.listen(
    centerMembershipProvider.select(
      (s) =>
          s.hasValue ? (s.valueOrNull?.centerId, s.valueOrNull?.gradeId) : null,
    ),
    (prev, next) {
      if (sessionChanged(prev, next) && next!.$1 != null) reset();
    },
  );
  final listener = AppLifecycleListener(
    onResume: () => ref.read(appConfigProvider.notifier).refreshIfStale(),
  );
  ref.onDispose(listener.dispose);
});
