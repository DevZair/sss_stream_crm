import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectycube_flutter_call_kit/connectycube_flutter_call_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app.dart';
import '../../../firebase_options.dart';
import '../data/video_call_models.dart';
import '../data/video_call_remote_data_source.dart';
import '../domain/agora_uid.dart';
import '../presentation/pages/video_call_page.dart';
import 'video_call_lifecycle.dart';

/// Обертка над [connectycube_flutter_call_kit](https://github.com/ConnectyCube/connectycube-flutter-call-kit):
/// нативный экран / уведомление входящего (CallKit / ConnectionService).
class ConnectycubeCallKitService {
  ConnectycubeCallKitService._();

  static bool _initialized = false;
  static bool _voipRefreshHooked = false;

  /// FCM data в формате [ConnectycubeFCMReceiver](https://github.com/ConnectyCube/connectycube-flutter-call-kit).
  static bool isConnectycubeCallPayload(Map<String, dynamic> data) {
    final st = data['signal_type']?.toString();
    return st == 'startCall' || st == 'endCall' || st == 'rejectCall';
  }

  static void ensureInitialized() {
    if (_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _initialized = true;

    _hookVoipTokenRefresh();

    ConnectycubeFlutterCallKit.instance.init(
      onCallAccepted: _onCallAccepted,
      onCallRejected: _onCallRejected,
      onCallIncoming: _onCallIncoming,
      color: '#2367E4',
    );

    ConnectycubeFlutterCallKit.onCallAcceptedWhenTerminated =
        _onCallAcceptedWhenTerminated;
    ConnectycubeFlutterCallKit.onCallRejectedWhenTerminated =
        _onCallRejectedWhenTerminated;
  }

  static void _hookVoipTokenRefresh() {
    if (!Platform.isIOS || _voipRefreshHooked) return;
    _voipRefreshHooked = true;
    ConnectycubeFlutterCallKit.onTokenRefreshed = (token) {
      unawaited(_persistVoipToken(token));
    };
  }

  /// Сохранить VoIP-токен (iOS) в Firestore — для PushKit на бэкенде.
  static Future<void> syncVoipTokenToFirestore() async {
    if (!Platform.isIOS) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _hookVoipTokenRefresh();
    try {
      final token = await ConnectycubeFlutterCallKit.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await _persistVoipToken(token);
      }
    } catch (e, st) {
      debugPrint('VoIP token: $e\n$st');
    }
  }

