import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../service/api_service.dart';
import '../../../../service/db_service.dart';
import '../../../../service/utils/error_messages.dart';
import '../../../chat/domain/entities/chat_message.dart';
import '../../presentation/models/chat_preview.dart';

class UploadResult {
  const UploadResult({
    required this.url,
    required this.originalName,
  });

  final String url;
  final String originalName;
}

class ChatRemoteDataSource {
  const ChatRemoteDataSource();

  Future<List<ChatPreview>> fetchChats({int limit = 50}) async {
    final path = '${ApiConstants.chatsPath}?limit=$limit';
    final result = await ApiService.request<List<dynamic>>(
      path,
      method: Method.get,
    );
    final items = result
        .whereType<Map<String, Object?>>()
        .map(_mapChatPreview)
        .toList();
    items.sort(
      (a, b) => (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return items;
  }

  Future<List<ChatMessage>> fetchMessages(
    String chatId, {
    int limit = 100,
  }) async {
    final path =
        '${ApiConstants.chatsPath}/${Uri.encodeComponent(chatId)}/messages?limit=$limit';
    final result = await ApiService.request<dynamic>(
      path,
      method: Method.get,
    );

    final List<Map<String, Object?>> rawItems = switch (result) {
      {'items': final List items} => items.whereType<Map<String, Object?>>().toList(),
      {'data': final List items} => items.whereType<Map<String, Object?>>().toList(),
      final List list => list.whereType<Map<String, Object?>>().toList(),
      _ => const [],
    };

    final messages = rawItems
        .map(ChatMessage.fromApi)
        .map((message) {
          if (message.mediaPath.isNotEmpty &&
              !message.mediaPath.startsWith('http')) {
            return message.copyWith(
              mediaPath: _absoluteUrl(message.mediaPath),
            );
          }
          return message;
        })
        .toList();

    messages.sort((a, b) {
      final left = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
      return left.compareTo(right);
    });

    return messages;
  }

  Future<void> sendText({
    required String chatId,
    required String text,
    String? replyTo,
  }) async {
    final path =
        '${ApiConstants.chatsPath}/${Uri.encodeComponent(chatId)}/send/text';
    final payload = <String, Object?>{'text': text};
    if (replyTo != null && replyTo.isNotEmpty) {
      payload['reply_to'] = replyTo;
    }
    await ApiService.request<Object?>(
      path,
      method: Method.post,
      data: payload,
    );
  }

  Future<void> sendMedia({
    required String chatId,
    required UploadResult upload,
    String? caption,
    String? replyTo,
  }) async {
    final path =
        '${ApiConstants.chatsPath}/${Uri.encodeComponent(chatId)}/send/media';
    final payload = <String, Object?>{
      'url': upload.url,
      'file_name': upload.originalName,
    };
    if (caption != null && caption.isNotEmpty) {
      payload['caption'] = caption;
    }
    if (replyTo != null && replyTo.isNotEmpty) {
      payload['reply_to'] = replyTo;
    }

    await ApiService.request<Object?>(
      path,
      method: Method.post,
      data: payload,
    );
  }

  Future<UploadResult> uploadFile({
    required String kind,
    required String filePath,
  }) async {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final path = ApiConstants.uploadPath(kind);
    final response = await ApiService.request<Map<String, dynamic>>(
      path,
      method: Method.post,
      formData: formData,
    );

    if (response['success'] == false) {
      final detail = response['message'] as String? ?? 'Upload failed';
      throw Exception(detail);
    }

    final url = _absoluteUrl(response['path'] as String? ?? '');
    final original = response['original_name'] as String? ?? fileName;

    if (url.isEmpty) {
      throw Exception(friendlyError('Не удалось получить ссылку на файл'));
    }

    return UploadResult(url: url, originalName: original);
  }

  Future<ChatPreview> startChat(String phoneDigits) async {
    final payload = {'phone': phoneDigits};
    final data = await ApiService.request<Map<String, dynamic>>(
      ApiConstants.startChatPath,
      method: Method.post,
      data: payload,
    );
    return _mapChatPreview(data);
  }

  Future<void> deleteChat(String chatId) async {
    final path = '${ApiConstants.chatsPath}/${Uri.encodeComponent(chatId)}';
    await ApiService.request<Object?>(
      path,
      method: Method.delete,
    );
  }

  Future<ChatMessage?> fetchMessage({
    required String chatId,
    required String messageRef,
  }) async {
    final path =
        '${ApiConstants.chatsPath}/${Uri.encodeComponent(chatId)}/messages/${Uri.encodeComponent(messageRef)}';
    final result = await ApiService.request<Map<String, Object?>>(
      path,
      method: Method.get,
    );
    if (result.isEmpty) return null;
    final message = ChatMessage.fromApi(result);
    if (message.mediaPath.isNotEmpty && !message.mediaPath.startsWith('http')) {
      return message.copyWith(mediaPath: _absoluteUrl(message.mediaPath));
    }
    return message;
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageRef,
  }) async {
    final path =
        '${ApiConstants.chatsPath}/${Uri.encodeComponent(chatId)}/messages/${Uri.encodeComponent(messageRef)}';
    await ApiService.request<Object?>(
      path,
      method: Method.delete,
    );
  }

  Future<ChatMessage?> updateMessage({
    required String chatId,
    required String messageRef,
    required Map<String, Object?> payload,
  }) async {
    final path =
        '${ApiConstants.chatsPath}/${Uri.encodeComponent(chatId)}/messages/${Uri.encodeComponent(messageRef)}';
    final result = await ApiService.request<Map<String, Object?>>(
      path,
      method: Method.patch,
      data: payload,
    );
    if (result.isEmpty) return null;
    final message = ChatMessage.fromApi(result);
    if (message.mediaPath.isNotEmpty && !message.mediaPath.startsWith('http')) {
      return message.copyWith(mediaPath: _absoluteUrl(message.mediaPath));
    }
    return message;
  }

  ChatPreview _mapChatPreview(Map<String, Object?> raw) {
    final chatId =
        (raw['chat_id'] ?? raw['chatId'] ?? '').toString().trim();
    final last = raw['last_message'] is Map<String, Object?>
        ? raw['last_message'] as Map<String, Object?>
        : <String, Object?>{};
    final nameCandidates = [
      raw['display_name'],
      raw['group_name'],
      raw['contact_name'],
      raw['phone_display'],
    ];
    final name = nameCandidates
        .whereType<String>()
        .firstWhere((v) => v.trim().isNotEmpty, orElse: () => chatId);
    final lastText = (last['preview'] ??
            last['text'] ??
            (last['media'] is Map<String, Object?>
                ? (last['media'] as Map<String, Object?>)['caption']
                : null) ??
            '')
        .toString()
        .trim();
    final messageText = lastText.isEmpty ? 'Нет сообщений' : lastText;
    final timestamp = last['timestamp'] ??
        last['created_at'] ??
        last['createdAt'] ??
        last['ts'] ??
        last['time'];
    final lastAt = ChatMessage.parseTimestamp(timestamp);
    final isUnread = (last['direction'] ?? '').toString().toLowerCase() ==
            'in' &&
        (last['seen'] != true);

    return ChatPreview(
      chatId: chatId,
      name: name,
      message: messageText,
      time: ChatMessage.formatTime(lastAt),
      color: _colorFromId(chatId),
      isGroup: raw['is_group'] == true,
      isUnread: isUnread,
      avatarUrl: raw['avatar'] as String?,
      lastMessageAt: lastAt,
    );
  }

  String _absoluteUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final base = _resolvedBaseOrigin();
    final normalized = path.startsWith('/') ? path : '/$path';
    if (normalized.startsWith('/api')) {
      return '$base$normalized';
    }
    return '$base/api$normalized';
  }

  String _resolvedBaseOrigin() {
    final stored = DBService.baseUrl;
    String base = stored.isNotEmpty ? stored : ApiConstants.baseUrl;
    if (base.endsWith('/api')) {
      base = base.substring(0, base.length - 4);
    }
    if (base.startsWith('http')) return base;
    return 'https://$base';
  }
}

Color _colorFromId(String id) {
  final hash = id.hashCode;
  final r = (hash & 0xFF0000) >> 16;
  final g = (hash & 0x00FF00) >> 8;
  final b = hash & 0x0000FF;
  return Color.fromARGB(255, (r % 120) + 80, (g % 120) + 80, (b % 120) + 80);
}
