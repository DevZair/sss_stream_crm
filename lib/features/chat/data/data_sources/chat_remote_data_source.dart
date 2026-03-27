import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../../../service/db_service.dart';
import '../../../chat/domain/entities/chat_message.dart';
import '../../presentation/models/chat_preview.dart';

class UploadResult {
  const UploadResult({
    required this.url,
    required this.originalName,
    required this.kind,
  });

  final String url;
  final String originalName;
  final String kind;
}

class GlobalSearchUser {
  const GlobalSearchUser({
    required this.uid,
    required this.username,
    required this.fullName,
    required this.internalUserId,
    required this.avatarUrl,
  });

  final String uid;
  final String username;
  final String fullName;
  final String internalUserId;
  final String avatarUrl;

  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (username.trim().isNotEmpty) return username.trim();
    if (internalUserId.trim().isNotEmpty) return internalUserId.trim();
    return 'Пользователь';
  }
}

class ChatRemoteDataSource {
  const ChatRemoteDataSource();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<List<ChatPreview>> fetchChats({int limit = 50}) async {
    final currentUser = await _loadCurrentUserProfile();
    final snapshot = await _firestore
        .collection('chats')
        .where('participantIds', arrayContains: currentUser.uid)
        .orderBy('lastMessageAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => _mapChatPreview(doc.data(), doc.id, currentUser.uid))
        .toList();
  }

  Stream<List<ChatPreview>> streamChats({int limit = 50}) async* {
    final currentUser = await _loadCurrentUserProfile();

    yield* _firestore
        .collection('chats')
        .where('participantIds', arrayContains: currentUser.uid)
        .orderBy('lastMessageAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _mapChatPreview(doc.data(), doc.id, currentUser.uid))
            .toList());
  }

  Future<List<GlobalSearchUser>> searchUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final currentUser = await _loadCurrentUserProfile();

    final snapshot = await _firestore
        .collection('users')
        .where('searchTokens', arrayContains: q)
        .limit(20)
        .get();

    return snapshot.docs
        .map((doc) => _userProfileFromDoc(doc))
        .where((user) => user.uid != currentUser.uid)
        .toList();
  }

  /// Firebase UID контакта по цифрам телефона (для external-чата → видеозвонок).
  Future<String?> resolveRegisteredUidByPhoneDigits(String digits) async {
    final normalized = digits.replaceAll(RegExp(r'\D'), '');
    if (normalized.length < 6) return null;

    final currentUser = await _loadCurrentUserProfile();

    final byToken = await _firestore
        .collection('users')
        .where('searchTokens', arrayContains: normalized)
        .limit(5)
        .get();

    for (final doc in byToken.docs) {
      if (doc.id != currentUser.uid) return doc.id;
    }

    final byPhone = await _firestore
        .collection('users')
        .where('phoneDigits', isEqualTo: normalized)
        .limit(5)
        .get();

    for (final doc in byPhone.docs) {
      if (doc.id != currentUser.uid) return doc.id;
    }

    return null;
  }

