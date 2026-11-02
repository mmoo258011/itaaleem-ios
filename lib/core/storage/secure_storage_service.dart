import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper over [FlutterSecureStorage] centralizing the key names used
/// for auth token + device identity persistence.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // resetOnError: if the OS-level encryption key ever becomes
            // unreadable (e.g. keystore invalidated by a backup/restore or
            // an OEM quirk), flutter_secure_storage would otherwise throw on
            // every read forever, which looked like "always forced back to
            // the login screen" even though a token was in fact saved. With
            // this on, a decrypt failure wipes just that corrupted entry and
            // returns null instead of throwing.
            aOptions: AndroidOptions(resetOnError: true),
            // Keep the keychain readable as soon as the device has been
            // unlocked once after boot, so a restart doesn't make the token
            // look "missing" before the user has unlocked their phone.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _authTokenKey = 'auth_token';
  static const _deviceIdKey = 'device_id';
  static const _studentProfileKey = 'student_profile';

  Future<String?> readAuthToken() => _storage.read(key: _authTokenKey);

  Future<void> writeAuthToken(String token) =>
      _storage.write(key: _authTokenKey, value: token);

  Future<void> deleteAuthToken() => _storage.delete(key: _authTokenKey);

  Future<String?> readDeviceId() => _storage.read(key: _deviceIdKey);

  Future<void> writeDeviceId(String deviceId) =>
      _storage.write(key: _deviceIdKey, value: deviceId);

  /// Raw JSON string of the last-known student profile, persisted on
  /// successful login/register so the app can restore auth state on next
  /// launch without an extra network round-trip.
  Future<String?> readStudentProfileJson() =>
      _storage.read(key: _studentProfileKey);

  Future<void> writeStudentProfileJson(String json) =>
      _storage.write(key: _studentProfileKey, value: json);

  Future<void> deleteStudentProfileJson() =>
      _storage.delete(key: _studentProfileKey);

  // --- Session type + guardian ("ولي الأمر") session ---
  // The guardian token lives under its own key so it is never attached to a
  // student endpoint (and vice versa) — the two tokens are separate on the
  // server too.
  static const _sessionTypeKey = 'session_type';
  static const _guardianTokenKey = 'guardian_token';
  static const _guardianProfileKey = 'guardian_profile';

  /// `"student"` or `"guardian"` — which kind of sign-in the stored session is.
  Future<String?> readSessionType() => _storage.read(key: _sessionTypeKey);

  Future<void> writeSessionType(String type) =>
      _storage.write(key: _sessionTypeKey, value: type);

  Future<void> deleteSessionType() => _storage.delete(key: _sessionTypeKey);

  Future<String?> readGuardianToken() => _storage.read(key: _guardianTokenKey);

  Future<void> writeGuardianToken(String token) =>
      _storage.write(key: _guardianTokenKey, value: token);

  Future<String?> readGuardianProfileJson() =>
      _storage.read(key: _guardianProfileKey);

  Future<void> writeGuardianProfileJson(String json) =>
      _storage.write(key: _guardianProfileKey, value: json);

  /// Clears the guardian session (token, cached profile, session type).
  Future<void> clearGuardianSession() async {
    await _storage.delete(key: _guardianTokenKey);
    await _storage.delete(key: _guardianProfileKey);
    await _storage.delete(key: _sessionTypeKey);
  }

  Future<void> clearAll() => _storage.deleteAll();
}

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
