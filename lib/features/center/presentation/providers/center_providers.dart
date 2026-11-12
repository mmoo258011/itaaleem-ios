import 'dart:convert';
import 'dart:async';

import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/network/center_deactivated_events.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/center/data/datasources/centers_remote_data_source.dart';
import 'package:itaaleem/features/center/data/dummy/center_dummy_data.dart';
import 'package:itaaleem/features/center/data/models/center_json_mapper.dart';
import 'package:itaaleem/features/center/domain/entities/center_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/features/smart_ui/completion/complete_profile_screen.dart'
    show profileCompletionApiProvider;
import 'package:itaaleem/features/smart_ui/completion/signup_extras.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _centerIdKey = 'joined_center_id';
const _gradeIdKey = 'joined_grade_id';

/// Real (non-demo) session equivalent of the demo keys above — written the
/// moment `join()` below succeeds, independently of whatever `GET /profile`
/// returns, and read back in `build()` if `/profile`'s response doesn't
/// carry a center/grade for some reason (an unrecognized response shape, a
/// stale cache, …). A real session's *primary* source of truth is still
/// `Student.centerId`/`gradeId` from `/profile` — this is only the local
/// fallback for when that hasn't caught up yet.
const _realCenterIdKey = 'real_joined_center_id';
const _realGradeIdKey = 'real_joined_grade_id';

/// The center + grade a student has joined.
class CenterMembership {
  const CenterMembership({required this.centerId, this.gradeId});

  final int centerId;
  final int? gradeId;
}

/// Whether the logged-in student has joined a center yet.
///
/// A demo session ([Student.isDemo]) keeps the old local-only behavior
/// (persisted in [SharedPreferences], never touches the network) — a real
/// session derives its initial membership straight from
/// [authControllerProvider]'s [Student.centerId]/[Student.gradeId] (as
/// returned by `/login`, `/register` and `/profile`), and [join]/[leave]
/// call the real `/centers` endpoints, updating this controller's own state
/// directly on success rather than re-fetching the profile.
///
/// [AppRouter] redirects a logged-in student with no membership to
/// `/center-search` until this resolves to non-null.
class CenterMembershipController extends AsyncNotifier<CenterMembership?> {
  @override
  Future<CenterMembership?> build() async {
    // Only the fields the membership derives from — watching the whole
    // Student re-ran this build (prefs writes + an AsyncLoading flash for
    // everything watching membership) on every unrelated profile refresh.
    final (loggedIn, isDemo, profileCenterId, profileGradeId) = ref.watch(
      authControllerProvider.select((s) {
        final student = s.valueOrNull;
        return (
          student != null,
          student?.isDemo ?? false,
          student?.centerId,
          student?.gradeId,
        );
      }),
    );
    if (!loggedIn) return null;

    if (isDemo) {
      final prefs = await SharedPreferences.getInstance();
      final centerId = prefs.getInt(_centerIdKey);
      if (centerId == null) return null;
      return CenterMembership(
        centerId: centerId,
        gradeId: prefs.getInt(_gradeIdKey),
      );
    }

    if (profileCenterId == null) {
      // `join()` below sets this controller's state directly, straight
      // from the successful `/join` call, without waiting on a profile
      // refetch. If something later re-triggers this build (e.g. a
      // best-effort `GET /profile` after joining, fired to keep other
      // `Student.centerId` readers in sync) and that response hasn't
      // caught up with the join yet, trust the membership already held
      // here instead of bouncing the student back to the join-by-code
      // screen right after they just joined.
      if (state.valueOrNull != null) {
        if (kDebugMode) {
          debugPrint(
            '[CenterMembership] profile has no center/grade yet — keeping '
            'previously joined membership (centerId=${state.valueOrNull?.centerId}, '
            'gradeId=${state.valueOrNull?.gradeId})',
          );
        }
        return state.valueOrNull;
      }

      // No in-memory state either (e.g. a cold app restart, where this
      // notifier's build() runs for the first time) — fall back to the
      // locally persisted join before concluding the student really has no
      // center, since `/profile` not carrying a center/grade could just
      // mean the response shape wasn't what [StudentModel.fromJson] expects
      // rather than the student genuinely never having joined.
      final prefs = await SharedPreferences.getInstance();
      final cachedCenterId = prefs.getInt(_realCenterIdKey);
      if (kDebugMode) {
        debugPrint(
          '[CenterMembership] profile has no center/grade — cached local '
          'join: centerId=$cachedCenterId gradeId=${prefs.getInt(_realGradeIdKey)}',
        );
      }
      if (cachedCenterId == null) return null;
      return CenterMembership(
        centerId: cachedCenterId,
        gradeId: prefs.getInt(_realGradeIdKey),
      );
    }

    // `/profile` is the source of truth once it does carry a center — keep
    // the local cache in sync so it stays a faithful fallback.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_realCenterIdKey, profileCenterId);
    if (profileGradeId != null) {
      await prefs.setInt(_realGradeIdKey, profileGradeId);
    } else {
      await prefs.remove(_realGradeIdKey);
    }
    return CenterMembership(centerId: profileCenterId, gradeId: profileGradeId);
  }

