import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service.dart';

const String kMessageChannelId = 'sss_chat_messages';
const String kMessageChannelName = 'Сообщения';

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

bool _initialized = false;

/// Показывает локальное уведомление из data-only FCM в фоне + общая настройка канала.
class LocalPushNotifications {
  LocalPushNotifications._();

  static Future<void> ensureInitialized({bool registerTapHandler = true}) async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: registerTapHandler
          ? _onNotificationResponse
          : null,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        kMessageChannelId,
        kMessageChannelName,
        description: 'Новые сообщения в чатах',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    _initialized = true;
  }

  static Future<NotificationAppLaunchDetails?> getLaunchDetails() =>
      _plugin.getNotificationAppLaunchDetails();

  /// Вызывать из [firebaseMessagingBackgroundHandler]: только data-only (без блока notification).
  static Future<void> showFromRemoteMessageIfDataOnly(
    RemoteMessage message,
  ) async {
    if (kIsWeb) return;
    if (message.notification != null) return;

    final data = message.data;
    final chatId = (data['chatId'] as String?)?.trim();
    if (chatId == null || chatId.isEmpty) return;

    final title = _titleFromData(data, fallback: 'Новое сообщение');
    var body = _bodyFromData(data);
    if (body.isEmpty) body = 'Сообщение';

    await showMessage(
      id: chatId.hashCode & 0x7fffffff,
      title: title,
      body: body,
      chatId: chatId,
    );
  }

  static Future<void> showMessage({
    required int id,
    required String title,
    required String body,
    required String chatId,
  }) async {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          kMessageChannelId,
          kMessageChannelName,
          channelDescription: 'Новые сообщения в чатах',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: chatId,
    );
  }

  static String _titleFromData(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    for (final key in [
      'senderName',
      'title',
      'fromName',
      'sender',
      'username',
    ]) {
      final v = data[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return fallback;
  }

  static String _bodyFromData(Map<String, dynamic> data) {
    for (final key in [
      'body',
      'message',
      'lastMessageText',
      'text',
      'preview',
    ]) {
      final v = data[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }
}

void _onNotificationResponse(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService.instance.openChatById(payload);
  });
}
