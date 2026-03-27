import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../features/call/services/connectycube_call_kit_service.dart';
import '../firebase_options.dart';
import 'db_service.dart';
import 'local_push_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (ConnectycubeCallKitService.isConnectycubeCallPayload(message.data)) {
    WidgetsFlutterBinding.ensureInitialized();
    await ConnectycubeCallKitService.handleCallRemoteMessageInBackground(
      message,
    );
    return;
  }

  await LocalPushNotifications.ensureInitialized(registerTapHandler: false);
  await LocalPushNotifications.showFromRemoteMessageIfDataOnly(message);
}

class FirebaseBackendService {
  const FirebaseBackendService._();

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseMessaging get messaging => FirebaseMessaging.instance;

  static Future<void> initialize({FirebaseOptions? options}) async {
    await Firebase.initializeApp(options: options);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _configureMessaging();
    await LocalPushNotifications.ensureInitialized();
    await hydrateLocalSession();
  }


  static Future<void> hydrateLocalSession() async {
    final user = auth.currentUser;
    if (user == null) {
      await DBService.clearSession();
      return;
    }

    DBService.firebaseUid = user.uid;
    DBService.refreshToken = user.refreshToken ?? '';

    final idToken = await user.getIdToken();
    if (idToken != null && idToken.isNotEmpty) {
      DBService.accessToken = idToken;
    }

    final snapshot = await firestore.collection('users').doc(user.uid).get();
    final data = snapshot.data();

    DBService.currentUserName = (data?['username'] as String? ?? '').trim();
    DBService.currentFullName =
        (data?['fullName'] as String? ?? user.displayName ?? '').trim();
    DBService.currentInternalUserId = (data?['internalUserId'] as String? ?? '')
        .trim();
    DBService.authEmail = (data?['authEmail'] as String? ?? user.email ?? '')
        .trim();

    await syncCurrentFcmToken();
  }

  static String buildAuthEmail({
    required String username,
    required String userId,
  }) {
    final normalizedUsername = _normalizeAuthPart(username, fallback: 'user');
    final normalizedUserId = _normalizeAuthPart(userId, fallback: 'id');
    if (normalizedUsername.isEmpty || normalizedUserId.isEmpty) {
      throw const FormatException(
        'Укажите корректные логин и ID пользователя.',
      );
    }
    return '$normalizedUsername'
        '__$normalizedUserId@auth.sss-chatapp.app';
  }

  static List<String> buildSearchTokens({
    required String username,
    required String fullName,
    required String internalUserId,
    required String authEmail,
  }) {
    final usernameLower = username.trim().toLowerCase();
    final fullNameLower = fullName.trim().toLowerCase();
    final internalLower = internalUserId.trim().toLowerCase();
    final emailLower = authEmail.trim().toLowerCase();
    final emailLocal = emailLower.split('@').first;
    final combinedUnderscore = '${usernameLower}_$internalLower';

    final Set<String> tokens = {
      usernameLower,
      fullNameLower,
      internalLower,
      emailLower,
      emailLocal,
      combinedUnderscore,
      ..._splitTokens(usernameLower),
      ..._splitTokens(fullNameLower),
      ..._splitTokens(internalLower),
      ..._splitTokens(emailLocal),
    };

    // Add prefixes for better search experience (e.g. "ali" -> "a", "al", "ali")
    if (usernameLower.isNotEmpty) {
      tokens.addAll(_generatePrefixes(usernameLower));
    }
    if (fullNameLower.isNotEmpty) {
      for (final t in _splitTokens(fullNameLower)) {
        tokens.addAll(_generatePrefixes(t));
      }
    }
    if (internalLower.isNotEmpty) {
      tokens.addAll(_generatePrefixes(internalLower));
    }

    return tokens.where((v) => v.isNotEmpty).toList()..sort();
  }

  static Set<String> _generatePrefixes(String value) {
    final Set<String> prefixes = {};
    for (int i = 1; i <= value.length; i++) {
      prefixes.add(value.substring(0, i));
    }
    return prefixes;
  }

  static Future<void> upsertCurrentUserProfile({
    required String username,
    required String fullName,
    required String internalUserId,
    required String authEmail,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Пользователь Firebase не найден.');
    }

    final trimmedUsername = username.trim();
    final trimmedFullName = fullName.trim();
    final trimmedInternalUserId = internalUserId.trim();
    final userRef = firestore.collection('users').doc(user.uid);
    final snapshot = await userRef.get();
    final existingPhoneDigits =
        (snapshot.data()?['phoneDigits'] as String? ?? '').trim();
    final payload = <String, Object?>{
      'uid': user.uid,
      'username': trimmedUsername,
      'usernameLower': trimmedUsername.toLowerCase(),
      'fullName': trimmedFullName,
      'fullNameLower': trimmedFullName.toLowerCase(),
      'internalUserId': trimmedInternalUserId,
      'authEmail': authEmail,
      'phoneDigits': existingPhoneDigits,
      'searchTokens': buildSearchTokens(
        username: trimmedUsername,
        fullName: trimmedFullName,
        internalUserId: trimmedInternalUserId,
        authEmail: authEmail,
      ),
      'registrationCompleted': true,
      'authProvider': 'password',
      'lastLoginAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!snapshot.exists) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }

    await userRef.set(payload, SetOptions(merge: true));

    DBService.firebaseUid = user.uid;
    DBService.currentUserName = trimmedUsername;
    DBService.currentFullName = trimmedFullName;
    DBService.currentInternalUserId = trimmedInternalUserId;
    DBService.authEmail = authEmail;

    await syncCurrentFcmToken();
  }

  static Future<void> syncCurrentFcmToken([String? token]) async {
    final user = auth.currentUser;
    final resolvedToken = (token ?? DBService.fcmToken).trim();
    if (user == null || resolvedToken.isEmpty) return;

    await firestore.collection('users').doc(user.uid).set({
      'lastFcmToken': resolvedToken,
      'fcmTokens': FieldValue.arrayUnion([resolvedToken]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> _configureMessaging() async {
    try {
      await messaging.setAutoInitEnabled(true);

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint(
        'FCM authorization status: ${settings.authorizationStatus.name}',
      );

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        DBService.fcmToken = token;
        unawaited(syncCurrentFcmToken(token));
      }

      messaging.onTokenRefresh.listen((nextToken) {
        DBService.fcmToken = nextToken;
        unawaited(syncCurrentFcmToken(nextToken));
      });
    } on Object catch (error, stackTrace) {
      debugPrint('FCM setup skipped: $error\n$stackTrace');
    }
  }

  static String _normalizeAuthPart(String value, {required String fallback}) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]'),
      '_',
    );
    if (normalized.isEmpty) return fallback;
    return normalized;
  }

  static Set<String> _splitTokens(String value) {
    return value
        .split(RegExp(r'[\s._-]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }
}