  /// Joins (or, called again with a different grade, switches) a center.
  /// [centerId] is kept for local state/membership tracking, but the API
  /// itself resolves the center from [centerCode] — the live backend's
  /// `POST /centers/join` route has no id in the URL and expects `{code,
  /// grade_id?}`. [gradeId] is omitted for centers with no grades to choose
  /// from. Returns `failure: null` on success, or the [Failure] to show if
  /// the API call failed — the caller (e.g. select-grade screen) is
  /// responsible for surfacing it. On success [CenterJoinResult.request] set
  /// means the server kept the old grade and opened a grade-change request.
  Future<({Failure? failure, CenterJoinResult result})> join({
    required int centerId,
    required String centerCode,
    int? gradeId,
  }) async {
    final isDemo =
        ref.read(authControllerProvider).valueOrNull?.isDemo ?? false;
    if (isDemo) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_centerIdKey, centerId);
      if (gradeId != null) {
        await prefs.setInt(_gradeIdKey, gradeId);
      } else {
        await prefs.remove(_gradeIdKey);
      }
      state = AsyncData(CenterMembership(centerId: centerId, gradeId: gradeId));
      return (failure: null, result: const CenterJoinResult());
    }

    try {
      final result = await ref
          .read(centersRemoteDataSourceProvider)
          .joinCenter(code: centerCode, gradeId: gradeId);
      // Moved back to the old grade: [gradeId] was only requested.
      if (result.request != null) gradeId = result.request!.fromGrade?.id;
      // Persisted immediately, independently of `/profile` — this is what
      // `build()` falls back to on a cold restart if that response's shape
      // isn't recognized as carrying a center/grade.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_realCenterIdKey, centerId);
      if (gradeId != null) {
        await prefs.setInt(_realGradeIdKey, gradeId);
      } else {
        await prefs.remove(_realGradeIdKey);
      }
      state = AsyncData(CenterMembership(centerId: centerId, gradeId: gradeId));
      // The membership change above already reloads every cached content
      // provider (subjects, lessons, banners, teachers — see `ref.cached`);
      // the profile is refreshed too so a now-active subscription unlocks
      // lessons without restarting the app.
      // Sign-up details first (governorate…), so the refreshed profile
      // only asks «كمّل بياناتك» for what the server still lacks.
      unawaited(() async {
        await flushSignupExtras(ref.read(profileCompletionApiProvider));
        await ref.read(authControllerProvider.notifier).refreshProfile();
      }());
      return (failure: null, result: result);
    } on DioException catch (e) {
      return (failure: failureOf(e), result: const CenterJoinResult());
    }
  }

  /// Clears the joined center — [AppRouter] reacts by bouncing the student
  /// back to `/center-search` since they no longer have a membership. Same
  /// as [AuthController.logout], the local membership is cleared regardless
  /// of whether the server call itself succeeds.
  Future<void> leave() async {
    final isDemo =
        ref.read(authControllerProvider).valueOrNull?.isDemo ?? false;
    if (isDemo) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_centerIdKey);
      await prefs.remove(_gradeIdKey);
      state = const AsyncData(null);
      return;
    }

    state = const AsyncData(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_realCenterIdKey);
    await prefs.remove(_realGradeIdKey);
    try {
      await ref.read(centersRemoteDataSourceProvider).leaveCenter();
    } on DioException {
      // Already cleared locally above — nothing further to do.
    }
  }

  /// Clears only the local real-session join cache, without calling `POST
  /// /centers/leave` — the student isn't actually leaving the center, just
  /// logging out. Called from [AuthController.logout]/`forceLogout` so a
  /// different student who later logs in on the same device doesn't
  /// briefly inherit this cache before their own `/profile` resolves.
  Future<void> clearLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_realCenterIdKey);
    await prefs.remove(_realGradeIdKey);
  }
}

