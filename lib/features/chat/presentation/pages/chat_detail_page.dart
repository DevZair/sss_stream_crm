import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircleAvatar, Colors, Material;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../../../../service/notification_service.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/ios_action_sheet.dart';
import '../../../../service/utils/error_messages.dart';
import '../../data/data_sources/chat_remote_data_source.dart';
import '../../domain/entities/chat_message.dart';
import '../models/chat_preview.dart';
import '../../../call/data/video_call_models.dart';
import '../../../call/data/video_call_remote_data_source.dart';
import '../../../call/presentation/pages/video_call_page.dart';

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
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  bool _isUploading = false;
  bool _isMutatingMessage = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.setCurrentChat(widget.chat.chatId);
    _recorder = AudioRecorder();
    _player = AudioPlayer();
    _initMessageStream();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    NotificationService.instance.setCurrentChat(null);
    _inputController.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? AppColors.background : AppColors.lightBackground;
    final navBg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.90)
        : CupertinoColors.systemBackground.withValues(alpha: 0.90);

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: navBg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.separator : AppColors.lightSeparator,
            width: 0.5,
          ),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.back, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        middle: GestureDetector(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: widget.chat.color,
                backgroundImage: widget.chat.avatarUrl != null
                    ? NetworkImage(widget.chat.avatarUrl!)
                    : null,
                child: widget.chat.avatarUrl != null
                    ? null
                    : Text(
                        widget.chat.initials,
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.chat.name,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textPrimary
                            : AppColors.lightTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _showCallTypePicker,
              child: const Icon(
                CupertinoIcons.phone_fill,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.only(left: 8),
              child: const Icon(
                CupertinoIcons.ellipsis_circle,
                color: AppColors.primary,
                size: 22,
              ),
              onPressed: () => _handleMore(),
            ),
          ],
        ),
      ),
      child: Column(
        children: [
          if (_isLoading)
            const Expanded(
              child: Center(child: CupertinoActivityIndicator(radius: 14)),
            )
          else if (_error != null && _messages.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            _MessagesView(
              messages: _messages,
              isDark: isDark,
              onPlayVoice: _playVoice,
              onImageTap: _openImageViewer,
              playingPath: _playingPath,
              isPlaying: _isPlaying,
              onLongPress: _handleMessageOptions,
            ),
          _InputBar(
            controller: _inputController,
            isDark: isDark,
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
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _showCallTypePicker() async {
    if (!widget.chat.canAttemptVideoCall) {
      _showToast(
        'Звонок: нужен чат с номером (от 6 цифр) или с зарегистрированным собеседником.',
      );
      return;
    }

    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Тип звонка'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'audio'),
            child: const Text('Аудиозвонок'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'video'),
            child: const Text('Видеозвонок'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
      ),
    );

    if (choice == 'audio') {
      await _startCall(isVideo: false);
    } else if (choice == 'video') {
      await _startCall(isVideo: true);
    }
  }

  Future<void> _startCall({required bool isVideo}) async {
    String? peerUid = widget.chat.directPeerUid;
    if (peerUid == null || peerUid.isEmpty) {
      final digits = widget.chat.externalContactDigits;
      if (digits != null && digits.length >= 6) {
        try {
          peerUid = await _remote.resolveRegisteredUidByPhoneDigits(digits);
        } catch (_) {
          peerUid = null;
        }
      }
    }

    if (peerUid == null || peerUid.isEmpty) {
      _showToast(
        'Этот номер ещё не зарегистрирован в приложении. Попросите собеседника войти или начните чат через поиск по логину.',
      );
      return;
    }

    final mic = await _ensurePermission(
      Permission.microphone,
      'Нужен доступ к микрофону для звонка.',
    );
    if (!mic) return;

    if (isVideo) {
      final cam = await _ensurePermission(
        Permission.camera,
        'Нужен доступ к камере для видеозвонка.',
      );
      if (!cam) return;
    }

    try {
      final room = await const VideoCallRemoteDataSource().createCall(
        sourceChatId: widget.chat.chatId,
        peerUid: peerUid,
        callType: isVideo ? callKitCallTypeVideo : callKitCallTypeAudio,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => VideoCallPage(
            callId: room.callId,
            initialChannelName: room.channelName,
            isAudioOnly: !isVideo,
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showToast(friendlyError(error));
    }
  }

  void _handleMore() async {
    await showIosActionSheet(
      context: context,
      actions: [
        IosSheetAction(
          label: 'Отключить уведомления',
          icon: CupertinoIcons.bell_slash,
          onTap: () {},
        ),
        IosSheetAction(
          label: 'Удалить чат',
          isDestructive: true,
          icon: CupertinoIcons.delete,
          onTap: _deleteChat,
        ),
      ],
    );
  }

  Future<void> _handleMessageOptions(ChatMessage message) async {
    if (_isMutatingMessage) return;
    final isMe = message.isMe;

    if (!isMe) {
      _showToast('Можно редактировать и удалять только свои сообщения.');
      return;
    }

    await showIosActionSheet(
      context: context,
      actions: [
        IosSheetAction(
          label: 'Редактировать',
          icon: CupertinoIcons.pencil,
          onTap: () => _editMessage(message),
        ),
        IosSheetAction(
          label: 'Удалить',
          isDestructive: true,
          icon: CupertinoIcons.delete,
          onTap: () => _confirmDeleteMessage(message),
        ),
      ],
    );
  }

  Future<void> _editMessage(ChatMessage message) async {
    final controller = TextEditingController(text: message.text);
    final updatedText = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Редактировать сообщение'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: controller,
            maxLines: 4,
            placeholder: 'Новый текст',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
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
    } catch (error) {
      if (mounted) _showToast(friendlyError(error));
    } finally {
      if (mounted) setState(() => _isMutatingMessage = false);
    }
  }

  void _handleAttach() {
    if (_isUploading || _isSending || _isLoading) return;
    showIosActionSheet(
      context: context,
      title: 'Прикрепить',
      actions: [
        IosSheetAction(
          label: 'Галерея',
          icon: CupertinoIcons.photo,
          onTap: _pickFromGallery,
        ),
        IosSheetAction(
          label: 'Камера',
          icon: CupertinoIcons.camera,
          onTap: _captureFromCamera,
        ),
        IosSheetAction(
          label: 'Файл',
          icon: CupertinoIcons.doc,
          onTap: _pickFile,
        ),
      ],
    );
  }

  void _initMessageStream() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    _messageSubscription = _remote
        .streamMessages(widget.chat.chatId)
        .listen(
      (items) {
        if (mounted) {
          setState(() {
            _messages = items;
            _isLoading = false;
            _error = null;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          final msg = friendlyError(error);
          if (!_isLoading && _messages.isNotEmpty) _showToast(msg);
          setState(() {
            _error = msg;
            _isLoading = false;
          });
        }
      },
    );
  }

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending || _isLoading) return;
    setState(() => _isSending = true);
    _inputController.clear();
    try {
      await _remote.sendText(chatId: widget.chat.chatId, text: text);
    } catch (error) {
      if (mounted) {
        _inputController.text = text;
        _showToast(friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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
    } catch (error) {
      if (mounted) _showToast(friendlyError(error));
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
      if (mounted) _showToast(friendlyError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDeleteMessage(ChatMessage message) async {
    if (_isMutatingMessage) return;
    final confirm = await showIosAlert<bool>(
      context: context,
      title: 'Удалить сообщение?',
      message: 'Это действие нельзя отменить.',
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Удалить'),
        ),
      ],
    );
    if (confirm != true) return;

    setState(() => _isMutatingMessage = true);
    try {
      await _remote.deleteMessage(
        chatId: widget.chat.chatId,
        messageRef: message.id,
      );
    } catch (error) {
      if (mounted) _showToast(friendlyError(error));
    } finally {
      if (mounted) setState(() => _isMutatingMessage = false);
    }
  }

  // ── Recording ──────────────────────────────────────────────────────────────

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
        if (start != null) _recordDuration = DateTime.now().difference(start);
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

  // ── Media helpers ──────────────────────────────────────────────────────────

  void _openImageViewer(String path) {
    if (path.isEmpty) return;
    final image = path.startsWith('http')
        ? Image.network(
            path,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              CupertinoIcons.photo,
              color: CupertinoColors.systemGrey,
              size: 64,
            ),
          )
        : Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              CupertinoIcons.photo,
              color: CupertinoColors.systemGrey,
              size: 64,
            ),
          );
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Container(
          color: CupertinoColors.black,
          child: SafeArea(child: InteractiveViewer(child: image)),
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
    if (photo == null || !mounted) return;

    final confirm = await showIosAlert<bool>(
      context: context,
      title: 'Отправить фото?',
      message: photo.name,
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Отправить'),
        ),
      ],
    );
    if (!mounted || confirm != true) return;
    await _uploadAndSendMedia(kind: 'image', path: photo.path);
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

  Future<void> _playVoice(String path, Duration _) async {
    if (path.isEmpty) return;
    await _player.stop();
    _playingPath = path;
    setState(() => _isPlaying = true);
    _player.onPlayerComplete.listen((_) {
      if (mounted)
        setState(() {
          _isPlaying = false;
          _playingPath = null;
        });
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

  // ── Permissions ────────────────────────────────────────────────────────────

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
        final open = await showIosAlert<bool>(
          context: context,
          title: 'Требуется разрешение',
          message: '$rationale Откройте настройки и предоставьте доступ.',
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Открыть настройки'),
            ),
          ],
        );
        if (open == true) await openAppSettings();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureMediaAccess({required String rationale}) async {
    if (Platform.isIOS) {
      return _ensurePermission(Permission.photos, rationale);
    }
    var status = await Permission.photos.status;
    if (status.isGranted) return true;
    status = await Permission.photos.request();
    if (status.isGranted) return true;
    var storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;
    storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }

  // ── Toast ──────────────────────────────────────────────────────────────────

  void _showToast(String message) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        bottom: 90,
        left: 40,
        right: 40,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceTertiary.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), entry.remove);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Messages view
// ══════════════════════════════════════════════════════════════════════════════

class _MessagesView extends StatelessWidget {
  const _MessagesView({
    required this.messages,
    required this.isDark,
    required this.onPlayVoice,
    required this.onImageTap,
    required this.playingPath,
    required this.isPlaying,
    required this.onLongPress,
  });

  final List<ChatMessage> messages;
  final bool isDark;
  final void Function(String path, Duration duration) onPlayVoice;
  final void Function(String path) onImageTap;
  final String? playingPath;
  final bool isPlaying;
  final void Function(ChatMessage message) onLongPress;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        reverse: true,
        physics: const BouncingScrollPhysics(),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[messages.length - 1 - index];

          Widget bubble = switch (message.type) {
            MessageType.voice => _VoiceBubble(
              time: message.timeLabel,
              isMe: message.isMe,
              isDark: isDark,
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
              isDark: isDark,
              onTap: () => onImageTap(message.mediaPath),
            ),
            MessageType.file => _FileBubble(message: message, isDark: isDark),
            MessageType.text => _TextBubble(
              message: message,
              isDark: isDark,
              onLongPress: () => onLongPress(message),
            ),
          };

          return _BubbleAnimator(
            key: ValueKey(message.id),
            child: GestureDetector(
              onLongPress: () => onLongPress(message),
              behavior: HitTestBehavior.translucent,
              child: bubble,
            ),
          );
        },
      ),
    );
  }
}

