import '../../../../service/db_service.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../data_sources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this.remoteDataSource);

  final AuthRemoteDataSource remoteDataSource;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required String fullName,
    required String userId,
  }) async {
    final response = await remoteDataSource.login(
      username: username,
      password: password,
      fullName: fullName,
      userId: userId,
    );

    if (response.accessToken.isEmpty) {
      throw const FormatException('Токен не получен от сервера');
    }

    if (response.accessToken.isNotEmpty) {
      DBService.accessToken = response.accessToken;
    }
    if (response.refreshToken.isNotEmpty) {
      DBService.refreshToken = response.refreshToken;
    }

    return response.toEntity();
  }
}
