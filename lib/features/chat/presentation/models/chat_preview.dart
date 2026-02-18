import 'package:flutter/material.dart';

class ChatPreview {
  const ChatPreview({
    required this.chatId,
    required this.name,
    required this.message,
    required this.time,
    required this.color,
    this.pinned = false,
    this.isUnread = false,
    this.isFavorite = false,
    this.isGroup = false,
    this.avatarUrl,
    this.lastMessageAt,
  });

  final String chatId;
  final String name;
  final String message;
  final String time;
  final Color color;
  final bool pinned;
  final bool isUnread;
  final bool isFavorite;
  final bool isGroup;
  final String? avatarUrl;
  final DateTime? lastMessageAt;

  ChatPreview copyWith({
    String? chatId,
    String? name,
    String? message,
    String? time,
    Color? color,
    bool? pinned,
    bool? isUnread,
    bool? isFavorite,
    bool? isGroup,
    String? avatarUrl,
    DateTime? lastMessageAt,
  }) {
    return ChatPreview(
      chatId: chatId ?? this.chatId,
      name: name ?? this.name,
      message: message ?? this.message,
      time: time ?? this.time,
      color: color ?? this.color,
      pinned: pinned ?? this.pinned,
      isUnread: isUnread ?? this.isUnread,
      isFavorite: isFavorite ?? this.isFavorite,
      isGroup: isGroup ?? this.isGroup,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }

  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

const demoChats = [
  ChatPreview(
    chatId: 'demo-1',
    name: 'Шухратов Заир',
    message: 'Ассалому алекум, қандай янгиликлар?',
    time: '10:46 AM',
    color: Color(0xFF3DC8F6),
    pinned: true,
    isUnread: true,
  ),
  ChatPreview(
    chatId: 'demo-2',
    name: 'Жахонгир Рахмошиков',
    message: 'Яхши, рахмат! Янги лойихалар устида ишлаяпмиз.',
    time: '07:01 AM',
    color: Color(0xFFEEA4C3),
    isFavorite: true,
  ),
  ChatPreview(
    chatId: 'demo-3',
    name: 'Арибжан Камилжанов',
    message: 'Салом! Кеча учрашув жуда фойдали бўлди.',
    time: 'Yesterday',
    color: Color(0xFF9C8DFB),
    isUnread: true,
  ),
  ChatPreview(
    chatId: 'demo-4',
    name: 'Аббос Октамбоев',
    message: 'Ҳа, албатта! Ҳар доим ёрдам беришга тайёрман.',
    time: 'Yesterday',
    color: Color(0xFF7DD6A5),
    isGroup: true,
  ),
  ChatPreview(
    chatId: 'demo-5',
    name: 'Сирожиддин Исмоилов',
    message: 'Лойиҳа режаси бўйича фикрларингиз қандай?',
    time: 'Yesterday',
    color: Color(0xFFF5C06A),
  ),
  ChatPreview(
    chatId: 'demo-6',
    name: 'Абдурахмон Холмуродов',
    message: 'Келаси ҳафта учрашамизми?',
    time: 'Friday',
    color: Color(0xFFF28F96),
  ),
  ChatPreview(
    chatId: 'demo-7',
    name: 'Алина Васильева',
    message: 'Спасибо за помощь с проектом!',
    time: 'Thursday',
    color: Color(0xFF70B0FF),
  ),
  ChatPreview(
    chatId: 'demo-8',
    name: 'Михаил Иванов',
    message: 'До встречи на конференции!',
    time: '7/1/25',
    color: Color(0xFF66D2C2),
  ),
];
