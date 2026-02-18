import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../service/utils/error_messages.dart';
import '../../data/data_sources/chat_remote_data_source.dart';
import '../../domain/entities/chat_message.dart';
import '../models/chat_preview.dart';

class ChatDetailPage extends StatefulWidget {
  const ChatDetailPage({super.key, required this.chat});

  final ChatPreview chat;

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final ChatRemoteDataSource _remote = const ChatRemoteDataSource();
  final TextEditingController _inputController = TextEditingController();
  List<ChatMessage> _messages = const [];
  final ImagePicker _imagePicker = ImagePicker();
  late final AudioRecorder _recorder;
  late final AudioPlayer _player;
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  DateTime? _recordStart;
  String? _recordPath;
  String? _playingPath;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploading = false;
  bool _isMutatingMessage = false;
  String? _error;

  Future<void> _handleMessageOptions(ChatMessage message) async {
    if (_isMutatingMessage) return;

    final isMe = message.isMe;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMe)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.white),
                title: const Text(
                  'Редактировать',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text(
                'Удалить',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'delete') {
      await _confirmDeleteMessage(message);
      return;
    }

    if (action == 'edit' && isMe) {
      final controller = TextEditingController(text: message.text);
      final updatedText = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Редактировать сообщение'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Новый текст'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );
      if (updatedText == null ||
          updatedText.isEmpty ||
          updatedText == message.text)
        return;

      setState(() => _isMutatingMessage = true);
      try {
        await _remote.updateMessage(
          chatId: widget.chat.chatId,
          messageRef: message.id,
          payload: {'text': updatedText},
        );
        await _loadMessages(showLoader: false);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
        }
      } finally {
        if (mounted) setState(() => _isMutatingMessage = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    _player = AudioPlayer();
    _loadMessages();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  void _handleAttach() {
    if (_isUploading || _isSending || _isLoading) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: Colors.white),
              title: const Text(
                'Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
              ),
              title: const Text(
                'Camera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _captureFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.white),
              title: const Text('File', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadMessages({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final items = await _remote.fetchMessages(widget.chat.chatId);
      if (mounted) {
        setState(() => _messages = items);
      }
    } catch (error) {
      if (mounted) {
        final message = friendlyError(error);
        if (!showLoader && _messages.isNotEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
        setState(() => _error = message);
      }
    } finally {
      if (mounted && showLoader) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    if (_isSending || _isLoading) return;

    setState(() => _isSending = true);
    try {
      await _remote.sendText(chatId: widget.chat.chatId, text: text);
      _inputController.clear();
      await _loadMessages(showLoader: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _handleMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.notifications_off_outlined,
                color: Colors.white,
              ),
              title: const Text(
                'Mute chat',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text(
                'Delete chat',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteChat();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadAndSendMedia({
    required String kind,
    required String path,
    String? caption,
  }) async {
    if (_isUploading || path.isEmpty) return;
    setState(() => _isUploading = true);
    try {
      final captionValue = caption?.trim();
      final upload = await _remote.uploadFile(kind: kind, filePath: path);
      await _remote.sendMedia(
        chatId: widget.chat.chatId,
        upload: upload,
        caption: captionValue?.isEmpty == true ? null : captionValue,
      );
      _inputController.clear();
      await _loadMessages(showLoader: false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteChat() async {
    setState(() => _isLoading = true);
    try {
      await _remote.deleteChat(widget.chat.chatId);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isSending || _isUploading || _isLoading) return;

    final granted = await _ensurePermission(
      Permission.microphone,
      'Нужен доступ к микрофону для записи голосовых.',
    );
    if (!granted) return;
    if (!await _recorder.hasPermission()) return;

    final path =
        '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    setState(() {
      _isRecording = true;
      _recordDuration = Duration.zero;
      _recordStart = DateTime.now();
      _recordPath = path;
    });
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
    } catch (_) {
      _recordTimer?.cancel();
      setState(() {
        _isRecording = false;
        _recordDuration = Duration.zero;
        _recordStart = null;
        _recordPath = null;
      });
      return;
    }
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        final start = _recordStart;
        if (start != null) {
          _recordDuration = DateTime.now().difference(start);
        }
      });
    });
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    final path = await _recorder.stop();
    _recordTimer?.cancel();
    setState(() {
      _isRecording = false;
      _recordDuration = Duration.zero;
      _recordStart = null;
    });
    final filePath = path ?? _recordPath;
    if (filePath != null && filePath.isNotEmpty) {
      try {
        await File(filePath).delete();
      } catch (_) {}
    }
    _recordPath = null;
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;
    final path = await _recorder.stop();
    _recordTimer?.cancel();
    setState(() {
      _isRecording = false;
      _recordDuration = Duration.zero;
      _recordStart = null;
    });
    final filePath = path ?? _recordPath ?? '';
    _recordPath = null;
    if (filePath.isEmpty) return;

    await _uploadAndSendMedia(kind: 'audio', path: filePath);
  }

  void _openImageViewer(String path) {
    if (path.isEmpty) return;
    final errorIcon = Icon(
      Icons.broken_image,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
      size: 64,
    );
    final image = path.startsWith('http')
        ? Image.network(
            path,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => errorIcon,
          )
        : Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => errorIcon,
          );
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(child: image),
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    final granted = await _ensureMediaAccess(
      rationale: 'Нужен доступ к галерее, чтобы выбрать фото.',
    );
    if (!granted) return;

    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    await _uploadAndSendMedia(kind: 'image', path: image.path);
  }

  Future<void> _captureFromCamera() async {
    final granted = await _ensurePermission(
      Permission.camera,
      'Нужен доступ к камере, чтобы сделать фото.',
    );
    if (!granted) return;

    final photo = await _imagePicker.pickImage(source: ImageSource.camera);
    if (photo == null) return;
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отправить фото?'),
        content: Text(photo.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true) {
      await _uploadAndSendMedia(
        kind: 'image',
        path: photo.path,
        caption: _inputController.text.trim().isEmpty
            ? null
            : _inputController.text.trim(),
      );
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path != null && file.path!.isNotEmpty) {
      await _uploadAndSendMedia(
        kind: 'document',
        path: file.path!,
        caption: _inputController.text.trim(),
      );
    }
  }

  Future<bool> _ensurePermission(
    Permission permission,
    String rationale,
  ) async {
    try {
      var status = await permission.status;
      if (status.isGranted || status.isLimited) return true;

      if (status.isDenied || status.isRestricted) {
        status = await permission.request();
        if (status.isGranted || status.isLimited) return true;
      }

      if (status.isPermanentlyDenied && mounted) {
        final shouldOpen = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Требуется разрешение'),
            content: Text(
              '$rationale Откройте настройки и предоставьте доступ.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Открыть настройки'),
              ),
            ],
          ),
        );
        if (shouldOpen == true) {
          await openAppSettings();
        }
      } else if (mounted && !status.isGranted && !status.isLimited) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(rationale)));
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при запросе разрешения: $rationale')),
        );
      }
      return false;
    }
  }

  Future<bool> _ensureMediaAccess({required String rationale}) async {
    try {
      // Для iOS используем Permission.photos для доступа к фото библиотеке
      if (Platform.isIOS) {
        var status = await Permission.photos.status;
        if (status.isGranted || status.isLimited) return true;

        status = await Permission.photos.request();
        if (status.isGranted || status.isLimited) return true;

        if (status.isPermanentlyDenied && mounted) {
          final shouldOpen = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Требуется разрешение'),
              content: Text(
                '$rationale Откройте настройки и предоставьте доступ к фото.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Открыть настройки'),
                ),
              ],
            ),
          );
          if (shouldOpen == true) {
            await openAppSettings();
          }
        } else if (mounted && !status.isGranted && !status.isLimited) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(rationale)));
        }
        return false;
      }

      // Для Android: Try modern media permission (Android 13+).
      var status = await Permission.photos.status;
      if (status.isGranted) return true;
      status = await Permission.photos.request();
      if (status.isGranted) return true;

      // Fallback to legacy storage on older Android.
      var storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) return true;
      storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      if (status.isPermanentlyDenied && mounted) {
        final shouldOpen = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Требуется разрешение'),
            content: Text(
              '$rationale Откройте настройки и предоставьте доступ.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Открыть настройки'),
              ),
            ],
          ),
        );
        if (shouldOpen == true) {
          await openAppSettings();
        }
      } else if (mounted && !status.isGranted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(rationale)));
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при запросе разрешения: $rationale')),
        );
      }
      return false;
    }
  }

  Future<void> _playVoice(String path, Duration _) async {
    if (path.isEmpty) return;
    await _player.stop();
    _playingPath = path;
    setState(() => _isPlaying = true);

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playingPath = null;
        });
      }
    });

    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        setState(() {
          _isPlaying = false;
          _playingPath = null;
        });
      }
    });

    final source = path.startsWith('http')
        ? UrlSource(path)
        : DeviceFileSource(path);
    await _player.play(source, mode: PlayerMode.mediaPlayer);
  }

  Future<void> _confirmDeleteMessage(ChatMessage message) async {
    if (_isMutatingMessage) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isMutatingMessage = true);
    try {
      await _remote.deleteMessage(
        chatId: widget.chat.chatId,
        messageRef: message.id,
      );
      await _loadMessages(showLoader: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) setState(() => _isMutatingMessage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: Theme.of(context).brightness == Brightness.dark
                ? const [Color(0xFF1D0C6A), Color(0xFF0E0A2E)]
                : const [Color(0xFFF7FAFF), Color(0xFFE9F0FF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _AppBar(chat: widget.chat, onMore: () => _handleMore(context)),
              const SizedBox(height: 12),
              if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              else if (_error != null && _messages.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                _MessagesView(
                  messages: _messages,
                  onPlayVoice: _playVoice,
                  onImageTap: _openImageViewer,
                  playingPath: _playingPath,
                  isPlaying: _isPlaying,
                  onDelete: _handleMessageOptions,
                ),
              _InputBar(
                controller: _inputController,
                onSend: _handleSend,
                onAttach: _handleAttach,
                onRecordStart: _startRecording,
                onRecordCancel: _cancelRecording,
                onRecordSend: _stopRecordingAndSend,
                isRecording: _isRecording,
                recordDuration: _recordDuration,
                isBusy: _isSending || _isUploading || _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppBar extends StatelessWidget {
  const _AppBar({required this.chat, required this.onMore});

  final ChatPreview chat;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back_ios, color: iconColor),
          ),
          CircleAvatar(
            radius: 22,
            backgroundColor: chat.color,
            child: Text(
              chat.initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  chat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: iconColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'Typing...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: iconColor.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onMore,
            icon: Icon(Icons.more_vert, color: iconColor),
          ),
        ],
      ),
    );
  }
}

class _MessagesView extends StatelessWidget {
  const _MessagesView({
    required this.messages,
    required this.onPlayVoice,
    required this.onImageTap,
    required this.playingPath,
    required this.isPlaying,
    required this.onDelete,
  });

  final List<ChatMessage> messages;
  final void Function(String path, Duration duration) onPlayVoice;
  final void Function(String path) onImageTap;
  final String? playingPath;
  final bool isPlaying;
  final void Function(ChatMessage message) onDelete;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        reverse: true,
        physics: const BouncingScrollPhysics(),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[messages.length - 1 - index];
          final bubble = switch (message.type) {
            MessageType.voice => _VoiceBubble(
              time: message.timeLabel,
              isMe: message.isMe,
              mediaPath: message.mediaPath,
              isPlaying:
                  isPlaying &&
                  message.mediaPath.isNotEmpty &&
                  message.mediaPath == playingPath,
              duration: message.duration,
              onPlay: () => onPlayVoice(message.mediaPath, message.duration),
            ),
            MessageType.image => _ImageBubble(
              message: message,
              onTap: () => onImageTap(message.mediaPath),
            ),
            MessageType.file => _FileBubble(message: message),
            MessageType.text => _TextBubble(
              message: message,
              onLongPress: () => onDelete(message),
            ),
          };

          return GestureDetector(
            onLongPress: () => onDelete(message),
            behavior: HitTestBehavior.translucent,
            child: bubble,
          );
        },
      ),
    );
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.message, required this.onLongPress});

  final ChatMessage message;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final bgColor = isMe ? const Color(0xFF3B62F0) : const Color(0xFF233653);
    final textColor = Colors.white;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 6),
              bottomRight: Radius.circular(isMe ? 6 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    message.timeLabel,
                    style: TextStyle(
                      color: textColor.withOpacity(0.8),
                      fontSize: 11,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.done_all,
                      size: 16,
                      color: Color(0xFFD6E8FF),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.message, required this.onTap});

  final ChatMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 6),
      bottomRight: Radius.circular(isMe ? 6 : 18),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: borderRadius,
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (message.mediaPath.isNotEmpty)
              GestureDetector(
                onTap: onTap,
                child: message.mediaPath.startsWith('http')
                    ? Image.network(
                        message.mediaPath,
                        width: 260,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 260,
                          height: 180,
                          color: Colors.black26,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image,
                            color: Colors.white70,
                          ),
                        ),
                      )
                    : Image.file(
                        File(message.mediaPath),
                        width: 260,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 260,
                          height: 180,
                          color: Colors.black26,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image,
                            color: Colors.white70,
                          ),
                        ),
                      ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                  if (message.text.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    message.timeLabel,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileBubble extends StatelessWidget {
  const _FileBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 6),
            bottomRight: Radius.circular(isMe ? 6 : 18),
          ),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            const Icon(Icons.insert_drive_file, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.fileName.isNotEmpty ? message.fileName : 'Файл',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.timeLabel,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({
    required this.time,
    required this.isMe,
    required this.onPlay,
    required this.mediaPath,
    this.duration = Duration.zero,
    this.isPlaying = false,
  });

  final String time;
  final bool isMe;
  final VoidCallback onPlay;
  final Duration duration;
  final bool isPlaying;
  final String mediaPath;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMe
        ? const Color(0xFF3B62F0)
        : const Color(0xFF233653);
    final playButtonColor = Colors.white.withOpacity(0.14);
    final contentColor = Colors.white.withOpacity(0.88);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onPlay,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: playButtonColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _WaveformBars(
              bars: _barsFromSeed(mediaPath.hashCode),
              color: contentColor,
              height: 28,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDuration(duration),
                  style: TextStyle(color: contentColor, fontSize: 11),
                ),
                Text(time, style: TextStyle(color: contentColor, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  List<double> _barsFromSeed(int seed, {int count = 30}) {
    final random = Random(seed);
    return List<double>.generate(
      count,
      (_) => 6 + random.nextInt(16).toDouble(),
    );
  }
}

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onRecordStart,
    required this.onRecordCancel,
    required this.onRecordSend,
    required this.isRecording,
    required this.recordDuration,
    this.isBusy = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordCancel;
  final VoidCallback onRecordSend;
  final bool isRecording;
  final Duration recordDuration;
  final bool isBusy;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  double _cancelDrag = 0;
  double _lockDrag = 0;
  bool _isLocked = false;
  bool _didCancel = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isRecording && oldWidget.isRecording) {
      _resetGestures();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _resetGestures() {
    _cancelDrag = 0;
    _lockDrag = 0;
    _isLocked = false;
    _didCancel = false;
  }

  void _handleStartRecording() {
    if (widget.isBusy || widget.isRecording) return;
    setState(_resetGestures);
    widget.onRecordStart();
  }

  void _handleSendRecording() {
    if (!widget.isRecording || _didCancel) return;
    widget.onRecordSend();
  }

  void _handleCancelRecording() {
    if (!widget.isRecording) return;
    _didCancel = true;
    widget.onRecordCancel();
    setState(_resetGestures);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!widget.isRecording) return;
    final dx = details.delta.dx;
    final dy = details.delta.dy;
    setState(() {
      _cancelDrag = (_cancelDrag + dx).clamp(-160, 10);
      if (!_isLocked) {
        _lockDrag += dy;
        if (_lockDrag < -32) {
          _isLocked = true;
        }
      }
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!widget.isRecording) return;
    if (_cancelDrag <= -110 && !_isLocked) {
      _handleCancelRecording();
      return;
    }
    setState(() {
      _cancelDrag = 0;
      _lockDrag = 0;
    });
  }

  String _recordDurationLabel() {
    final minutes = widget.recordDuration.inMinutes.remainder(60);
    final seconds = widget.recordDuration.inSeconds.remainder(60);
    final tenths = (widget.recordDuration.inMilliseconds % 1000) ~/ 100;
    return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')},$tenths';
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final canSendText = value.text.trim().isNotEmpty && !widget.isBusy;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: widget.isRecording
                ? _buildRecordingLayout(onSurface)
                : _buildComposerLayout(onSurface, canSendText),
          );
        },
      ),
    );
  }

  Widget _buildComposerLayout(Color onSurface, bool canSendText) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2C3D) : const Color(0xFFEFF3FA);
    final secondary = isDark
        ? const Color(0xFF1A2433)
        : const Color(0xFFE1E7F2);

    return Container(
      key: const ValueKey('composer'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [surface, secondary],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _IconTap(
            icon: Icons.emoji_emotions_outlined,
            color: onSurface.withOpacity(0.72),
            onTap: widget.isBusy
                ? null
                : () {
                    _focusNode.requestFocus();
                  },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              style: TextStyle(color: onSurface),
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              enabled: !widget.isBusy,
              decoration: InputDecoration.collapsed(
                hintText: 'Message',
                hintStyle: TextStyle(color: onSurface.withOpacity(0.55)),
              ),
              onSubmitted: (_) {
                if (canSendText) widget.onSend();
              },
            ),
          ),
          const SizedBox(width: 10),
          _IconTap(
            icon: Icons.attach_file,
            color: onSurface.withOpacity(0.72),
            onTap: widget.isBusy ? null : widget.onAttach,
          ),
          const SizedBox(width: 6),
          _buildMicOrSendButton(onSurface, canSendText),
        ],
      ),
    );
  }

  Widget _buildMicOrSendButton(Color onSurface, bool canSendText) {
    final icon = canSendText ? Icons.send_rounded : Icons.mic_none_rounded;
    final bgColor = canSendText
        ? AppColors.primary
        : Colors.white.withOpacity(0.05);
    final fgColor = canSendText ? Colors.white : onSurface.withOpacity(0.85);

    return GestureDetector(
      onTap: widget.isBusy
          ? null
          : () {
              if (canSendText) {
                widget.onSend();
              } else if (widget.isRecording) {
                _handleSendRecording();
              } else {
                _handleStartRecording();
              }
            },
      onLongPressStart: widget.isBusy || canSendText
          ? null
          : (_) => _handleStartRecording(),
      onLongPressEnd: widget.isBusy || canSendText
          ? null
          : (_) {
              if (_isLocked) return;
              _handleSendRecording();
            },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, color: fgColor, size: 22),
      ),
    );
  }

  Widget _buildRecordingLayout(Color onSurface) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1F2C3D) : const Color(0xFFE9EEF7);
    final sliderTextColor = Color.lerp(
      onSurface.withOpacity(0.78),
      Colors.redAccent,
      min(_cancelDrag.abs() / 120, 1),
    );

    return Column(
      key: const ValueKey('recording'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onPanUpdate: _handlePanUpdate,
                onPanEnd: _handlePanEnd,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        base,
                        isDark ? base.withOpacity(0.92) : Colors.white,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _recordDurationLabel(),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Transform.translate(
                          offset: Offset(_cancelDrag, 0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 16,
                                color: sliderTextColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Slide to cancel',
                                style: TextStyle(
                                  color: sliderTextColor,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _isLocked ? 1 : 0.4,
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 2,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.22),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _buildRecordingMic(),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: min(widget.recordDuration.inMilliseconds / 45000, 1),
            minHeight: 3,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingMic() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (!_isLocked)
          const Positioned(top: -44, right: 0, child: _LockHint()),
        GestureDetector(
          onTap: widget.isBusy ? null : _handleSendRecording,
          onLongPressMoveUpdate: (details) {
            if (!widget.isRecording) return;
            final dx = details.offsetFromOrigin.dx;
            final dy = details.offsetFromOrigin.dy;
            setState(() {
              _cancelDrag = dx.clamp(-160, 10);
              if (!_isLocked && dy < -32) {
                _isLocked = true;
              }
            });
            if (_cancelDrag <= -110 && !_isLocked) {
              _handleCancelRecording();
            }
          },
          onLongPressEnd: widget.isBusy
              ? null
              : (_) {
                  if (_isLocked || _didCancel) return;
                  _handleSendRecording();
                },
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFF2BB7E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              _isLocked ? Icons.send_rounded : Icons.mic_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
        if (_isLocked)
          Positioned(
            bottom: -18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: const Text(
                'Locked',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(onTap == null ? 0.04 : 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: onTap == null ? color.withOpacity(0.4) : color,
        ),
      ),
    );
  }
}

class _LockHint extends StatelessWidget {
  const _LockHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 16),
          SizedBox(width: 6),
          Text(
            'Slide up to lock recording',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({
    required this.bars,
    required this.color,
    this.height = 26,
  });

  final List<double> bars;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        const double barWidth = 3;
        const double barSpacing = 2;
        final int maxBars = availableWidth.isFinite
            ? max(4, (availableWidth / (barWidth + barSpacing)).floor())
            : bars.length;

        final List<double> visibleBars = (bars.isEmpty ? [height / 2] : bars)
            .take(maxBars)
            .toList();

        return SizedBox(
          height: height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: visibleBars
                .map(
                  (value) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: barSpacing / 2,
                    ),
                    child: Container(
                      width: barWidth,
                      height: min(value, height),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}
