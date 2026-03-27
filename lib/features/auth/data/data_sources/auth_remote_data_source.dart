import 'package:firebase_auth/firebase_auth.dart';

import '../../../../service/db_service.dart';
import '../../../../service/firebase_backend_service.dart';
import '../../domain/entities/auth_session.dart';

class AuthRemoteDataSource {
  Future<AuthSession> login({
    required String username,
    required String password,
    required String fullName,
    required String userId,
  }) async {
    final trimmedUsername = username.trim();
    final trimmedFullName = fullName.trim();
    final trimmedUserId = userId.trim();
    final authEmail = FirebaseBackendService.buildAuthEmail(
      username: trimmedUsername,
      userId: trimmedUserId,
    );

    UserCredential credential;

    try {
      credential = await FirebaseBackendService.auth.signInWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      final shouldCreate =
          error.code == 'user-not-found' || error.code == 'invalid-credential';
      if (!shouldCreate) rethrow;

      try {
        credential = await FirebaseBackendService.auth
            .createUserWithEmailAndPassword(
              email: authEmail,
              password: password,
            );
      } on FirebaseAuthException catch (createError) {
        if (createError.code == 'email-already-in-use') {
          throw const FormatException('Неверный пароль.');
        }
        rethrow;
      }
    }

    final user = credential.user ?? FirebaseBackendService.auth.currentUser;
    if (user == null) {
      throw StateError('Не удалось получить пользователя Firebase.');
    }

    if ((user.displayName ?? '').trim() != trimmedFullName) {
      await user.updateDisplayName(trimmedFullName);
    }

    await FirebaseBackendService.upsertCurrentUserProfile(
      username: trimmedUsername,
      fullName: trimmedFullName,
      internalUserId: trimmedUserId,
      authEmail: authEmail,
    );

    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw const FormatException('Не удалось получить токен Firebase.');
    }

    DBService.accessToken = idToken;
    DBService.refreshToken = user.refreshToken ?? '';
    DBService.firebaseUid = user.uid;

    return AuthSession(
      accessToken: idToken,
      refreshToken: user.refreshToken ?? '',
      userName: trimmedFullName.isNotEmpty ? trimmedFullName : trimmedUsername,
    );
  }
}