  Future<List<ChatMessage>> fetchMessages(
    String chatId, {
    int limit = 100,
  }) async {
    final currentUser = await _loadCurrentUserProfile();
    final chatRef = _chatRef(chatId);

    await _ensureCanAccessChat(chatRef, currentUser.uid);

    final snapshot = await chatRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    await chatRef.update({
      'unreadBy': FieldValue.arrayRemove([currentUser.uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return snapshot.docs.reversed
        .map((doc) => _mapMessage(doc.data(), doc.id, currentUser.uid))
        .toList();
  }

  Stream<List<ChatMessage>> streamMessages(
    String chatId, {
    int limit = 100,
  }) async* {
    final currentUser = await _loadCurrentUserProfile();
    final chatRef = _chatRef(chatId);

    // We can't await easily inside a stream before yielding, but async* allows it.
    await _ensureCanAccessChat(chatRef, currentUser.uid);

    yield* chatRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .asyncMap((snapshot) async {
      
      // Clear unread badge
      try {
        await chatRef.update({
          'unreadBy': FieldValue.arrayRemove([currentUser.uid]),
        });
      } catch (_) {} // ignore permission issues if any during stream

      return snapshot.docs.reversed
          .map((doc) => _mapMessage(doc.data(), doc.id, currentUser.uid))
          .toList();
    });
  }

  Future<void> sendText({
    required String chatId,
    required String text,
    String? replyTo,
  }) async {
    final currentUser = await _loadCurrentUserProfile();
    final chatRef = _chatRef(chatId);

    await _ensureCanAccessChat(chatRef, currentUser.uid);

    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    await chatRef.collection('messages').add({
      'senderId': currentUser.uid,
      'senderName': currentUser.displayName,
      'type': 'text',
      'text': trimmedText,
      'replyTo': _nullIfEmpty(replyTo),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'mediaUrl': '',
      'fileName': '',
      'durationMillis': 0,
    });

    await _updateChatSummary(
      chatRef,
      senderId: currentUser.uid,
      senderName: currentUser.displayName,
      previewText: trimmedText,
      messageType: 'text',
    );
  }

  Future<void> sendMedia({
    required String chatId,
    required UploadResult upload,
    String? caption,
    String? replyTo,
  }) async {
    final currentUser = await _loadCurrentUserProfile();
    final chatRef = _chatRef(chatId);

    await _ensureCanAccessChat(chatRef, currentUser.uid);

    final trimmedCaption = caption?.trim() ?? '';
    final messageType = _messageTypeFromUploadKind(upload.kind);
    final previewText = trimmedCaption.isNotEmpty
        ? trimmedCaption
        : _previewLabelForType(messageType);

    await chatRef.collection('messages').add({
      'senderId': currentUser.uid,
      'senderName': currentUser.displayName,
      'type': messageType,
      'text': trimmedCaption,
      'replyTo': _nullIfEmpty(replyTo),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'mediaUrl': upload.url,
      'fileName': upload.originalName,
      'durationMillis': 0,
    });

    await _updateChatSummary(
      chatRef,
      senderId: currentUser.uid,
      senderName: currentUser.displayName,
      previewText: previewText,
      messageType: messageType,
    );
  }

  Future<UploadResult> uploadFile({
    required String kind,
    required String filePath,
  }) async {
    final currentUser = await _loadCurrentUserProfile();
    final file = File(filePath);
    if (!await file.exists()) {
      throw const FileSystemException('Файл не найден');
    }

    final fileName = file.path.split(Platform.pathSeparator).last;
    final objectPath =
        'chat_uploads/${currentUser.uid}/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    final ref = _storage.ref(objectPath);
    await ref.putFile(
      file,
      SettableMetadata(
        contentType: _contentTypeForKind(kind, fileName),
        customMetadata: {'uploadedBy': currentUser.uid, 'kind': kind},
      ),
    );

    final url = await ref.getDownloadURL();
    return UploadResult(url: url, originalName: fileName, kind: kind);
  }

  Future<ChatPreview> startChat(String query) async {
    final currentUser = await _loadCurrentUserProfile();
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      throw const FormatException('Введите имя, логин или номер.');
    }

    final otherUser = await _findUserByQuery(normalizedQuery, currentUser);

    if (otherUser != null) {
      if (otherUser.uid == currentUser.uid) {
        throw const FormatException('Нельзя создать чат с самим собой.');
      }

      final chatId = _directChatId(currentUser.uid, otherUser.uid);
      final peerIds = [currentUser.uid, otherUser.uid]..sort();
      final chatRef = _chatRef(chatId);
      final existing = await chatRef.get();
      final payload = <String, Object?>{
        'type': 'direct',
        'participantIds': [currentUser.uid, otherUser.uid],
        // Фиксированная пара для правил Firestore: после «выйти из чата» можно снова открыть диалог.
        'peerIds': peerIds,
        'displayNameByUser': {
          currentUser.uid: otherUser.displayName,
          otherUser.uid: currentUser.displayName,
        },
        'avatarUrlByUser': {
          currentUser.uid: otherUser.avatarUrl,
          otherUser.uid: currentUser.avatarUrl,
        },
        'contactLookup': normalizedQuery,
        'lastMessageText': '',
        'lastMessageType': 'text',
        'unreadBy': const <String>[],
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!existing.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      await chatRef.set(payload, SetOptions(merge: true));

      final snapshot = await chatRef.get();
      return _mapChatPreview(
        snapshot.data() ?? const {},
        chatId,
        currentUser.uid,
      );
    }

    final digits = normalizedQuery.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) {
      throw const FormatException(
        'Пользователь не найден. Укажите логин или номер телефона.',
      );
    }

    final chatId = 'external_${currentUser.uid}_$digits';
    final chatRef = _chatRef(chatId);
    final existing = await chatRef.get();
    final payload = <String, Object?>{
      'type': 'external',
      'participantIds': [currentUser.uid],
      'displayNameByUser': {currentUser.uid: digits},
      'avatarUrlByUser': {currentUser.uid: ''},
      'externalContactPhone': digits,
      'createdBy': currentUser.uid,
      'lastMessageText': '',
      'lastMessageType': 'text',
      'unreadBy': const <String>[],
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!existing.exists) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }
    await chatRef.set(payload, SetOptions(merge: true));

    return _mapChatPreview(
      (await chatRef.get()).data() ?? const {},
      chatId,
      currentUser.uid,
    );
  }

  Future<GlobalSearchUser?> _findUserByQuery(
    String query,
    GlobalSearchUser current,
  ) async {
    final q = query.trim().toLowerCase();
    final digits = q.replaceAll(RegExp(r'\D'), '');

    final Set<String> seen = {current.uid};
    final List<GlobalSearchUser> candidates = [];

    final first = await _firestore
        .collection('users')
        .where('searchTokens', arrayContains: q)
        .limit(5)
        .get();
    for (final doc in first.docs) {
      final user = _userProfileFromDoc(doc);
      if (!seen.contains(user.uid)) {
        seen.add(user.uid);
        candidates.add(user);
      }
    }

    // Поиск по любым токенам (разбиваем по пробелу/подчёркиванию/дефису)
    final tokens = q
        .split(RegExp(r'[\s._-]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet();

    for (final token in tokens) {
      final snapshot = await _firestore
          .collection('users')
          .where('searchTokens', arrayContains: token)
          .limit(5)
          .get();
      for (final doc in snapshot.docs) {
        final user = _userProfileFromDoc(doc);
        if (!seen.contains(user.uid)) {
          seen.add(user.uid);
          candidates.add(user);
        }
      }
    }

    if (digits.length >= 6) {
      final snapshot = await _firestore
          .collection('users')
          .where('searchTokens', arrayContains: digits)
          .limit(5)
          .get();
      for (final doc in snapshot.docs) {
        final user = _userProfileFromDoc(doc);
        if (!seen.contains(user.uid)) {
          seen.add(user.uid);
          candidates.add(user);
        }
      }
    }

    return candidates.isEmpty ? null : candidates.first;
  }

  Future<void> deleteChat(String chatId) async {
    final currentUser = await _loadCurrentUserProfile();
    final chatRef = _chatRef(chatId);
    final snapshot = await chatRef.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return;

    final participantIds =
        (data['participantIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();

    if (!participantIds.contains(currentUser.uid)) {
      throw StateError('Нет доступа к этому чату.');
    }

    if (participantIds.length <= 1) {
      await chatRef.delete();
      return;
    }

    await chatRef.update({
      'participantIds': FieldValue.arrayRemove([currentUser.uid]),
      'unreadBy': FieldValue.arrayRemove([currentUser.uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<ChatMessage?> fetchMessage({
    required String chatId,
    required String messageRef,
  }) async {
    final currentUser = await _loadCurrentUserProfile();
    final chatRef = _chatRef(chatId);
    await _ensureCanAccessChat(chatRef, currentUser.uid);

    final snapshot = await chatRef.collection('messages').doc(messageRef).get();
    if (!snapshot.exists) return null;

    return _mapMessage(
      snapshot.data() ?? const {},
      snapshot.id,
      currentUser.uid,
    );
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageRef,
  }) async {
    final currentUser = await _loadCurrentUserProfile();
    final chatRef = _chatRef(chatId);
    await _ensureCanAccessChat(chatRef, currentUser.uid);

    final messageRefDoc = chatRef.collection('messages').doc(messageRef);
    final messageSnapshot = await messageRefDoc.get();
    if (!messageSnapshot.exists) return;

    final messageData = messageSnapshot.data() ?? const {};
    if ((messageData['senderId'] as String? ?? '') != currentUser.uid) {
      throw const FormatException('Можно удалять только свои сообщения.');
    }

    await messageRefDoc.delete();
    await _syncChatSummary(chatRef);
  }

  Future<ChatMessage?> updateMessage({
    required String chatId,
    required String messageRef,
    required Map<String, Object?> payload,
  }) async {
    final currentUser = await _loadCurrentUserProfile();
    final chatRef = _chatRef(chatId);
    await _ensureCanAccessChat(chatRef, currentUser.uid);

    final messageDoc = chatRef.collection('messages').doc(messageRef);
    final snapshot = await messageDoc.get();
    if (!snapshot.exists) return null;

    final data = snapshot.data() ?? const {};
    if ((data['senderId'] as String? ?? '') != currentUser.uid) {
      throw const FormatException('Можно редактировать только свои сообщения.');
    }

    final updatedText = (payload['text'] as String? ?? '').trim();
    await messageDoc.update({
      'text': updatedText,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _syncChatSummary(chatRef);

    final refreshed = await messageDoc.get();
    if (!refreshed.exists) return null;
    return _mapMessage(
      refreshed.data() ?? const {},
      refreshed.id,
      currentUser.uid,
    );
  }

  DocumentReference<Map<String, dynamic>> _chatRef(String chatId) {
    return _firestore.collection('chats').doc(chatId);
  }

  Future<void> _ensureCanAccessChat(
    DocumentReference<Map<String, dynamic>> chatRef,
    String uid,
  ) async {
    final snapshot = await chatRef.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw StateError('Чат не найден.');
    }

    final participantIds =
        (data['participantIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();

    if (!participantIds.contains(uid)) {
      throw StateError('Нет доступа к этому чату.');
    }
  }

  Future<GlobalSearchUser> _loadCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Выполните вход в приложение.');
    }

    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    final data = snapshot.data() ?? const {};
    final username = (data['username'] as String? ?? DBService.currentUserName)
        .trim();
    final fullName = (data['fullName'] as String? ?? DBService.currentFullName)
        .trim();
    final internalUserId =
        (data['internalUserId'] as String? ?? DBService.currentInternalUserId)
            .trim();
    final avatarUrl = (data['avatarUrl'] as String? ?? '').trim();

    return GlobalSearchUser(
      uid: user.uid,
      username: username,
      fullName: fullName,
      internalUserId: internalUserId,
      avatarUrl: avatarUrl,
    );
  }

  GlobalSearchUser _userProfileFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return GlobalSearchUser(
      uid: doc.id,
      username: (data['username'] as String? ?? '').trim(),
      fullName: (data['fullName'] as String? ?? '').trim(),
      internalUserId: (data['internalUserId'] as String? ?? '').trim(),
      avatarUrl: (data['avatarUrl'] as String? ?? '').trim(),
    );
  }


  Future<void> _updateChatSummary(
    DocumentReference<Map<String, dynamic>> chatRef, {
    required String senderId,
    required String senderName,
    required String previewText,
    required String messageType,
  }) async {
    final snapshot = await chatRef.get();
    final data = snapshot.data() ?? const {};
    final participantIds =
        (data['participantIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
    final unreadBy = participantIds.where((id) => id != senderId).toList();

    await chatRef.set({
      'lastMessageText': previewText,
      'lastMessageType': messageType,
      'lastMessageSenderId': senderId,
      'lastMessageSenderName': senderName,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadBy': unreadBy,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _syncChatSummary(
    DocumentReference<Map<String, dynamic>> chatRef,
  ) async {
    final chatSnapshot = await chatRef.get();
    final chatData = chatSnapshot.data() ?? const {};
    final unreadBy = (chatData['unreadBy'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();

    final latest = await chatRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (latest.docs.isEmpty) {
      await chatRef.set({
        'lastMessageText': '',
        'lastMessageType': 'text',
        'lastMessageSenderId': '',
        'lastMessageSenderName': '',
        'lastMessageAt': chatData['createdAt'] ?? FieldValue.serverTimestamp(),
        'unreadBy': const <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final doc = latest.docs.first;
    final data = doc.data();
    final messageType = (data['type'] as String? ?? 'text').trim();
    final text = (data['text'] as String? ?? '').trim();

    await chatRef.set({
      'lastMessageText': text.isNotEmpty
          ? text
          : _previewLabelForType(messageType),
      'lastMessageType': messageType,
      'lastMessageSenderId': (data['senderId'] as String? ?? '').trim(),
      'lastMessageSenderName': (data['senderName'] as String? ?? '').trim(),
      'lastMessageAt': data['createdAt'],
      'unreadBy': unreadBy,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  ChatPreview _mapChatPreview(
    Map<String, dynamic> data,
    String chatId,
    String currentUid,
  ) {
    final displayNameByUser =
        (data['displayNameByUser'] as Map<dynamic, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );
    final avatarUrlByUser =
        (data['avatarUrlByUser'] as Map<dynamic, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );

    final chatType = (data['type'] as String? ?? '').trim();
    String? directPeerUid;
    String? externalContactDigits;
    if (chatType == 'direct') {
      final participantIds =
          (data['participantIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
      for (final id in participantIds) {
        if (id != currentUid) {
          directPeerUid = id;
          break;
        }
      }
    } else if (chatType == 'external') {
      final raw = (data['externalContactPhone'] as String? ?? '').trim();
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 6) externalContactDigits = digits;
    }

    final resolvedName =
        displayNameByUser[currentUid]?.trim().isNotEmpty == true
        ? displayNameByUser[currentUid]!.trim()
        : (data['externalContactPhone'] as String? ?? 'Чат').trim();
    final lastMessageType = (data['lastMessageType'] as String? ?? 'text')
        .trim();
    final rawLastText = (data['lastMessageText'] as String? ?? '').trim();
    final previewText = rawLastText.isNotEmpty
        ? rawLastText
        : _previewLabelForType(lastMessageType);
    final lastMessageAt = _toDateTime(data['lastMessageAt']);
    final unreadBy = (data['unreadBy'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet();
    final avatarUrl = (avatarUrlByUser[currentUid] ?? '').trim();

    final lastSender =
        (data['lastMessageSenderId'] as String? ?? '').trim();

    return ChatPreview(
      chatId: chatId,
      name: resolvedName.isEmpty ? 'Чат' : resolvedName,
      message: previewText,
      time: _formatPreviewTime(lastMessageAt),
      color: _chatColor(chatId),
      isUnread: unreadBy.contains(currentUid),
      avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      lastMessageAt: lastMessageAt,
      lastMessageSenderId: lastSender.isEmpty ? null : lastSender,
      chatType: chatType,
      directPeerUid: directPeerUid,
      externalContactDigits: externalContactDigits,
    );
  }

  ChatMessage _mapMessage(
    Map<String, dynamic> data,
    String id,
    String currentUid,
  ) {
    final timestamp = _toDateTime(data['createdAt'] ?? data['updatedAt']);
    final type = _messageTypeFromValue(
      (data['type'] as String? ?? 'text').trim(),
    );

    return ChatMessage(
      id: id,
      text: (data['text'] as String? ?? '').trim(),
      timeLabel: ChatMessage.formatTime(timestamp),
      isMe: (data['senderId'] as String? ?? '') == currentUid,
      type: type,
      mediaPath: (data['mediaUrl'] as String? ?? '').trim(),
      fileName: (data['fileName'] as String? ?? '').trim(),
      duration: Duration(
        milliseconds: (data['durationMillis'] as num? ?? 0).round(),
      ),
      timestamp: timestamp,
    );
  }

  MessageType _messageTypeFromValue(String value) {
    switch (value) {
      case 'image':
        return MessageType.image;
      case 'voice':
      case 'audio':
        return MessageType.voice;
      case 'file':
      case 'document':
      case 'video':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }

  String _messageTypeFromUploadKind(String kind) {
    switch (kind) {
      case 'image':
        return 'image';
      case 'audio':
        return 'voice';
      default:
        return 'file';
    }
  }

  String _previewLabelForType(String type) {
    switch (type) {
      case 'image':
        return 'Фото';
      case 'voice':
      case 'audio':
        return 'Голосовое сообщение';
      case 'file':
      case 'document':
      case 'video':
        return 'Файл';
      default:
        return 'Нет сообщений';
    }
  }

  DateTime? _toDateTime(Object? value) {
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    if (value is num) {
      final millis = value.toInt();
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
    }
    return null;
  }

  String _formatPreviewTime(DateTime? value) {
    if (value == null) return '';

    final now = DateTime.now();
    final sameDay =
        value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
    if (sameDay) return ChatMessage.formatTime(value);

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        value.year == yesterday.year &&
        value.month == yesterday.month &&
        value.day == yesterday.day;
    if (isYesterday) return 'Вчера';

    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    if (value.year == now.year) {
      return '$day.$month';
    }

    final year = (value.year % 100).toString().padLeft(2, '0');
    return '$day.$month.$year';
  }

  Color _chatColor(String seed) {
    const palette = <Color>[
      Color(0xFF3DC8F6),
      Color(0xFFEEA4C3),
      Color(0xFF9C8DFB),
      Color(0xFF7DD6A5),
      Color(0xFFF5C06A),
      Color(0xFFF28F96),
      Color(0xFF70B0FF),
      Color(0xFF66D2C2),
    ];
    return palette[seed.hashCode.abs() % palette.length];
  }

  String _directChatId(String firstUid, String secondUid) {
    final ids = [firstUid, secondUid]..sort();
    return 'direct_${ids.join('_')}';
  }

  String? _nullIfEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String _contentTypeForKind(String kind, String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (kind) {
      case 'image':
        if (extension == 'png') return 'image/png';
        if (extension == 'webp') return 'image/webp';
        return 'image/jpeg';
      case 'audio':
        if (extension == 'wav') return 'audio/wav';
        return 'audio/mp4';
      default:
        if (extension == 'pdf') return 'application/pdf';
        if (extension == 'doc') return 'application/msword';
        if (extension == 'docx') {
          return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        }
        return 'application/octet-stream';
    }
  }
}

