import 'dart:async';

import '../../../../service/db_service.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';

class MockAuthRepository implements AuthRepository {
  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required String fullName,
    required String userId,
  }) async {
    // Simulate network latency
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final session = AuthSession(
      accessToken: 'demo_token_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'demo_refresh',
      userName: username,
    );

    DBService.accessToken = session.accessToken;
    DBService.refreshToken = session.refreshToken;

    return session;
  }
}
