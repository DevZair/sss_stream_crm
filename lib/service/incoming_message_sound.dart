import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../features/chat/presentation/models/chat_preview.dart';

/// Короткий звук входящего сообщения (ассет + debounce, чтобы FCM и Firestore не дублировали).
class IncomingMessageSound {
  IncomingMessageSound._();

  static final AudioPlayer _player = AudioPlayer();
  static DateTime? _lastPlay;
  static const _debounce = Duration(milliseconds: 450);

  static Future<void> play() async {
    final now = DateTime.now();
    if (_lastPlay != null && now.difference(_lastPlay!) < _debounce) return;
    _lastPlay = now;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/message_in.mp3'));
    } catch (e, st) {
      debugPrint('IncomingMessageSound: $e\n$st');
    }
  }

  /// Первый чат с входящим обновлением (для баннера и звука).
  static ChatPreview? findIncomingFirestoreUpdate({
    required List<ChatPreview> previous,
    required List<ChatPreview> next,
    required String? activeChatId,
    required String? currentUserId,
  }) {
    if (currentUserId == null || currentUserId.isEmpty) return null;
    if (previous.isEmpty) return null;

    for (final chat in next) {
      if (chat.chatId == activeChatId) continue;

      ChatPreview? old;
      for (final p in previous) {
        if (p.chatId == chat.chatId) {
          old = p;
          break;
        }
      }

      if (old == null) {
        if (_isIncomingNewChat(chat, currentUserId)) {
          return chat;
        }
        continue;
      }

      if (!_looksLikeNewerMessage(old, chat)) continue;
      final sender = chat.lastMessageSenderId;
      if (sender != null &&
          sender.isNotEmpty &&
          sender != currentUserId) {
        return chat;
      }
    }
    return null;
  }

  /// Звук при диффе списка чатов (см. [findIncomingFirestoreUpdate]).
  static void maybePlayForFirestoreUpdate({
    required List<ChatPreview> previous,
    required List<ChatPreview> next,
    required String? activeChatId,
    required String? currentUserId,
  }) {
    final chat = findIncomingFirestoreUpdate(
      previous: previous,
      next: next,
      activeChatId: activeChatId,
      currentUserId: currentUserId,
    );
    if (chat != null) play();
  }

  static bool _isIncomingNewChat(ChatPreview chat, String me) {
    final sender = chat.lastMessageSenderId;
    if (sender != null && sender.isNotEmpty && sender != me) {
      return chat.lastMessageAt != null;
    }
    return false;
  }

  static bool _looksLikeNewerMessage(ChatPreview old, ChatPreview neu) {
    final nAt = neu.lastMessageAt;
    final oAt = old.lastMessageAt;
    if (nAt == null) return false;
    if (oAt == null) return true;
    if (nAt.isAfter(oAt)) return true;
    if (nAt == oAt && neu.message != old.message) return true;
    return false;
  }
}
