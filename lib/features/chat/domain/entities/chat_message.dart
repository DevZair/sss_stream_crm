enum MessageType { text, voice, image, file }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.timeLabel,
    required this.isMe,
    this.type = MessageType.text,
    this.mediaPath = '',
    this.fileName = '',
    this.duration = Duration.zero,
    this.timestamp,
  });

  final String id;
  final String text;
  final String timeLabel;
  final bool isMe;
  final MessageType type;
  final String mediaPath;
  final String fileName;
  final Duration duration;
  final DateTime? timestamp;

  static ChatMessage fromApi(Map<String, Object?> json) {
    final media = json['media'];
    final direction = (json['direction'] ?? '').toString().toLowerCase();
    final isMe = direction == 'out';

    final tsCandidate = json['timestamp'] ??
        json['created_at'] ??
        json['createdAt'] ??
        json['ts'] ??
        json['time'];
    final ts = parseTimestamp(tsCandidate);

    final messageType = _resolveType(
      json['type'],
      media is Map<String, Object?> ? media['type'] : null,
    );

    final String text = _pickText(json, media);
    final mediaPath = _pickMediaUrl(media);
    final fileName = _pickFileName(media);

    final rawId = (json['id'] ??
            json['_id'] ??
            json['id_message'] ??
            json['idMessage'] ??
            json['message_ref'] ??
            json['messageRef'] ??
            '')
        .toString();
    final resolvedId = rawId.trim().isNotEmpty
        ? rawId
        : 'msg_${DateTime.now().millisecondsSinceEpoch}_${direction.hashCode}';

    return ChatMessage(
      id: resolvedId,
      text: text,
      timeLabel: formatTime(ts),
      isMe: isMe,
      type: messageType,
      mediaPath: mediaPath,
      fileName: fileName,
      duration: _resolveDuration(media is Map<String, Object?> ? media : null),
      timestamp: ts,
    );
  }

  static MessageType _resolveType(Object? type, Object? mediaType) {
    final value = (type ?? mediaType ?? '').toString().toLowerCase();
    if (value.contains('image')) return MessageType.image;
    if (value.contains('video')) return MessageType.file;
    if (value.contains('audio') || value.contains('voice')) {
      return MessageType.voice;
    }
    if (value.isNotEmpty && value != 'text' && value != 'conversation') {
      return MessageType.file;
    }
    return MessageType.text;
  }

  static String _pickText(Map<String, Object?> json, Object? media) {
    final mediaMap = media is Map<String, Object?> ? media : null;
    final textCandidates = [
      json['text'],
      json['body'],
      mediaMap?['caption'],
      mediaMap?['description'],
    ];
    for (final candidate in textCandidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    if (mediaMap != null) {
      final mediaName = _pickFileName(mediaMap);
      if (mediaName.isNotEmpty) return mediaName;
    }
    return '';
  }

  static String _pickMediaUrl(Object? media) {
    if (media is Map<String, Object?>) {
      final candidates = [
        media['url'],
        media['download_url'],
        media['downloadUrl'],
        media['path'],
      ];
      for (final candidate in candidates) {
        if (candidate is String && candidate.isNotEmpty) {
          return candidate;
        }
      }
    }
    return '';
  }

  static String _pickFileName(Object? media) {
    if (media is Map<String, Object?>) {
      final candidates = [
        media['file_name'],
        media['fileName'],
        media['name'],
        media['original_name'],
      ];
      for (final candidate in candidates) {
        if (candidate is String && candidate.isNotEmpty) {
          return candidate;
        }
      }
    }
    return '';
  }

  static DateTime? parseTimestamp(Object? value) {
    if (value is DateTime) return value;
    if (value is num) {
      final raw = value.toInt();
      final millis = raw < 3000000000 ? raw * 1000 : raw;
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
    }
    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    return null;
  }

  static String formatTime(DateTime? dt) {
    if (dt == null) return '';
    final hours = dt.hour.toString().padLeft(2, '0');
    final minutes = dt.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  static Duration _resolveDuration(Map<String, Object?>? media) {
    if (media == null) return Duration.zero;
    final raw = media['duration'] ?? media['seconds'];
    if (raw is num && raw > 0) {
      return Duration(seconds: raw.round());
    }
    return Duration.zero;
  }

  ChatMessage copyWith({
    String? id,
    String? text,
    String? timeLabel,
    bool? isMe,
    MessageType? type,
    String? mediaPath,
    String? fileName,
    Duration? duration,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      timeLabel: timeLabel ?? this.timeLabel,
      isMe: isMe ?? this.isMe,
      type: type ?? this.type,
      mediaPath: mediaPath ?? this.mediaPath,
      fileName: fileName ?? this.fileName,
      duration: duration ?? this.duration,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
