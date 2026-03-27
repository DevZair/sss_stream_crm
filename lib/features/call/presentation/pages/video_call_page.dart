import 'dart:async';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectycube_flutter_call_kit/connectycube_flutter_call_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/constants/agora_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/video_call_models.dart';
import '../../data/video_call_remote_data_source.dart';
import '../../domain/agora_uid.dart';
import '../../services/video_call_lifecycle.dart';
import '../../utils/agora_call_extras.dart';

class VideoCallPage extends StatefulWidget {
  const VideoCallPage({
    super.key,
    required this.callId,
    this.initialChannelName,
    this.isAudioOnly = false,
  });

  final String callId;
  final String? initialChannelName;

  /// Аудиозвонок (без камеры Agora).
  final bool isAudioOnly;

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  final _callData = const VideoCallRemoteDataSource();
  RtcEngine? _engine;
  late final RtcEngineEventHandler _eventHandler;

  String? _channelName;
  int _localAgoraUid = 0;
  bool _joined = false;
  String? _errorMessage;
  final Set<int> _remoteUids = {};
  StreamSubscription<VideoCallRoom?>? _roomSub;
  List<String> _firebaseParticipants = const [];
  bool _muted = false;
  bool _videoOff = false;
  bool _bootstrapStarted = false;
  Timer? _callDurationTimer;
  int _callElapsedSeconds = 0;
  QualityType _uplinkQuality = QualityType.qualityUnknown;

