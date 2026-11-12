import 'package:itaaleem/core/utils/result.dart';
import 'package:itaaleem/features/auth/domain/entities/student.dart';

/// Contract implemented by [AuthRepositoryImpl] in the data layer.
///
/// Every method returns a `Result` instead of throwing, so presentation
/// code never needs a try/catch for expected failure cases (validation,
/// network, unauthorized, etc.) — see plan §8.
abstract interface class AuthRepository {
  Future<Result<Student>> register({
    required String fullName,
    required String mobile,
    required String password,
    required String passwordConfirmation,
    String? email,
    int? courseId,
    Map<String, String> extras = const {},
  });

  Future<Result<Student>> login({
    required String mobile,
    required String password,
    String? fcmToken,
  });

  Future<Result<void>> logout();

  /// If a token was persisted from a previous session, verifies it against
  /// `GET /profile` and returns the current student. Returns `null` (and
  /// clears the stale session) if there is no token or the server rejects
  /// it.
  Future<Student?> restoreSession();

  /// The last profile cached on this device, or `null` when there's no
  /// stored token or no cached profile. Never touches the network.
  Future<Student?> cachedSession();

  /// `GET /profile`.
  Future<Result<Student>> getProfile();

  /// `PUT /profile`. [avatarFilePath], when given, uploads a new profile
  /// photo alongside the name/mobile/email change.
  Future<Result<Student>> updateProfile({
    required String fullName,
    String? mobile,
    String? email,
    String? avatarFilePath,
  });

  /// `PUT /password`.
  Future<Result<void>> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirmation,
  });

  /// `DELETE /account` — permanently deletes the account. On success, the
  /// local session is cleared the same way [logout] does; on failure the
  /// session is left untouched since the account still exists.
  Future<Result<void>> deleteAccount();
}
