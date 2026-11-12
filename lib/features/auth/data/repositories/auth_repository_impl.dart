import 'dart:convert';

import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/storage/secure_storage_service.dart';
import 'package:itaaleem/core/utils/result.dart';
import 'package:itaaleem/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:itaaleem/features/auth/data/models/student_model.dart';
import 'package:itaaleem/features/auth/domain/entities/student.dart';
import 'package:itaaleem/features/auth/domain/repositories/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remoteDataSource, this._secureStorage);

  final AuthRemoteDataSource _remoteDataSource;
  final SecureStorageService _secureStorage;

  @override
  Future<Result<Student>> register({
    required String fullName,
    required String mobile,
    required String password,
    required String passwordConfirmation,
    String? email,
    int? courseId,
    Map<String, String> extras = const {},
  }) async {
    try {
      final response = await _remoteDataSource.register(
        fullName: fullName,
        mobile: mobile,
        password: password,
        passwordConfirmation: passwordConfirmation,
        email: email,
        courseId: courseId,
        extras: extras,
      );
      await _persistSession(response);
      return Ok(response.student);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<Student>> login({
    required String mobile,
    required String password,
    String? fcmToken,
  }) async {
    try {
      final response = await _remoteDataSource.login(
        mobile: mobile,
        password: password,
        fcmToken: fcmToken,
      );
      await _persistSession(response);
      return Ok(response.student);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<void>> logout() async {
    try {
      await _remoteDataSource.logout();
      await _clearSession();
      return const Ok(null);
    } on DioException catch (e) {
      // Even if the server call fails (e.g. token already expired), the
      // local session should still be cleared so the user isn't stuck.
      await _clearSession();
      return Err(_failureOf(e));
    } catch (_) {
      await _clearSession();
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Student?> restoreSession() async {
    String? token;
    try {
      token = await _secureStorage.readAuthToken();
    } catch (e) {
      // A read failure here (e.g. a transient keystore/keychain error) must
      // never be confused with "the user logged out" — it must NOT clear
      // anything. Fall back to whatever profile we last cached and let the
      // next launch retry the real read.
      if (kDebugMode) {
        debugPrint(
          '>>> restoreSession: token read threw ($e), keeping session, using cache',
        );
      }
      return _cachedStudent();
    }
    if (kDebugMode) {
      debugPrint(
        'Stored token found: ${token == null || token.isEmpty ? "no" : "yes"}',
      );
    }
    if (token == null || token.isEmpty) return null;

    try {
      final student = await _remoteDataSource.getProfile();
      await _secureStorage.writeStudentProfileJson(
        jsonEncode(student.toJson()),
      );
      if (kDebugMode) {
        debugPrint(
          '>>> restoreSession: GET /profile ok, staying logged in as ${student.id}',
        );
      }
      return student;
    } on DioException catch (e) {
      final failure = _failureOf(e);
      if (kDebugMode) {
        debugPrint(
          '>>> restoreSession: GET /profile failed (status '
          '${e.response?.statusCode}) -> ${failure.runtimeType}',
        );
      }
      if (failure is UnauthorizedFailure) {
        // Only a genuine 401 means the token itself was rejected — that's
        // the one case that should actually clear the session.
        await _clearSession();
        return null;
      }
      // Server unreachable, a 5xx hiccup, or anything else that isn't the
      // server explicitly rejecting the token — keep the session and fall
      // back to the last-known profile instead of forcing a logout.
      return _cachedStudent();
    } catch (e) {
      // Unexpected (e.g. a response-parsing bug) — not an auth rejection,
      // so don't wipe a perfectly valid token over it.
      if (kDebugMode) {
        debugPrint(
          '>>> restoreSession: GET /profile threw unexpectedly ($e), keeping session',
        );
      }
      return _cachedStudent();
    }
  }

  @override
  Future<Result<Student>> getProfile() async {
    try {
      final student = await _remoteDataSource.getProfile();
      await _secureStorage.writeStudentProfileJson(
        jsonEncode(student.toJson()),
      );
      return Ok(student);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<Student>> updateProfile({
    required String fullName,
    String? mobile,
    String? email,
    String? avatarFilePath,
  }) async {
    try {
      final student = await _remoteDataSource.updateProfile(
        fullName: fullName,
        mobile: mobile,
        email: email,
        avatarFilePath: avatarFilePath,
      );
      await _secureStorage.writeStudentProfileJson(
        jsonEncode(student.toJson()),
      );
      return Ok(student);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<void>> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirmation,
  }) async {
    try {
      await _remoteDataSource.updatePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
        newPasswordConfirmation: newPasswordConfirmation,
      );
      return const Ok(null);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (_) {
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Result<void>> deleteAccount() async {
    try {
      await _remoteDataSource.deleteAccount();
      try {
        await _clearSession();
      } catch (e) {
        // The account is already gone server-side — a local cleanup hiccup
        // must not surface as a failed deletion.
        if (kDebugMode) {
          debugPrint('>>> DELETE ACCOUNT local cleanup failed: $e');
        }
      }
      return const Ok(null);
    } on DioException catch (e) {
      return Err(_failureOf(e));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('>>> DELETE ACCOUNT unexpected error: $e');
      }
      return const Err(UnknownFailure('حدث خطأ ما، حاول مرة أخرى'));
    }
  }

  @override
  Future<Student?> cachedSession() async {
    try {
      final token = await _secureStorage.readAuthToken();
      if (token == null || token.isEmpty) return null;
    } catch (_) {
      // Fall through to whatever profile is cached.
    }
    return _cachedStudent();
  }

  Future<Student?> _cachedStudent() async {
    final profileJson = await _secureStorage.readStudentProfileJson();
    if (profileJson == null) return null;
    try {
      return StudentModel.fromJson(
        jsonDecode(profileJson) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistSession(AuthResponseModel response) async {
    await _secureStorage.writeAuthToken(response.token);
    await _secureStorage.writeSessionType('student');
    await _secureStorage.writeStudentProfileJson(
      jsonEncode(response.student.toJson()),
    );
    if (kDebugMode) {
      final readBack = await _secureStorage.readAuthToken();
      debugPrint(
        '>>> auth token persisted: read back matches written: '
        '${readBack == response.token}',
      );
    }
  }

  Future<void> _clearSession() async {
    await _secureStorage.deleteAuthToken();
    await _secureStorage.deleteStudentProfileJson();
  }

  Failure _failureOf(DioException e) {
    final error = e.error;
    if (error is Failure) return error;
    return const NetworkFailure('تعذر الاتصال بالسيرفر، تحقق من الإنترنت');
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final remoteDataSource = ref.watch(authRemoteDataSourceProvider);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return AuthRepositoryImpl(remoteDataSource, secureStorage);
});