final centerMembershipProvider =
    AsyncNotifierProvider<CenterMembershipController, CenterMembership?>(
      CenterMembershipController.new,
    );

/// In-memory cache of centers fetched via [centerByIdProvider], keyed by id
/// — lets that provider stay a plain synchronous `CenterModel?` (matching
/// what every screen that reads it already expects) while still being fed
/// by a real, async `GET /centers/{id}` behind the scenes.
class _CenterCache extends Notifier<Map<int, CenterModel>> {
  @override
  Map<int, CenterModel> build() => {};

  void put(int id, CenterModel center) {
    state = {...state, id: center};
  }

  bool has(int id) => state.containsKey(id);

  void remove(int id) {
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
  }
}

final _centerCacheProvider =
    NotifierProvider<_CenterCache, Map<int, CenterModel>>(_CenterCache.new);

/// The last good copy (from disk, or the one a pull-to-refresh replaces),
/// shown by [centerByIdProvider] while a fetch runs or after it failed.
final _centerStaleProvider =
    NotifierProvider<_CenterCache, Map<int, CenterModel>>(_CenterCache.new);

/// Waits between `GET /centers/{id}` attempts before giving up; a provider
/// so tests can shorten them.
final centerRetryDelaysProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ],
);

String _centerPrefsKey(int id) => 'center_json_v1_$id';

/// `ref.read` of a [Ref] or a [WidgetRef].
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Tracks the last error for a [centerByIdProvider] fetch that's currently
/// failed, keyed by center id — lets dependent screens show a "تعذر
/// التحميل" + retry state instead of [centerByIdProvider] returning `null`
/// forever (which every call site otherwise reads as "still loading").
class _CenterFetchErrors extends Notifier<Map<int, Object>> {
  @override
  Map<int, Object> build() => {};

  void setError(int id, Object error) => state = {...state, id: error};

  void clear(int id) {
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
  }

  void clearAll() {
    if (state.isNotEmpty) state = {};
  }
}

final _centerFetchErrorsProvider =
    NotifierProvider<_CenterFetchErrors, Map<int, Object>>(
      _CenterFetchErrors.new,
    );

/// Non-null once [centerByIdProvider]'s `GET /centers/{id}` fetch for this
/// id has failed — screens use this (instead of an indefinite spinner) to
/// show an error state with a retry button wired to [retryCenterFetch].
final centerFetchErrorProvider = Provider.family<Object?, int>((ref, id) {
  return ref.watch(_centerFetchErrorsProvider.select((errors) => errors[id]));
});

/// Clears a fetch failure recorded by [centerFetchErrorProvider] so the next
/// read of [centerByIdProvider] fires the request again.
void retryCenterFetch(WidgetRef ref, int id) {
  ref.read(_centerFetchErrorsProvider.notifier).clear(id);
}

/// Every failed center fetch goes again — on reconnect and on resume.
void retryFailedCenters(ProviderReader read) {
  read(_centerFetchErrorsProvider.notifier).clearAll();
}

/// Pull-to-refresh: fetches `GET /centers/{id}` again, showing the current
/// copy until the new one arrives.
void refreshCenter(WidgetRef ref, int id) => refreshCenterWith(ref.read, id);

void refreshCenterWith(ProviderReader read, int id) {
  final current = read(_centerCacheProvider)[id];
  if (current != null) read(_centerStaleProvider.notifier).put(id, current);
  read(_centerFetchErrorsProvider.notifier).clear(id);
  read(_centerCacheProvider.notifier).remove(id);
}

/// Sticky gate [AppRouter] redirects on: `true` once either (a) a 403 from
/// any endpoint has been flagged by [ErrorMappingInterceptor] as meaning the
/// joined center was deactivated server-side, or (b) the joined center's own
/// `GET /centers/{id}` fetch resolved with `is_active: false`. Re-derives
/// from (b) on every rebuild (e.g. after leaving/rejoining a different
/// center), so only (a)'s one-shot event needs sticky `state =` handling.
class CenterDeactivatedController extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(centerDeactivatedStreamProvider, (previous, next) {
      if (next.hasValue) state = true;
    });

    final membership = ref.watch(centerMembershipProvider).valueOrNull;
    if (membership == null) return false;
    final center = ref.watch(centerByIdProvider(membership.centerId));
    return center != null && !center.isActive;
  }
}

