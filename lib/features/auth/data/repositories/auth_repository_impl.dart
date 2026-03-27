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
    final session = await remoteDataSource.login(
      username: username,
      password: password,
      fullName: fullName,
      userId: userId,
    );

    if (session.accessToken.isEmpty) {
      throw const FormatException('Токен Firebase не получен');
    }

    DBService.accessToken = session.accessToken;
    if (session.refreshToken.isNotEmpty) {
      DBService.refreshToken = session.refreshToken;
    }

    return session;
  }
}
