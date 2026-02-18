import '../entities/auth_session.dart';
import '../repositories/auth_repository.dart';

class LoginParams {
  const LoginParams({
    required this.username,
    required this.password,
    required this.fullName,
    required this.userId,
  });

  final String username;
  final String password;
  final String fullName;
  final String userId;
}

class LoginUseCase {
  const LoginUseCase(this.repository);

  final AuthRepository repository;

  Future<AuthSession> call(LoginParams params) {
    return repository.login(
      username: params.username,
      password: params.password,
      fullName: params.fullName,
      userId: params.userId,
    );
  }
}
