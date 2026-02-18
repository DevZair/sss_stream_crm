import '../entities/auth_session.dart';

abstract class AuthRepository {
  Future<AuthSession> login({
    required String username,
    required String password,
    required String fullName,
    required String userId,
  });
}