class _BubbleAnimator extends StatefulWidget {
  const _BubbleAnimator({required Key key, required this.child}) : super(key: key);
  final Widget child;

  @override
  State<_BubbleAnimator> createState() => _BubbleAnimatorState();
}

class _BubbleAnimatorState extends State<_BubbleAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _slide = Tween<Offset>(begin: const Offset(0, 1.0), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: widget.child,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Bubble widgets
// ══════════════════════════════════════════════════════════════════════════════

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.message,
    required this.isDark,
    required this.onLongPress,
  });

  final ChatMessage message;
  final bool isDark;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    // iMessage-style: blue for me, grey for them
    final bgColor = isMe
        ? AppColors.myBubble
        : (isDark ? AppColors.theirBubble : AppColors.theirBubbleLight);
    final textColor = isMe
        ? CupertinoColors.white
        : (isDark ? AppColors.textPrimary : AppColors.lightTextPrimary);
    final timeColor = isMe
        ? CupertinoColors.white.withOpacity(0.75)
        : (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(
            top: 2,
            bottom: 2,
            left: isMe ? 60 : 0,
            right: isMe ? 0 : 60,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isMe ? 20 : 5),
              bottomRight: Radius.circular(isMe ? 5 : 20),
            ),
          ),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: TextStyle(color: textColor, fontSize: 16, height: 1.35),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.timeLabel,
                    style: TextStyle(color: timeColor, fontSize: 11),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      CupertinoIcons.checkmark_alt_circle_fill,
                      size: 13,
                      color: CupertinoColors.white.withOpacity(0.75),
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
  const _ImageBubble({
    required this.message,
    required this.isDark,
    required this.onTap,
  });

  final ChatMessage message;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 5),
      bottomRight: Radius.circular(isMe ? 5 : 18),
    );
    final overlayColor = isDark
        ? AppColors.theirBubble
        : AppColors.theirBubbleLight;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 2,
          bottom: 2,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        decoration: BoxDecoration(
          color: overlayColor,
          borderRadius: borderRadius,
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
                        width: 240,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 240,
                          height: 180,
                          child: Icon(
                            CupertinoIcons.photo,
                            color: CupertinoColors.systemGrey,
                            size: 48,
                          ),
                        ),
                      )
                    : Image.file(
                        File(message.mediaPath),
                        width: 240,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 240,
                          height: 180,
                          child: Icon(
                            CupertinoIcons.photo,
                            color: CupertinoColors.systemGrey,
                            size: 48,
                          ),
                        ),
                      ),
              ),
            if (message.text.isNotEmpty || true)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  message.timeLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FileBubble extends StatelessWidget {
  const _FileBubble({required this.message, required this.isDark});

  final ChatMessage message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final bgColor = isMe
        ? AppColors.myBubble
        : (isDark ? AppColors.theirBubble : AppColors.theirBubbleLight);
    final textColor = isMe
        ? CupertinoColors.white
        : (isDark ? AppColors.textPrimary : AppColors.lightTextPrimary);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 2,
          bottom: 2,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 5),
            bottomRight: Radius.circular(isMe ? 5 : 18),
          ),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.doc_fill, color: textColor, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.fileName.isNotEmpty ? message.fileName : 'Файл',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message.timeLabel,
                    style: TextStyle(
                      color: textColor.withOpacity(0.7),
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
    required this.isDark,
    required this.onPlay,
    required this.mediaPath,
    this.duration = Duration.zero,
    this.isPlaying = false,
  });

  final String time;
  final bool isMe;
  final bool isDark;
  final VoidCallback onPlay;
  final Duration duration;
  final bool isPlaying;
  final String mediaPath;

  @override
  Widget build(BuildContext context) {
    final bgColor = isMe
        ? AppColors.myBubble
        : (isDark ? AppColors.theirBubble : AppColors.theirBubbleLight);
    final fgColor = isMe
        ? CupertinoColors.white
        : (isDark ? AppColors.textPrimary : AppColors.lightTextPrimary);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 2,
          bottom: 2,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 5),
            bottomRight: Radius.circular(isMe ? 5 : 20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: onPlay,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: fgColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  color: fgColor,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _WaveformBars(
              bars: _barsFromSeed(mediaPath.hashCode),
              color: fgColor.withOpacity(0.7),
              height: 24,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: fgColor.withOpacity(0.9),
                    fontSize: 11,
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    color: fgColor.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  List<double> _barsFromSeed(int seed, {int count = 24}) {
    final rng = Random(seed);
    return List<double>.generate(count, (_) => 4 + rng.nextInt(14).toDouble());
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Input bar
// ══════════════════════════════════════════════════════════════════════════════

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.isDark,
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
  final bool isDark;
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
    if (!widget.isRecording && oldWidget.isRecording) _resetGestures();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _resetGestures() {
    _didCancel = false;
  }

  String _recordLabel() {
    final m = widget.recordDuration.inMinutes.remainder(60);
    final s = widget.recordDuration.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = widget.isDark
        ? AppColors.surfaceSecondary
        : AppColors.lightSurface;
    final borderColor = widget.isDark
        ? AppColors.separator
        : AppColors.lightSeparator;
    final secondaryText = widget.isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;
    final textColor = widget.isDark
        ? AppColors.textPrimary
        : AppColors.lightTextPrimary;

    return Container(
      color: surfaceColor,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: surfaceColor,
            border: Border(top: BorderSide(color: borderColor, width: 0.5)),
          ),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (context, value, _) {
              final canSend = value.text.trim().isNotEmpty && !widget.isBusy;

              if (widget.isRecording) {
                return _buildRecordingBar(secondaryText);
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attach
                  CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minSize: 36,
                    child: Icon(
                      CupertinoIcons.paperclip,
                      color: widget.isBusy ? secondaryText : AppColors.primary,
                      size: 24,
                    ),
                    onPressed: widget.isBusy ? null : widget.onAttach,
                  ),
                  // Text field
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 36,
                        maxHeight: 120,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? AppColors.surfaceTertiary
                            : AppColors.lightSurfaceSecondary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor, width: 0.5),
                      ),
                      child: CupertinoTextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 5,
                        placeholder: 'Message',
                        placeholderStyle: TextStyle(
                          color: secondaryText,
                          fontSize: 16,
                        ),
                        style: TextStyle(color: textColor, fontSize: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: const BoxDecoration(),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) {
                          if (canSend) widget.onSend();
                        },
                      ),
                    ),
                  ),
                  // Mic / Send
                  CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minSize: 36,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: canSend
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        canSend ? CupertinoIcons.arrow_up : CupertinoIcons.mic_fill,
                        color: canSend ? CupertinoColors.white : AppColors.primary,
                        size: 18,
                      ),
                    ),
                    onPressed: widget.isBusy
                        ? null
                        : () {
                            if (canSend) {
                              widget.onSend();
                            } else {
                              widget.onRecordStart();
                            }
                          },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingBar(Color secondaryText) {
    return Row(
      children: [
        // Cancel
        CupertinoButton(
          padding: const EdgeInsets.all(6),
          minSize: 36,
          child: const Icon(
            CupertinoIcons.xmark_circle_fill,
            color: AppColors.error,
            size: 28,
          ),
          onPressed: () {
            _didCancel = true;
            widget.onRecordCancel();
            setState(_resetGestures);
          },
        ),
        // Timer
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _recordLabel(),
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Slide to cancel',
                style: TextStyle(color: secondaryText, fontSize: 13),
              ),
            ],
          ),
        ),
        // Send
        CupertinoButton(
          padding: const EdgeInsets.all(6),
          minSize: 36,
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.arrow_up,
              color: CupertinoColors.white,
              size: 18,
            ),
          ),
          onPressed: () {
            if (!_didCancel) widget.onRecordSend();
          },
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Waveform bars
// ══════════════════════════════════════════════════════════════════════════════

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({
    required this.bars,
    required this.color,
    this.height = 24,
  });

  final List<double> bars;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars
            .map(
              (val) => Container(
                width: 2.5,
                height: min(val, height),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