  @override
  void initState() {
    super.initState();
    VideoCallLifecycle.isInRoom = true;
    _channelName = widget.initialChannelName?.trim().isNotEmpty == true
        ? widget.initialChannelName
        : null;
    _eventHandler = RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        if (mounted) {
          setState(() {
            _joined = true;
            _callElapsedSeconds = 0;
          });
          _startCallDurationTimer();
        }
      },
      onLeaveChannel: (RtcConnection connection, RtcStats stats) {
        _stopCallDurationTimer();
      },
      onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        if (mounted) {
          setState(() => _remoteUids.add(remoteUid));
        }
      },
      onUserOffline: (
        RtcConnection connection,
        int remoteUid,
        UserOfflineReasonType reason,
      ) {
        if (mounted) {
          setState(() => _remoteUids.remove(remoteUid));
        }
      },
      onNetworkQuality: (
        RtcConnection connection,
        int remoteUid,
        QualityType txQuality,
        QualityType rxQuality,
      ) {
        // remoteUid == 0 — статистика локального пользователя (аплинк).
        if (remoteUid == 0 && mounted) {
          setState(() => _uplinkQuality = txQuality);
        }
      },
      onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
        debugPrint(
          'Agora: токен скоро истечёт — для продакшена обновляйте с бэкенда.',
        );
      },
      onError: (ErrorCodeType err, String msg) {
        debugPrint('Agora onError: $err $msg');
      },
    );

    _roomSub = _callData.watchCall(widget.callId).listen((room) {
      if (!mounted) return;
      if (room == null) {
        _leaveAndPop();
        return;
      }
      setState(() {
        _firebaseParticipants = room.participantIds;
        _channelName ??= room.channelName;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _bootstrapStarted) return;
      _bootstrapStarted = true;
      unawaited(_bootstrap());
    });
  }

  void _startCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _callElapsedSeconds += 1);
    });
  }

  void _stopCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = null;
  }

  Future<void> _bootstrap() async {
    final appId = AgoraConstants.appId.trim();
    if (appId.isEmpty) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Не задан AGORA_APP_ID. Запустите приложение с '
              '--dart-define=AGORA_APP_ID=...';
        });
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Пользователь не авторизован.';
        });
      }
      return;
    }

    final channel = _channelName;
    if (channel == null || channel.isEmpty) {
      final room = await _callData.getActiveCall(widget.callId);
      if (!mounted) return;
      if (room == null) {
        setState(() {
          _errorMessage = 'Звонок завершён или недоступен.';
        });
        return;
      }
      _channelName = room.channelName;
    }

    final mic = await _ensurePermission(
      Permission.microphone,
      'Нужен доступ к микрофону.',
    );
    if (!mic) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Нужен доступ к микрофону для звонка.';
        });
      }
      return;
    }

    if (!widget.isAudioOnly) {
      final cam = await _ensurePermission(
        Permission.camera,
        'Нужен доступ к камере.',
      );
      if (!cam) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Нет разрешений для видеозвонка.';
          });
        }
        return;
      }
    }

    _localAgoraUid = firebaseUidToAgoraUid(user.uid);

    final engine = createAgoraRtcEngine();
    await engine.initialize(RtcEngineContext(appId: appId));
    engine.registerEventHandler(_eventHandler);

    if (widget.isAudioOnly) {
      await engine.enableAudio();
    } else {
      await engine.enableVideo();
      await engine.startPreview();
    }

    final token = AgoraConstants.rtcToken;

    try {
      await engine.joinChannel(
        token: token,
        channelId: _channelName!,
        uid: _localAgoraUid,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          publishCameraTrack: !widget.isAudioOnly,
          autoSubscribeAudio: true,
          autoSubscribeVideo: !widget.isAudioOnly,
        ),
      );
    } on AgoraRtcException catch (e) {
      debugPrint('joinChannel: $e');
      await engine.leaveChannel();
      await engine.release();
      if (mounted) {
        setState(() {
          _errorMessage =
              'Не удалось подключиться (${e.code}). '
              'Проверьте App ID / токен Agora.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _engine = engine);
    } else {
      await engine.leaveChannel();
      await engine.release();
    }
  }

  Future<bool> _ensurePermission(
    Permission permission,
    String rationale,
  ) async {
    var status = await permission.status;
    if (status.isGranted || status.isLimited) return true;
    status = await permission.request();
    if (status.isGranted || status.isLimited) return true;
    if (status.isPermanentlyDenied && mounted) {
      final open = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Разрешение'),
          content: Text(
            '$rationale Откройте настройки.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Настройки'),
            ),
          ],
        ),
      );
      if (open == true) await openAppSettings();
    }
    return false;
  }

  Future<void> _leaveAndPop() async {
    await _disposeEngine();
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  Future<void> _hangUp() async {
    try {
      await ConnectycubeFlutterCallKit.reportCallEnded(
        sessionId: widget.callId,
      );
      await ConnectycubeFlutterCallKit.clearCallData(sessionId: widget.callId);
    } catch (_) {}
    try {
      await _callData.endCall(widget.callId);
    } on FirebaseException catch (e) {
      debugPrint('endCall: $e');
    }
    await _leaveAndPop();
  }

  Future<void> _disposeEngine() async {
    _stopCallDurationTimer();
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      try {
        await engine.leaveChannel();
      } catch (_) {}
      try {
        await engine.release();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _stopCallDurationTimer();
    _roomSub?.cancel();
    unawaited(_disposeEngine());
    VideoCallLifecycle.isInRoom = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final fg = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;

    if (_errorMessage != null) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(widget.isAudioOnly ? 'Аудиозвонок' : 'Видеозвонок'),
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: const Icon(CupertinoIcons.xmark, color: AppColors.primary),
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: fg),
            ),
          ),
        ),
      );
    }

    final engine = _engine;
    final channel = _channelName ?? '';

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF1C1C1E).withValues(alpha: 0.92),
        middle: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _joined ? 'В эфире' : 'Подключение…',
              style: const TextStyle(
                color: CupertinoColors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            if (_joined) ...[
              const SizedBox(height: 2),
              Text(
                formatCallDurationMmSs(_callElapsedSeconds),
                style: TextStyle(
                  color: CupertinoColors.white.withValues(alpha: 0.72),
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _hangUp,
          child: const Icon(CupertinoIcons.phone_down_fill, color: Colors.red),
        ),
        trailing: _joined
            ? CupertinoButton(
                padding: const EdgeInsets.only(right: 8),
                onPressed: () {
                  showCupertinoDialog<void>(
                    context: context,
                    builder: (ctx) => CupertinoAlertDialog(
                      title: const Text('Качество сети'),
                      content: Text(agoraUplinkQualityLabel(_uplinkQuality)),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: agoraUplinkQualityColor(_uplinkQuality),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: agoraUplinkQualityColor(
                              _uplinkQuality,
                            ).withValues(alpha: 0.45),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      CupertinoIcons.wifi,
                      size: 18,
                      color: agoraUplinkQualityColor(_uplinkQuality),
                    ),
                  ],
                ),
              )
            : null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_firebaseParticipants.length} участн.',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildVideoGrid(engine, channel)),
            _toolbar(engine),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoGrid(RtcEngine? engine, String channel) {
    if (engine == null) {
      return const Center(
        child: CupertinoActivityIndicator(
          color: CupertinoColors.white,
          radius: 16,
        ),
      );
    }

    final remotes = _remoteUids.toList()..sort();
    final connection = RtcConnection(
      channelId: channel,
      localUid: _localAgoraUid,
    );
    const pad = 8.0;

    if (remotes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(pad),
        child: _videoShell(_localView(engine)),
      );
    }

    // Идея раскладок: SurajLad/VideoCall-App-Flutter (1:1 — два полуэкрана и т.д.)
    if (remotes.length == 1) {
      return Padding(
        padding: const EdgeInsets.all(pad),
        child: Column(
          children: [
            Expanded(
              child: _videoShell(
                _remoteAgoraView(engine, remotes.single, connection),
              ),
            ),
            const SizedBox(height: pad),
            Expanded(child: _videoShell(_localView(engine))),
          ],
        ),
      );
    }

    if (remotes.length == 2) {
      return Padding(
        padding: const EdgeInsets.all(pad),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _videoShell(
                      _remoteAgoraView(engine, remotes[0], connection),
                    ),
                  ),
                  const SizedBox(width: pad),
                  Expanded(
                    child: _videoShell(
                      _remoteAgoraView(engine, remotes[1], connection),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: pad),
            Expanded(child: _videoShell(_localView(engine))),
          ],
        ),
      );
    }

    if (remotes.length == 3) {
      return Padding(
        padding: const EdgeInsets.all(pad),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _videoShell(
                      _remoteAgoraView(engine, remotes[0], connection),
                    ),
                  ),
                  const SizedBox(width: pad),
                  Expanded(
                    child: _videoShell(
                      _remoteAgoraView(engine, remotes[1], connection),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: pad),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _videoShell(
                      _remoteAgoraView(engine, remotes[2], connection),
                    ),
                  ),
                  const SizedBox(width: pad),
                  Expanded(child: _videoShell(_localView(engine))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        GridView.builder(
          padding: const EdgeInsets.all(pad),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: pad,
            crossAxisSpacing: pad,
            childAspectRatio: 0.85,
          ),
          itemCount: remotes.length,
          itemBuilder: (context, i) {
            return _videoShell(
              _remoteAgoraView(engine, remotes[i], connection),
            );
          },
        ),
        Positioned(
          right: 12,
          bottom: 12,
          width: 120,
          height: 170,
          child: _videoShell(_localView(engine)),
        ),
      ],
    );
  }

  Widget _videoShell(Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: child,
      ),
    );
  }

  Widget _remoteAgoraView(
    RtcEngine engine,
    int remoteUid,
    RtcConnection connection,
  ) {
    if (widget.isAudioOnly) {
      return _audioOnlyAvatar(isRemote: true);
    }
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: engine,
        canvas: VideoCanvas(uid: remoteUid),
        connection: connection,
        useFlutterTexture: Platform.isIOS,
        useAndroidSurfaceView: Platform.isAndroid,
      ),
    );
  }

  Widget _localView(RtcEngine engine) {
    if (widget.isAudioOnly) {
      return _audioOnlyAvatar(isRemote: false);
    }
    if (_videoOff) {
      return Container(
        color: const Color(0xFF2C2C2E),
        alignment: Alignment.center,
        child: const Icon(
          Icons.videocam_off_outlined,
          color: Color(0xFF8E8E93),
          size: 56,
        ),
      );
    }
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: engine,
        canvas: const VideoCanvas(uid: 0),
        useFlutterTexture: Platform.isIOS,
        useAndroidSurfaceView: Platform.isAndroid,
      ),
    );
  }

  Widget _audioOnlyAvatar({required bool isRemote}) {
    return Container(
      color: const Color(0xFF2C2C2E),
      alignment: Alignment.center,
      child: Icon(
        isRemote ? CupertinoIcons.person_fill : CupertinoIcons.mic_fill,
        color: const Color(0xFF8E8E93),
        size: isRemote ? 72 : 56,
      ),
    );
  }

  Widget _toolbar(RtcEngine? engine) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        border: Border(
          top: BorderSide(color: Color(0x22FFFFFF), width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: engine == null
                ? null
                : () async {
                    setState(() => _muted = !_muted);
                    await engine.muteLocalAudioStream(_muted);
                  },
            child: Icon(
              _muted ? CupertinoIcons.mic_off : CupertinoIcons.mic_fill,
              color: CupertinoColors.white,
              size: 28,
            ),
          ),
          if (!widget.isAudioOnly) ...[
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: engine == null
                  ? null
                  : () async {
                      setState(() => _videoOff = !_videoOff);
                      await engine.muteLocalVideoStream(_videoOff);
                    },
              child: Icon(
                _videoOff ? Icons.videocam_off : Icons.videocam,
                color: CupertinoColors.white,
                size: 28,
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: engine == null ? null : () => engine.switchCamera(),
              child: const Icon(
                CupertinoIcons.camera_rotate_fill,
                color: CupertinoColors.white,
                size: 28,
              ),
            ),
          ],
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _showAddParticipantSheet,
            child: const Icon(
              CupertinoIcons.person_add,
              color: CupertinoColors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddParticipantSheet() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;

    final callSnap =
        await FirebaseFirestore.instance
            .collection('video_calls')
            .doc(widget.callId)
            .get();
    final data = callSnap.data() ?? {};
    if ((data['createdBy'] as String? ?? '') != me) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Участники'),
            content: const Text(
              'Добавлять людей может только тот, кто начал звонок.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final controller = TextEditingController();
    List<Map<String, String>> results = [];
    bool loading = false;

    if (!mounted) return;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            Future<void> search(String q) async {
              final query = q.trim().toLowerCase();
              if (query.length < 2) {
                setModal(() => results = []);
                return;
              }
              setModal(() => loading = true);
              try {
                final snap = await FirebaseFirestore.instance
                    .collection('users')
                    .where('searchTokens', arrayContains: query)
                    .limit(12)
                    .get();
                final out = <Map<String, String>>[];
                for (final doc in snap.docs) {
                  if (doc.id == me) continue;
                  final d = doc.data();
                  final name = (d['fullName'] as String? ?? '').trim();
                  final user = (d['username'] as String? ?? '').trim();
                  out.add({
                    'uid': doc.id,
                    'title': name.isNotEmpty ? name : user,
                    'subtitle': user,
                  });
                }
                setModal(() => results = out);
              } finally {
                setModal(() => loading = false);
              }
            }

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.55,
              decoration: const BoxDecoration(
                color: Color(0xFF1C1C1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: CupertinoSearchTextField(
                      controller: controller,
                      placeholder: 'Имя или логин',
                      onChanged: search,
                    ),
                  ),
                  if (loading)
                    const Expanded(
                      child: Center(
                        child: CupertinoActivityIndicator(radius: 12),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final row = results[index];
                          return CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            alignment: Alignment.centerLeft,
                            onPressed: () async {
                              Navigator.pop(ctx);
                              try {
                                await _callData.inviteParticipant(
                                  callId: widget.callId,
                                  invitedUid: row['uid']!,
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                showCupertinoDialog<void>(
                                    context: context,
                                    builder: (dialogCtx) =>
                                        CupertinoAlertDialog(
                                          title: const Text('Ошибка'),
                                          content: Text('$e'),
                                          actions: [
                                            CupertinoDialogAction(
                                              onPressed: () =>
                                                  Navigator.pop(dialogCtx),
                                              child: const Text('OK'),
                                            ),
                                          ],
                                        ),
                                  );
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row['title'] ?? '',
                                  style: const TextStyle(
                                    color: CupertinoColors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if ((row['subtitle'] ?? '').isNotEmpty)
                                  Text(
                                    row['subtitle']!,
                                    style: const TextStyle(
                                      color: CupertinoColors.systemGrey,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }
}
