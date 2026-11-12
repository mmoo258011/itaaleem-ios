import 'package:itaaleem/core/utils/result.dart';
import 'package:itaaleem/features/auth/domain/entities/student.dart';
import 'package:itaaleem/features/auth/domain/repositories/auth_repository.dart';

class RegisterUseCase {
  const RegisterUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<Student>> call({
    required String fullName,
    required String mobile,
    required String password,
    required String passwordConfirmation,
    String? email,
    int? courseId,
    Map<String, String> extras = const {},
  }) {
    return _repository.register(
      fullName: fullName,
      mobile: mobile,
      password: password,
      passwordConfirmation: passwordConfirmation,
      email: email,
      courseId: courseId,
      extras: extras,
    );
  }
}
