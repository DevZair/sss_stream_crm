import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';

import '../../data/video_call_models.dart';
import '../../services/connectycube_call_kit_service.dart';
import '../../services/video_call_lifecycle.dart';

/// Слушает `users/{uid}/incoming_video_calls` и показывает нативный входящий звонок
/// (ConnectyCube Call Kit: CallKit / ConnectionService).
class IncomingVideoCallHost extends StatefulWidget {
  const IncomingVideoCallHost({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingVideoCallHost> createState() => _IncomingVideoCallHostState();
}

class _IncomingVideoCallHostState extends State<IncomingVideoCallHost> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  final Set<String> _callKitShownFor = {};

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _sub?.cancel();
      _sub = null;
      _callKitShownFor.clear();
      if (user == null) return;
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('incoming_video_calls');
      _sub = ref.snapshots().listen(_onIncomingSnapshot);
    });
  }

  void _onIncomingSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted || VideoCallLifecycle.isInRoom) return;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final doc = change.doc;
      final callId = doc.id;
      if (_callKitShownFor.contains(callId)) continue;
      final data = doc.data() ?? {};
      final channelName = (data['channelName'] as String? ?? '').trim();
      final callerName = (data['callerName'] as String? ?? 'Звонок').trim();
      final callerUid = (data['callerId'] as String? ?? '').trim();
      final callType =
          (data['callType'] as num?)?.toInt() ?? callKitCallTypeVideo;
      if (channelName.isEmpty || callerUid.isEmpty) continue;

      _callKitShownFor.add(callId);
      unawaited(
        ConnectycubeCallKitService.showIncomingKit(
          callId: callId,
          channelName: channelName,
          callerName: callerName,
          callerUid: callerUid,
          calleeUid: me.uid,
          callType: callType == callKitCallTypeAudio
              ? callKitCallTypeAudio
              : callKitCallTypeVideo,
        ),
      );
      break;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
