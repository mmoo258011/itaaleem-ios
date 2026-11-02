import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/features/auth/domain/entities/student.dart';

/// Maps the `user` JSON object (per APP_SPEC.md's `{success, message,
/// data}` envelope) onto the [Student] domain entity.
class StudentModel extends Student {
  const StudentModel({
    required super.id,
    required super.fullName,
    required super.mobile,
    required super.status,
    super.avatarUrl,
    super.email,
    super.centerId,
    super.centerJson,
    super.gradeId,
    super.subscriptionStatus,
    super.hasPaidAccess,
    super.role,
    super.mustChangePassword,
    super.parentCode,
  });

  factory StudentModel.fromJson(Map<String, dynamic> json) {
    final center = json['center'];
    final grade = json['grade'];
    // Same "which shape does the live API actually use" hedge as
    // center/grade above — try a bare root field first, then whatever the
    // nested center/grade objects might carry it as.
    final subscriptionStatus =
        (json['subscription_status'] ?? json['subscriptionStatus'])
            as String? ??
        (center is Map<String, dynamic>
            ? center['subscription_status'] as String?
            : null);
    // The live API has been observed returning the joined center/grade both
    // ways: nested objects (`center: {id, ...}`/`grade: {id, ...}`) and flat
    // scalar columns straight off the `users` row (`center_id`/`grade_id`) —
    // the latter is what `CenterMembershipController.join`'s backend
    // actually writes (`$user->forceFill(['center_id' => ..., 'grade_id' =>
    // ...])`), so a plain `toArray()`/`toJson()` on that model would emit
    // flat columns unless the relations are explicitly loaded and appended.
    // Try the nested shape first, then fall back to the flat one.
    final nestedCenterId = center is Map<String, dynamic>
        ? int.tryParse(center['id']?.toString() ?? '')
        : null;
    final nestedGradeId = grade is Map<String, dynamic>
        ? int.tryParse(grade['id']?.toString() ?? '')
        : null;
    if (center is Map<String, dynamic>) {
      if (kDebugMode) {
        debugPrint(
          '>>> PARSING profile center: logo=${center["logo"]}, cover=${center["cover"]}',
        );
      }
    } else {
      if (kDebugMode) {
        debugPrint(
          '>>> PARSING profile center: no nested center object (${json["center_id"]})',
        );
      }
    }
    final parsed = StudentModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      // The live API returns `name`, not `full_name` (APP_SPEC.md's
      // original draft) — `full_name` kept as a fallback in case an older
      // cached profile (written before this fix) is read back.
      fullName: json['name'] as String? ?? json['full_name'] as String? ?? '',
      mobile: json['mobile'] as String? ?? '',
      email: json['email'] as String?,
      // The live API has no `status` field on the user object at all (only
      // `role: "student"`) — there's no inactive/suspended concept exposed
      // here, so this just always resolves to "active".
      status: json['status'] as String? ?? 'active',
      // The API returns a storage-relative path (e.g. `avatars/xxx.jpg`),
      // not a full URL — resolving it here is what actually makes the
      // photo render; leaving it raw silently fails every Image.network
      // call with an invalid-URI error.
      avatarUrl: ApiEndpoints.mediaUrl(json['avatar'] as String?),
      centerId:
          nestedCenterId ?? int.tryParse(json['center_id']?.toString() ?? ''),
      centerJson: center is Map<String, dynamic> ? center : null,
      gradeId:
          nestedGradeId ?? int.tryParse(json['grade_id']?.toString() ?? ''),
      subscriptionStatus: subscriptionStatus,
      hasPaidAccess: _asBool(json['has_paid_access']),
      role: _role(json),
      mustChangePassword: _asBool(json['must_change_password']),
      parentCode: _nonEmptyString(json['parent_code']),
    );
    if (kDebugMode) {
      debugPrint(
        '>>> STUDENT centerLogo=${parsed.centerLogo}, centerCover=${parsed.centerCover}',
      );
    }
    return parsed;
  }

  /// `role` as sent by the live API, else whatever other shape an admin
  /// account might carry (`type`/`user_type`, or a bare `is_admin` flag).
  static String? _role(Map<String, dynamic> json) {
    final raw = json['role'] ?? json['user_type'] ?? json['type'];
    final role = raw is Map ? raw['name'] : raw;
    if (role is String && role.isNotEmpty) return role.toLowerCase();
    if (_asBool(json['is_admin'])) return 'admin';
    return null;
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _asBool(Object? value) =>
      value == true || value == 1 || value == '1' || value == 'true';

  /// Unwraps the `{success, message, data}` envelope shared by `/login`,
  /// `/register` (`data.user`) and `/profile` (`data` *is* the user object
  /// directly, no further nesting). `subscription_status` may end up sitting
  /// beside `user` in that envelope rather than inside it — merged in here
  /// before handing off to [fromJson] if so.
  factory StudentModel.fromEnvelope(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final body = data['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(data['user'] as Map)
        : data;
    // `center` (and `grade`) may sit beside `user` rather than inside it.
    for (final key in const ['center', 'grade']) {
      if (body[key] is! Map && data[key] is Map) body[key] = data[key];
      if (body[key] is! Map && json[key] is Map) body[key] = json[key];
    }
    if (body['subscription_status'] == null &&
        data['subscription_status'] != null) {
      body['subscription_status'] = data['subscription_status'];
    }
    return StudentModel.fromJson(body);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': fullName,
    'mobile': mobile,
    'status': status,
    'avatar': avatarUrl,
    if (email != null) 'email': email,
    if (centerJson != null)
      'center': centerJson
    else if (centerId != null)
      'center': {'id': centerId},
    if (gradeId != null) 'grade': {'id': gradeId},
    if (subscriptionStatus != null) 'subscription_status': subscriptionStatus,
    'has_paid_access': hasPaidAccess,
    if (role != null) 'role': role,
    'must_change_password': mustChangePassword,
    if (parentCode != null) 'parent_code': parentCode,
  };
}

/// Unwraps the `{success, message, data}` envelope from `/login` and
/// `/register`, both of which return `{user, token}` in `data`.
class AuthResponseModel {
  const AuthResponseModel({required this.token, required this.student});

  final String token;
  final StudentModel student;

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    final body = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return AuthResponseModel(
      token: body['token'] as String,
      student: StudentModel.fromJson({
        ...(body['user'] as Map<String, dynamic>),
        // `center`/`grade` may sit beside `user` in the envelope.
        for (final key in const ['center', 'grade'])
          if ((body['user'] as Map)[key] is! Map && body[key] is Map)
            key: body[key],
      }),
    );
  }
}