final centerDeactivatedProvider =
    NotifierProvider<CenterDeactivatedController, bool>(
      CenterDeactivatedController.new,
    );

/// Looks up a center by id — synchronously `null` while a demo lookup
/// misses, or while a real fetch is still in flight/hasn't been triggered
/// yet; every current call site already treats `null` as "show a loading
/// state" unless [centerFetchErrorProvider] for the same id is non-null, in
/// which case it's a failure, not a loading state.
final centerByIdProvider = Provider.family<CenterModel?, int>((ref, id) {
  final isDemo = ref.watch(isDemoSessionProvider);
  if (isDemo) {
    for (final center in centerDummyData) {
      if (center.id == id) return center;
    }
    return null;
  }

  // `select` so a cache write for another id doesn't rebuild this provider
  // (and re-fire its request).
  final cached = ref.watch(_centerCacheProvider.select((m) => m[id]));
  if (cached != null) return cached;

  final stale = ref.watch(_centerStaleProvider.select((m) => m[id]));

  // A previous run (all its retries) failed and hasn't been retried — don't
  // re-fire on every rebuild; [retryFailedCenters] / [retryCenterFetch] /
  // [refreshCenter] clear it. The last good copy shows meanwhile.
  final hasError = ref.watch(
    _centerFetchErrorsProvider.select((errors) => errors.containsKey(id)),
  );
  if (hasError) return stale;

  // Cache miss: fire the real fetch once and populate the cache when it
  // resolves, which re-runs this provider (it watches [_centerCacheProvider]
  // above) and returns the loaded center on the next read.
  // Rebuilds while the request is in flight must not fire a second one.
  final inFlight = ref.read(_centerFetchesInFlightProvider);
  if (!inFlight.add(id)) return stale;
  unawaited(
    _fetchCenter(
      id,
      remote: ref.read(centersRemoteDataSourceProvider),
      delays: ref.read(centerRetryDelaysProvider),
      cache: ref.read(_centerCacheProvider.notifier),
      stale: ref.read(_centerStaleProvider.notifier),
      errors: ref.read(_centerFetchErrorsProvider.notifier),
    ).whenComplete(() => inFlight.remove(id)),
  );
  return stale;
});

/// `GET /centers/{id}` with retries ([centerRetryDelaysProvider]); the disk
/// copy is loaded first so something shows offline.
Future<void> _fetchCenter(
  int id, {
  required CentersRemoteDataSource remote,
  required List<Duration> delays,
  required _CenterCache cache,
  required _CenterCache stale,
  required _CenterFetchErrors errors,
}) async {
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_centerPrefsKey(id));
    if (raw != null && !stale.has(id)) {
      stale.put(
        id,
        centerModelFromJson(jsonDecode(raw) as Map<String, dynamic>),
      );
    }
  } catch (_) {}

  for (var attempt = 0; ; attempt++) {
    try {
      final json = await remote
          .getCenterDetailsJson(id)
          .timeout(const Duration(seconds: 10));
      final center = centerModelFromJson(json);
      cache.put(id, center);
      try {
        await prefs?.setString(_centerPrefsKey(id), jsonEncode(json));
      } catch (_) {}
      return;
    } catch (error) {
      if (attempt >= delays.length) {
        if (kDebugMode) {
          debugPrint('[centerByIdProvider] GET /centers/$id failed: $error');
        }
        errors.setError(id, error);
        return;
      }
      await Future<void>.delayed(delays[attempt]);
    }
  }
}

/// Ids with a `GET /centers/{id}` currently running (see [centerByIdProvider]).
///
/// Owned by the [ProviderContainer] rather than a top-level variable, so it
/// starts empty with every container (app start, tests) instead of living for
/// the whole isolate. Deliberately a plain [Provider] holding a mutable set,
/// not a `StateProvider`: [centerByIdProvider] marks an id in flight while it
/// is building, and Riverpod forbids writing another provider's `state` at
/// that moment. Nothing watches this set, so mutating it needs no
/// notification.
final _centerFetchesInFlightProvider = Provider<Set<int>>((ref) => <int>{});