  static Future<void> _persistVoipToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || token.trim().isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'iosVoipPushToken': token,
        'voipTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('persist VoIP: $e\n$st');
    }
  }

  /// Android 14+: полноэкранный входящий на блокировке — системное разрешение.
  static Future<void> offerFullScreenIncomingCallPermission(
    BuildContext context,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      final allowed = await ConnectycubeFlutterCallKit.canUseFullScreenIntent();
      if (allowed) return;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('call_kit_fullscreen_hint_dismissed') == true) {
        return;
      }
      if (!context.mounted) return;

      final open = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Входящие звонки'),
          content: const Text(
            'Чтобы показывать звонок на экране блокировки (Android 14+), '
            'разрешите «полноэкранные уведомления» для приложения в настройках.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Позже'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Открыть настройки'),
            ),
          ],
        ),
      );

      if (open == true) {
        await ConnectycubeFlutterCallKit.provideFullScreenIntentAccess();
      } else {
        await prefs.setBool('call_kit_fullscreen_hint_dismissed', true);
      }
    } catch (e, st) {
      debugPrint('fullScreenIntent: $e\n$st');
    }
  }

  /// Foreground FCM: возвращает true, если сообщение обработано как звонок.
  static Future<bool> handleForegroundCallPush(RemoteMessage message) async {
    return _applyConnectycubeFcmData(message.data);
  }

  /// Background isolate [firebaseMessagingBackgroundHandler].
  static Future<void> handleCallRemoteMessageInBackground(
    RemoteMessage message,
  ) async {
    await _applyConnectycubeFcmData(message.data);
  }

  static Future<bool> _applyConnectycubeFcmData(Map<String, dynamic> raw) async {
    if (!isConnectycubeCallPayload(raw)) return false;
    final st = raw['signal_type']?.toString();
    if (st == 'endCall' || st == 'rejectCall') {
      final id = raw['session_id']?.toString();
      if (id != null && id.isNotEmpty) {
        await ConnectycubeFlutterCallKit.reportCallEnded(sessionId: id);
        await ConnectycubeFlutterCallKit.clearCallData(sessionId: id);
      }
      return true;
    }
    if (st == 'startCall') {
      await _showNativeIncomingFromFcm(raw);
      return true;
    }
    return false;
  }

  static Future<void> _showNativeIncomingFromFcm(Map<String, dynamic> raw) async {
    final sessionId = raw['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;

    final callType =
        int.tryParse(raw['call_type']?.toString() ?? '') ?? callKitCallTypeVideo;
    final callerId = int.tryParse(raw['caller_id']?.toString() ?? '');
    final callerName = (raw['caller_name']?.toString() ?? '').trim().isNotEmpty
        ? raw['caller_name'].toString().trim()
        : 'Звонок';
    final photo = raw['photo_url']?.toString();

    final oppStr = raw['call_opponents']?.toString() ?? '';
    final opponents = oppStr
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toSet();

    if (callerId == null || opponents.isEmpty) {
      debugPrint(
        'Connectycube FCM: нужны caller_id и call_opponents (через запятую).',
      );
      return;
    }

    final userInfo = <String, String>{};
    final ui = raw['user_info'];
    if (ui is String && ui.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(ui);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            userInfo[k.toString()] = v.toString();
          });
        }
      } catch (_) {}
    }
    for (final entry in [
      ['channel_name', 'channelName'],
      ['channelName', 'channelName'],
      ['callId', 'callId'],
    ]) {
      final v = raw[entry[0]]?.toString();
      if (v != null && v.isNotEmpty) userInfo[entry[1]] = v;
    }

    final event = CallEvent(
      sessionId: sessionId,
      callType: callType == callKitCallTypeAudio
          ? callKitCallTypeAudio
          : callKitCallTypeVideo,
      callerId: callerId,
      callerName: callerName,
      opponentsIds: opponents,
      callPhoto: photo,
      userInfo: userInfo.isEmpty ? null : userInfo,
    );
    await ConnectycubeFlutterCallKit.showCallNotification(event);
  }

  /// Показать системный входящий звонок (в т.ч. поверх других приложений на Android).
  static Future<void> showIncomingKit({
    required String callId,
    required String channelName,
    required String callerName,
    required String callerUid,
    required String calleeUid,
    required int callType,
    String? callPhoto,
  }) {
    final cubeCaller = firebaseUidToAgoraUid(callerUid);
    final cubeCallee = firebaseUidToAgoraUid(calleeUid);

    final event = CallEvent(
      sessionId: callId,
      callType: callType,
      callerId: cubeCaller,
      callerName: callerName.isEmpty ? 'Звонок' : callerName,
      opponentsIds: {cubeCallee},
      callPhoto: callPhoto,
      userInfo: {
        'callId': callId,
        'channelName': channelName,
        'callerUid': callerUid,
        'callType': '$callType',
      },
    );

    return ConnectycubeFlutterCallKit.showCallNotification(event);
  }

  static Future<void> _onCallIncoming(CallEvent event) async {}

  static Future<void> _onCallAccepted(CallEvent e) async {
    final info = e.userInfo ?? {};
    final channelName = (info['channelName'] ?? '').trim();
    final isAudioOnly = e.callType == callKitCallTypeAudio;
    final callId = e.sessionId;

    await ConnectycubeFlutterCallKit.reportCallAccepted(sessionId: callId);
    await const VideoCallRemoteDataSource().deleteIncomingForMe(callId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = App.navigatorKey.currentState;
      if (nav == null || VideoCallLifecycle.isInRoom) return;
      unawaited(
        nav.push<void>(
          CupertinoPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => VideoCallPage(
              callId: callId,
              initialChannelName:
                  channelName.isNotEmpty ? channelName : null,
              isAudioOnly: isAudioOnly,
            ),
          ),
        ),
      );
    });
  }

  static Future<void> _onCallRejected(CallEvent e) async {
    final callId = e.sessionId;
    await const VideoCallRemoteDataSource().deleteIncomingForMe(callId);
    await ConnectycubeFlutterCallKit.reportCallEnded(sessionId: callId);
    await ConnectycubeFlutterCallKit.clearCallData(sessionId: callId);
  }
}

@pragma('vm:entry-point')
Future<void> _onCallAcceptedWhenTerminated(CallEvent e) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await const VideoCallRemoteDataSource().deleteIncomingForMe(e.sessionId);
  await ConnectycubeFlutterCallKit.reportCallAccepted(sessionId: e.sessionId);
}

@pragma('vm:entry-point')
Future<void> _onCallRejectedWhenTerminated(CallEvent e) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await const VideoCallRemoteDataSource().deleteIncomingForMe(e.sessionId);
  await ConnectycubeFlutterCallKit.reportCallEnded(sessionId: e.sessionId);
  await ConnectycubeFlutterCallKit.clearCallData(sessionId: e.sessionId);
}
