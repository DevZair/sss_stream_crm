/// Avoid stacking incoming-call UI while already in a video room.
class VideoCallLifecycle {
  VideoCallLifecycle._();

  static bool isInRoom = false;
}
