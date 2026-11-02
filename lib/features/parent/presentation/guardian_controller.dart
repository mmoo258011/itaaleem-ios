import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/services/fcm_service.dart';
import 'package:itaaleem/core/storage/secure_storage_service.dart';
import 'package:itaaleem/features/parent/data/parent_api.dart';
import 'package:itaaleem/features/parent/data/parent_models.dart';

const guardianSessionType = 'guardian';

/// The guardian ("ولي الأمر") session — `null` when there is none. Kept
/// entirely apart from [AuthController]: its own token, its own client, its
/// own routes.
class GuardianController extends AsyncNotifier<Guardian?> {
  late final GuardianApi api = buildGuardianApi(
    ref,
    onUnauthorized: () => unawaited(forceLogout()),
  );

  SecureStorageService get _storage => ref.read(secureStorageServiceProvider);

  @override
  Future<Guardian?> build() async {
    try {
      if (await _storage.readSessionType() != guardianSessionType) return null;
      final token = await _storage.readGuardianToken();
      if (token == null || token.isEmpty) return null;
    } catch (_) {
      return null;
    }
    // App start: `GET /parent/me`. A 401 ends the session; anything else
    // (offline, 5xx) keeps the last-known profile.
    try {
      final guardian = await api.me();
      await _cache(guardian);
      _afterSignIn();
      return guardian;
    } on ParentApiException catch (e) {
      if (e.isUnauthorized) {
        await _storage.clearGuardianSession();
        return null;
      }
      final cached = await _cached();
      if (cached != null) _afterSignIn();
      return cached;
    }
  }

  Future<ParentApiException?> login({
    required String mobile,
    required String password,
  }) => _signIn(() => api.login(mobile: mobile, password: password));

  Future<ParentApiException?> register({
    required String mobile,
    required String parentCode,
    required String password,
    required String passwordConfirmation,
    String? name,
  }) => _signIn(
    () => api.register(
      mobile: mobile,
      parentCode: parentCode,
      password: password,
      passwordConfirmation: passwordConfirmation,
      name: name,
    ),
  );

  Future<ParentApiException?> _signIn(
    Future<GuardianAuthResult> Function() call,
  ) async {
    try {
      final result = await call();
      await _storage.writeGuardianToken(result.token);
      await _storage.writeSessionType(guardianSessionType);
      await _cache(result.guardian);
      state = AsyncData(result.guardian);
      _afterSignIn();
      return null;
    } on ParentApiException catch (e) {
      return e;
    }
  }

  /// `POST /parent/logout` (which also drops this device's push token
  /// server-side), then the local session.
  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {
      // The local session is cleared either way.
    }
    await forceLogout();
  }

  /// Clears the session locally — the server already rejected the token.
  Future<void> forceLogout() async {
    if (state.valueOrNull == null) return;
    await _storage.clearGuardianSession();
    await ref.read(fcmServiceProvider).deleteLocalToken();
    state = const AsyncData(null);
  }

  void updateChildren(List<ParentChild> children) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = Guardian(
      id: current.id,
      name: current.name,
      mobile: current.mobile,
      children: children,
    );
    state = AsyncData(next);
    unawaited(_cache(next));
  }

  void _afterSignIn() {
    final fcm = ref.read(fcmServiceProvider);
    // Once the router has switched to the guardian routes.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      unawaited(fcm.initGuardian());
      fcm.flushPendingNavigation();
    });
  }

  Future<void> _cache(Guardian guardian) async {
    try {
      await _storage.writeGuardianProfileJson(jsonEncode(guardian.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('>>> guardian cache write failed: $e');
    }
  }

  Future<Guardian?> _cached() async {
    try {
      final raw = await _storage.readGuardianProfileJson();
      if (raw == null) return null;
      return Guardian.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

final guardianControllerProvider =
    AsyncNotifierProvider<GuardianController, Guardian?>(
      GuardianController.new,
    );

/// `GET /parent/children` — the list screen; seeded from the session.
final guardianChildrenProvider = FutureProvider.autoDispose<List<ParentChild>>((
  ref,
) async {
  final controller = ref.read(guardianControllerProvider.notifier);
  final children = await controller.api.children();
  controller.updateChildren(children);
  return children;
});

/// `GET /parent/children/{id}`.
final guardianChildDetailsProvider = FutureProvider.autoDispose
    .family<ChildDetails, int>((ref, id) {
      return ref.read(guardianControllerProvider.notifier).api.child(id);
    });
