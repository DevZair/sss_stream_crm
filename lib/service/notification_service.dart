import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/widgets/in_app_message_banner.dart';
import '../features/call/services/connectycube_call_kit_service.dart';
import '../features/chat/presentation/pages/chat_detail_page.dart';
import '../features/chat/presentation/models/chat_preview.dart';
import '../app.dart';
import 'incoming_message_sound.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  String? _currentChatId;

  void setCurrentChat(String? chatId) {
    _currentChatId = chatId;
  }

  /// Открытый чат (чтобы не дублировать звук/уведомление).
  String? get currentChatId => _currentChatId;

  Future<void> initialize() async {
    FirebaseMessaging.onMessage.listen((message) {
      unawaited(_handleForegroundMessage(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _navigateToChat(message);
    });
  }

  void openChatById(String chatId) {
    _navigateToChat(chatId);
  }

  /// Баннер по обновлению чата из Firestore (без FCM).
  void showIncomingChatBanner(ChatPreview chat) {
    _showTopBanner(title: chat.name, body: chat.message, chatId: chat.chatId);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (await ConnectycubeCallKitService.handleForegroundCallPush(message)) {
      return;
    }

    final data = message.data;
    final chatId = data['chatId'] as String?;

    if (chatId != null && chatId == _currentChatId) {
      return;
    }

    final notification = message.notification;
    final titleFallback = _titleFromRemoteMessage(message);
    final bodyText = _bodyFromRemoteMessage(message);

    final hasVisualPayload = notification != null ||
        titleFallback.isNotEmpty ||
        bodyText.isNotEmpty;
    if (!hasVisualPayload) return;

    IncomingMessageSound.play();

    final title = (notification?.title?.trim().isNotEmpty == true)
        ? notification!.title!.trim()
        : (titleFallback.isNotEmpty ? titleFallback : 'Новое сообщение');
    final body = (notification?.body?.trim().isNotEmpty == true)
        ? notification!.body!.trim()
        : bodyText;

    _showTopBanner(title: title, body: body, chatId: chatId);
  }

  String _titleFromRemoteMessage(RemoteMessage m) {
    final t = m.notification?.title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final d = m.data;
    for (final key in [
      'senderName',
      'title',
      'fromName',
      'sender',
      'username',
    ]) {
      final v = d[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  String _bodyFromRemoteMessage(RemoteMessage m) {
    final b = m.notification?.body?.trim();
    if (b != null && b.isNotEmpty) return b;
    final d = m.data;
    for (final key in [
      'body',
      'message',
      'lastMessageText',
      'text',
      'preview',
    ]) {
      final v = d[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  void _showTopBanner({
    required String title,
    required String body,
    String? chatId,
  }) {
    final nav = App.navigatorKey.currentState;
    final overlay = nav?.overlay;
    final context = nav?.context;
    if (overlay == null || context == null) return;

    InAppMessageBanner.show(
      overlay: overlay,
      context: context,
      title: title,
      body: body,
      onTap: () {
        if (chatId != null) _navigateToChat(chatId);
      },
    );
  }

  void _navigateToChat(dynamic chatIdOrMessage) {
    String? chatId;
    if (chatIdOrMessage is RemoteMessage) {
      chatId = chatIdOrMessage.data['chatId'] as String?;
    } else if (chatIdOrMessage is String) {
      chatId = chatIdOrMessage;
    }

    if (chatId == null) return;

    final context = App.navigatorKey.currentContext;
    if (context == null) return;

    // Create a minimal ChatPreview for navigation
    final chat = ChatPreview(
      chatId: chatId,
      name: 'Сообщение', // Fallback name
      message: '',
      time: '',
      color: Colors.blue,
    );

    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => ChatDetailPage(chat: chat),
      ),
    );
  }
}
