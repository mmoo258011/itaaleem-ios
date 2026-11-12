import 'dart:async';

import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/services/fcm_service.dart';
import 'package:itaaleem/core/services/notification_service.dart';
import 'package:itaaleem/core/storage/secure_storage_service.dart';
import 'package:itaaleem/core/utils/result.dart';
import 'package:itaaleem/features/auth/data/account_data_wiper.dart';
import 'package:itaaleem/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:itaaleem/features/auth/data/models/student_model.dart';
import 'package:itaaleem/features/auth/domain/entities/student.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_providers.dart';
import 'package:itaaleem/features/auth/presentation/providers/signed_in_before_provider.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/subjects/data/datasources/subjects_remote_data_source.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _demoModeKey = 'demo_mode';

/// "دخول تجريبي" — a fully local session that never touches the network:
/// no token, no `GET /me`, nothing persisted beyond the [_demoModeKey] flag
/// that lets a cold restart come back into the same demo session instead
/// of bouncing to `/login`.
const demoStudent = Student(
  id: -1,
  fullName: 'طالب تجريبي',
  mobile: '01000000000',
  status: 'active',
  isDemo: true,
);

/// Holds the current auth state as `AsyncValue<Student?>`:
/// - loading: still restoring the session on app start, or an
///   auth action (login/register/logout) is in flight.
/// - data(null): unauthenticated.
/// - data(Student): authenticated.
/// - error: the last auth action failed (state also carries the previous
///   Student via [AsyncValue.value] if any, per default AsyncNotifier
///   behavior).
///
/// [AppRouter] watches this provider to redirect unauthenticated users to
/// `/login`.
class AuthController extends AsyncNotifier<Student?> {
  /// The splash's minimum duration used to live here (a fixed delay before
  /// this resolved); it's now `appStartupProvider`'s job, running
  /// concurrently with the restore instead of in front of it.
  static const _restoreGracePeriod = Duration(milliseconds: 700);

  /// Bumped on every state change. A profile fetch that started before a
  /// newer change (e.g. the background revalidate, or a refresh from the
  /// join, landing after «كمّل بياناتك» was saved) must not write its older
  /// profile over it — that sent the student back to the completion screen.
  int _generation = 0;

  @override
  set state(AsyncValue<Student?> newState) {
    _generation++;
    super.state = newState;
  }