/// The center the student has joined, for display (name, logo, cover,
/// brand color). Prefers the fetched `GET /centers/{id}` record, but fills
/// any missing logo/cover — and stands in entirely while that fetch is
/// pending or failed — from the `center` object already delivered by
/// `GET /profile`.
final joinedCenterProvider = Provider<CenterModel?>((ref) {
  final membership = ref.watch(centerMembershipProvider).valueOrNull;
  // Rebuild only when the profile's center payload actually changes (compared
  // by content — every refresh parses a fresh map), not on every refresh.
  ref.watch(
    authControllerProvider.select(
      (s) => (s.valueOrNull?.isDemo, s.valueOrNull?.centerJson?.toString()),
    ),
  );
  final student = ref.read(authControllerProvider).valueOrNull;
  final fetched = membership == null
      ? null
      : ref.watch(centerByIdProvider(membership.centerId));

  CenterModel? fromProfile;
  final json = student?.centerJson;
  if (json != null && !(student?.isDemo ?? false)) {
    try {
      fromProfile = centerModelFromJson(json);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('>>> HOME profile center parse failed: $e');
      }
    }
  }

  if (fetched == null) {
    // Only trust the profile's center while it matches the joined one.
    if (membership != null &&
        fromProfile != null &&
        fromProfile.id != membership.centerId) {
      return null;
    }
    return fromProfile;
  }
  if (fromProfile == null || fromProfile.id != fetched.id) return fetched;
  return fetched.copyWith(
    logo: (fetched.logo == null || fetched.logo!.isEmpty)
        ? fromProfile.logo
        : null,
    cover: (fetched.cover == null || fetched.cover!.isEmpty)
        ? fromProfile.cover
        : null,
  );
});

const _contactCenterCacheKey = 'contact_center_cache';

/// What [ContactCenterScreen] shows: the center plus whether it came from
/// the last-good local copy because the network failed.
typedef ContactCenterInfo = ({CenterModel center, bool fromCache});

/// The student's own center for the "تواصل مع المركز" screen.
///
/// `GET /centers/{id}` 404s for any center but the student's own (and for
/// every id before joining), so this asks `GET /center/support-info` first
/// and only falls back to `/centers/{membership.centerId}`. Each request is
/// capped at 10s. Whatever succeeds is cached in [SharedPreferences]; if both
/// fail, the cached copy is returned with `fromCache: true`, and with no
/// cache the error propagates so the screen shows retry instead of loading
/// forever.
final contactCenterInfoProvider = FutureProvider.autoDispose<ContactCenterInfo>(
  (ref) async {
    if (ref.watch(isDemoSessionProvider)) {
      final membership = await ref.watch(centerMembershipProvider.future);
      final center = membership == null
          ? null
          : ref.read(centerByIdProvider(membership.centerId));
      if (center == null) throw StateError('no demo center');
      return (center: center, fromCache: false);
    }

    final remote = ref.read(centersRemoteDataSourceProvider);
    const timeout = Duration(seconds: 10);
    final prefs = await SharedPreferences.getInstance();
    Object? lastError;

    Future<ContactCenterInfo?> attempt(
      Future<Map<String, dynamic>> Function() fetch,
    ) async {
      try {
        final json = await fetch().timeout(timeout);
        final center = centerModelFromJson(json);
        if (center.name.isEmpty && center.phoneNumbers.isEmpty) return null;
        await prefs.setString(_contactCenterCacheKey, jsonEncode(json));
        return (center: center, fromCache: false);
      } catch (e) {
        lastError = e;
        if (kDebugMode) debugPrint('[contactCenterInfo] $e');
        return null;
      }
    }

    final fromSupport = await attempt(remote.getSupportInfoJson);
    if (fromSupport != null) return fromSupport;

    CenterMembership? membership;
    try {
      membership = await ref.read(centerMembershipProvider.future);
    } catch (_) {}
    if (membership != null) {
      final id = membership.centerId;
      final fromDetails = await attempt(() => remote.getCenterDetailsJson(id));
      if (fromDetails != null) return fromDetails;
    }

    final cached = prefs.getString(_contactCenterCacheKey);
    if (cached != null) {
      try {
        final json = jsonDecode(cached) as Map<String, dynamic>;
        return (center: centerModelFromJson(json), fromCache: true);
      } catch (_) {}
    }
    throw lastError ?? StateError('no center');
  },
);
