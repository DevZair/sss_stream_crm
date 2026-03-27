/// Тип для [ConnectycubeFlutterCallKit]: 0 — аудио, 1 — видео.
const int callKitCallTypeAudio = 0;
const int callKitCallTypeVideo = 1;

class VideoCallRoom {
  const VideoCallRoom({
    required this.callId,
    required this.channelName,
    required this.participantIds,
    this.callType = callKitCallTypeVideo,
  });

  final String callId;
  final String channelName;
  final List<String> participantIds;

  /// [callKitCallTypeAudio] / [callKitCallTypeVideo]
  final int callType;

  bool get isVideoCall => callType == callKitCallTypeVideo;
}