  @override
  Future<Student?> build() async {
    // Any real session (restored, logged in, registered) means this install
    // has had an account — a later logout lands on login, not register.
    listenSelf((_, next) {
      final student = next.valueOrNull;
      if (student != null && !student.isDemo) {
        ref.read(signedInBeforeProvider.notifier).mark();
      }
    });
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_demoModeKey) ?? false) return demoStudent;
    final repository = ref.watch(authRepositoryProvider);
    // Cached session → enter the app right away and revalidate
    // `GET /profile` in the background (stale-while-revalidate). The splash
    // never waits on the network when there's something to show.
    final cached = await repository.cachedSession();
    final restoreFuture = repository.restoreSession();
    if (cached != null) {
      final generation = _generation;
      unawaited(
        restoreFuture.then((fresh) {
          // Unless the session changed meanwhile (logout / another login,
          // or a newer profile already applied).
          if (state.valueOrNull?.id != cached.id) return;
          if (generation != _generation) return;
          // `null` = the token was rejected (401) and the session cleared.
          state = AsyncData(fresh);
        }, onError: (Object _) {}),
      );
      return cached;
    }
    // No cache (first sign-in on this install, or an old build's state):
    // wait for the restore, but enter as soon as a cache appears.
    return restoreFuture.timeout(
      _restoreGracePeriod,
      onTimeout: () async {
        final late = await repository.cachedSession();
        return late ?? restoreFuture;
      },
    );
  }

  Future<Failure?> register({
    required String fullName,
    required String mobile,
    required String password,
    required String passwordConfirmation,
    String? email,
    int? courseId,
    Map<String, String> extras = const {},
  }) async {
    state = const AsyncLoading<Student?>().copyWithPrevious(state);
    final useCase = ref.read(registerUseCaseProvider);
    final result = await useCase(
      fullName: fullName,
      mobile: mobile,
      password: password,
      passwordConfirmation: passwordConfirmation,
      email: email,
      courseId: courseId,
      extras: extras,
    );
    return _applyResult(result);
  }

  Future<Failure?> login({
    required String mobile,
    required String password,
  }) async {
    state = const AsyncLoading<Student?>().copyWithPrevious(state);
    final fcmToken = await ref.read(notificationServiceProvider).getToken();
    final useCase = ref.read(loginUseCaseProvider);
    final result = await useCase(
      mobile: mobile,
      password: password,
      fcmToken: fcmToken,
    );
    return _applyResult(result);
  }

  Future<void> logout() async {
    if (state.valueOrNull?.isDemo ?? false) {
      await _clearDemoMode();
      return;
    }
    state = const AsyncLoading<Student?>().copyWithPrevious(state);
    final fcm = ref.read(fcmServiceProvider);
    await fcm.unregisterFromServer();
    await fcm.deleteLocalToken();
    await ref.read(centerMembershipProvider.notifier).clearLocalCache();
    await SubjectsCache.clear();
    final useCase = ref.read(logoutUseCaseProvider);
    await useCase();
    await wipeAccountData(ref);
    // Regardless of server-side outcome, the repository always clears the
    // local session — reflect that as logged-out immediately.
    state = const AsyncData<Student?>(null);
  }

  /// Clears the session locally without calling `POST /logout` — the
  /// server already rejected the token (a 401 from any authenticated
  /// endpoint besides login/register/the startup restore, which handle
  /// their own 401 already — see `ErrorMappingInterceptor`), so retrying
  /// that same call would just 401 again. No-ops if already logged out or
  /// on a demo session (which never holds a real token).
  Future<void> forceLogout() async {
    if (state.valueOrNull == null) return;
    if (state.valueOrNull?.isDemo ?? false) return;
    final secureStorage = ref.read(secureStorageServiceProvider);
    await secureStorage.deleteAuthToken();
    await secureStorage.deleteStudentProfileJson();
    await SubjectsCache.clear();
    await ref.read(centerMembershipProvider.notifier).clearLocalCache();
    await ref.read(fcmServiceProvider).deleteLocalToken();
    await wipeAccountData(ref);
    state = const AsyncData<Student?>(null);
  }

  /// Clears the persisted demo flag (and whatever dummy center it joined,
  /// so a later real login or a fresh demo run doesn't inherit it) and
  /// drops back to unauthenticated — shared by [logout] and
  /// [deleteAccount], since a demo session has nothing real on a server to
  /// delete.
  Future<void> _clearDemoMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_demoModeKey, false);
    await ref.read(centerMembershipProvider.notifier).leave();
    state = const AsyncData<Student?>(null);
  }

  /// Re-fetches `GET /profile` and updates the shared session state — used
  /// after an action that changed something on the student's profile
  /// server-side without returning the updated [Student] itself (e.g.
  /// redeeming an activation code). A no-op on a demo session, which has no
  /// real profile to refresh.
  Future<void> refreshProfile() async {
    if (state.valueOrNull?.isDemo ?? false) return;
    final generation = _generation;
    final useCase = ref.read(getProfileUseCaseProvider);
    final result = await useCase();
    // Something newer was applied while this was in flight.
    if (generation != _generation) return;
    if (result case Ok<Student>(:final value)) {
      state = AsyncData<Student?>(value);
    }
  }

  /// `POST /profile/complete` answered 200 with the saved `user` and the new
  /// `profile_completion`: applied right away, so the router lets the
  /// student through without waiting for (or depending on) another
  /// `GET /profile`. The profile is then refreshed in the background.
  Future<void> applyProfileCompletion(Map<String, dynamic> body) async {
    final current = state.valueOrNull;
    if (current is StudentModel) {
      state = AsyncData<Student?>(mergeCompletionResponse(current, body));
    }
    await refreshProfile();
  }

  /// Updates the name/photo and, on success, refreshes the shared session
  /// state so every screen watching [authControllerProvider] (e.g. the
  /// account tab's header) reflects the change immediately.
  Future<Failure?> updateProfile({
    required String fullName,
    String? mobile,
    String? email,
    String? avatarFilePath,
  }) async {
    final useCase = ref.read(updateProfileUseCaseProvider);
    final result = await useCase(
      fullName: fullName,
      mobile: mobile,
      email: email,
      avatarFilePath: avatarFilePath,
    );
    return _applyResult(result);
  }

  Future<Failure?> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirmation,
  }) async {
    final useCase = ref.read(updatePasswordUseCaseProvider);
    final result = await useCase(
      currentPassword: currentPassword,
      newPassword: newPassword,
      newPasswordConfirmation: newPasswordConfirmation,
    );
    switch (result) {
      case Ok<void>():
        return null;
      case Err<void>(:final failure):
        return failure;
    }
  }

  /// Permanently deletes the account. On success, clears the auth state the
  /// same way [logout] does, which triggers [AppRouter] to redirect to
  /// `/login`. On failure, the caller shows the returned [Failure] and the
  /// session stays intact.
  ///
  /// In a demo session there's no real account to delete server-side — this
  /// just behaves like [logout].
  Future<Failure?> deleteAccount() async {
    if (state.valueOrNull?.isDemo ?? false) {
      await _clearDemoMode();
      return null;
    }
    state = const AsyncLoading<Student?>().copyWithPrevious(state);
    final useCase = ref.read(deleteAccountUseCaseProvider);
    final result = await useCase();
    switch (result) {
      case Ok<void>():
        try {
          await SubjectsCache.clear();
          await ref.read(centerMembershipProvider.notifier).clearLocalCache();
          await ref.read(fcmServiceProvider).deleteLocalToken();
          await wipeAccountData(ref);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('>>> DELETE ACCOUNT cache clear failed: $e');
          }
        }
        state = const AsyncData<Student?>(null);
        return null;
      case Err<void>(:final failure):
        state = AsyncData<Student?>(state.valueOrNull);
        return failure;
    }
  }

  Failure? _applyResult(Result<Student> result) {
    switch (result) {
      case Ok<Student>(:final value):
        state = AsyncData<Student?>(value);
        // `/login` and `/register` can return a slimmer `center` object than
        // `/profile` (no cover/logo) — pull the full profile.
        unawaited(refreshProfile());
        return null;
      case Err<Student>(:final failure):
        // Failed action: fall back to whatever auth state we had before
        // (still unauthenticated on a failed login, still authenticated on
        // a failed... well, register/login only reach here unauthenticated).
        state = AsyncData<Student?>(state.valueOrNull);
        return failure;
    }
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, Student?>(
  AuthController.new,
);

/// `authControllerProvider`'s `isDemo` flag alone, via `.select` — screens
/// that only care whether the session is a demo one should watch this
/// instead of the whole [Student], so they don't rebuild on every unrelated
/// profile field change (name, avatar, center/grade, ...).
final isDemoSessionProvider = Provider<bool>((ref) {
  return ref.watch(
    authControllerProvider.select(
      (state) => state.valueOrNull?.isDemo ?? false,
    ),
  );
});
