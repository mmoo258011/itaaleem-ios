import 'package:itaaleem/core/device/device_identity_service.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/services/screen_security_service.dart';
import 'package:itaaleem/features/auth/data/models/student_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Raw Dio calls against the auth endpoints. Login/register attach
/// `device_id`/`device_name`/`device_model`/`operating_system` from
/// [DeviceIdentityService], per APP_SPEC.md.
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._dio, this._deviceIdentityService);

  final Dio _dio;
  final DeviceIdentityService _deviceIdentityService;

  Future<AuthResponseModel> register({
    required String fullName,
    required String mobile,
    required String password,
    required String passwordConfirmation,
    String? email,
    int? courseId,
  }) async {
    final device = await _deviceIdentityService.getIdentity();
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.register,
      data: {
        // The live API expects `name`, not `full_name` (APP_SPEC.md's
        // original draft) — confirmed against the live backend.
        'name': fullName,
        // Empty on iOS email sign-up (the live server still requires
        // `mobile` — it then answers 422, handled by the screen).
        if (mobile.isNotEmpty) 'mobile': mobile,
        'password': password,
        'password_confirmation': passwordConfirmation,
        if (email != null && email.isNotEmpty) 'email': email,
        if (courseId != null) 'course_id': courseId,
        ...device.toJson(),
      },
    );
    return AuthResponseModel.fromJson(response.data ?? const {});
  }

  Future<AuthResponseModel> login({
    required String mobile,
    required String password,
    String? fcmToken,
  }) async {
    final device = await _deviceIdentityService.getIdentity();
    final body = {
      // The live API's login field is generically named `login` (it
      // accepts a mobile number or an email) rather than `mobile` — the
      // parameter here stays `mobile` since that's still the only login
      // method surfaced in the UI today.
      // [mobile] may be an email (iOS's combined field): `login` carries
      // either; `mobile` is always sent because the server marks it
      // required, and `email` is added when it is one.
      'mobile': mobile,
      'login': mobile,
      if (mobile.contains('@')) 'email': mobile,
      'password': password,
      ...device.toJson(),
      if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
    };
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.login,
        data: body,
      );
      if (kDebugMode) {
        debugPrint('>>> POST /login status ${response.statusCode}');
      }
      final parsed = AuthResponseModel.fromJson(response.data ?? const {});
      if (kDebugMode) {
        debugPrint('>>> POST /login ok (student id: ${parsed.student.id})');
      }
      return parsed;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('>>> POST /login threw: $e\n$stackTrace');
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    await _dio.post<void>(ApiEndpoints.logout);
  }

  Future<StudentModel> getProfile() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiEndpoints.profile);
    if (kDebugMode) {
      debugPrint(
        '>>> GET ${ApiEndpoints.profile} raw response: ${response.data}',
      );
    }
    ScreenSecurityService.updateShieldFlag(response.data, fromProfile: true);
    final student = StudentModel.fromEnvelope(response.data ?? const {});
    if (kDebugMode) {
      debugPrint('>>> FIXED: centerCover=${student.centerCover}');
    }
    if (kDebugMode) {
      debugPrint(
        '>>> GET ${ApiEndpoints.profile} parsed: centerId=${student.centerId} '
        'gradeId=${student.gradeId}',
      );
    }
    return student;
  }

  /// Laravel doesn't parse multipart bodies on a genuine PUT — a
  /// file-carrying update is sent as POST with Laravel's `_method`
  /// spoofing field instead; a text-only update uses a plain PUT.
  Future<StudentModel> updateProfile({
    required String fullName,
    String? mobile,
    String? email,
    String? avatarFilePath,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '>>> ${avatarFilePath == null ? "PUT" : "POST (PUT-spoofed)"} '
        '${ApiEndpoints.profile}: name="$fullName", mobile=$mobile, '
        'email=$email, avatar=${avatarFilePath ?? "(none)"} field="avatar"',
      );
    }
    final fields = {
      'name': fullName,
      if (mobile != null && mobile.isNotEmpty) 'mobile': mobile,
      if (email != null && email.isNotEmpty) 'email': email,
    };
    final response = avatarFilePath == null
        ? await _dio.put<Map<String, dynamic>>(
            ApiEndpoints.profile,
            data: fields,
          )
        : await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.profile,
            data: FormData.fromMap({
              '_method': 'PUT',
              ...fields,
              'avatar': await MultipartFile.fromFile(avatarFilePath),
            }),
          );
    if (kDebugMode) {
      debugPrint(
        '>>> ${ApiEndpoints.profile} response (${response.statusCode}): '
        '${response.data}',
      );
    }
    return StudentModel.fromEnvelope(response.data ?? const {});
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirmation,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.password,
      data: {
        'current_password': currentPassword,
        'password': newPassword,
        'password_confirmation': newPasswordConfirmation,
      },
    );
  }

  Future<void> deleteAccount() async {
    final response = await _dio.delete<dynamic>(ApiEndpoints.profile);
    if (kDebugMode) {
      debugPrint(
        '>>> DELETE ACCOUNT response: ${response.statusCode} ${response.data}',
      );
    }
  }
}

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  final dio = ref.watch(dioClientProvider);
  final deviceIdentityService = ref.watch(deviceIdentityServiceProvider);
  return AuthRemoteDataSource(dio, deviceIdentityService);
});
