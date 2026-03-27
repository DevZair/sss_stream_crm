import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'video_call_models.dart';

class VideoCallRemoteDataSource {
  const VideoCallRemoteDataSource();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> get _calls =>
      _firestore.collection('video_calls');

  DocumentReference<Map<String, dynamic>> _incomingRef(
    String targetUid,
    String callId,
  ) {
    return _firestore
        .collection('users')
        .doc(targetUid)
        .collection('incoming_video_calls')
        .doc(callId);
  }

  /// Starts a 1:1 room from a direct chat; notifies [peerUid] via Firestore.
  /// [callType] — [callKitCallTypeAudio] или [callKitCallTypeVideo] (ConnectyCube / CallKit).
  Future<VideoCallRoom> createCall({
    required String sourceChatId,
    required String peerUid,
    int callType = callKitCallTypeVideo,
  }) async {
    final me = _auth.currentUser;
    if (me == null) {
      throw StateError('Выполните вход в приложение.');
    }
    if (peerUid.isEmpty || peerUid == me.uid) {
      throw StateError('Некорректный собеседник для звонка.');
    }

    final caller = await _displayNameForUid(me.uid);
    final callId = _uuid.v4();
    final channelName = callId.replaceAll('-', '');
    final participantIds = [me.uid, peerUid]..sort();

    final callRef = _calls.doc(callId);
    final batch = _firestore.batch();

    batch.set(callRef, {
      'channelName': channelName,
      'createdBy': me.uid,
      'participantIds': participantIds,
      'status': 'active',
      'sourceChatId': sourceChatId,
      'createdAt': FieldValue.serverTimestamp(),
      'callerName': caller,
      'callType': callType,
    });

    batch.set(_incomingRef(peerUid, callId), {
      'callId': callId,
      'channelName': channelName,
      'callerId': me.uid,
      'callerName': caller,
      'participantIds': participantIds,
      'sourceChatId': sourceChatId,
      'createdAt': FieldValue.serverTimestamp(),
      'callType': callType,
    });

    await batch.commit();

    return VideoCallRoom(
      callId: callId,
      channelName: channelName,
      participantIds: participantIds,
      callType: callType,
    );
  }

  Stream<VideoCallRoom?> watchCall(String callId) {
    return _calls.doc(callId).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data() ?? {};
      if ((data['status'] as String? ?? '') != 'active') return null;
      final channelName = (data['channelName'] as String? ?? '').trim();
      if (channelName.isEmpty) return null;
      final participants =
          (data['participantIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
      final ct = (data['callType'] as num?)?.toInt() ?? callKitCallTypeVideo;
      return VideoCallRoom(
        callId: snap.id,
        channelName: channelName,
        participantIds: participants,
        callType: ct == callKitCallTypeAudio ? callKitCallTypeAudio : callKitCallTypeVideo,
      );
    });
  }

  Future<VideoCallRoom?> getActiveCall(String callId) async {
    final snap = await _calls.doc(callId).get();
    if (!snap.exists) return null;
    final data = snap.data() ?? {};
    if ((data['status'] as String? ?? '') != 'active') return null;
    final channelName = (data['channelName'] as String? ?? '').trim();
    if (channelName.isEmpty) return null;
    final participants =
        (data['participantIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
    final ct = (data['callType'] as num?)?.toInt() ?? callKitCallTypeVideo;
    return VideoCallRoom(
      callId: snap.id,
      channelName: channelName,
      participantIds: participants,
      callType: ct == callKitCallTypeAudio ? callKitCallTypeAudio : callKitCallTypeVideo,
    );
  }

  /// Removes local incoming pointer (e.g. decline before join).
  Future<void> deleteIncomingForMe(String callId) async {
    final me = _auth.currentUser;
    if (me == null) return;
    await _incomingRef(me.uid, callId).delete();
  }

  Future<void> endCall(String callId) async {
    final me = _auth.currentUser;
    if (me == null) return;

    final ref = _calls.doc(callId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data() ?? {};
    final createdBy = (data['createdBy'] as String? ?? '').trim();
    final participants =
        (data['participantIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();

    if (createdBy != me.uid && !participants.contains(me.uid)) {
      throw StateError('Нет доступа к этому звонку.');
    }

    final batch = _firestore.batch();
    batch.set(ref, {
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    for (final uid in participants.toSet()) {
      batch.delete(_incomingRef(uid, callId));
    }

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      debugPrint('endCall batch: $e');
      await ref.set({
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Host invites another registered user; they receive [incoming_video_calls].
  Future<void> inviteParticipant({
    required String callId,
    required String invitedUid,
  }) async {
    final me = _auth.currentUser;
    if (me == null) {
      throw StateError('Выполните вход в приложение.');
    }
    if (invitedUid.isEmpty || invitedUid == me.uid) {
      throw StateError('Некорректный пользователь.');
    }

    final ref = _calls.doc(callId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('Звонок не найден.');
    }
    final data = snap.data() ?? {};
    if ((data['status'] as String? ?? '') != 'active') {
      throw StateError('Звонок уже завершён.');
    }
    if ((data['createdBy'] as String? ?? '') != me.uid) {
      throw StateError('Только организатор может добавлять участников.');
    }

    final channelName = (data['channelName'] as String? ?? '').trim();
    final participantIds =
        (data['participantIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
    if (participantIds.contains(invitedUid)) {
      return;
    }

    final callerName =
        (data['callerName'] as String? ?? '').trim().isNotEmpty
        ? (data['callerName'] as String).trim()
        : await _displayNameForUid(me.uid);
    final callType =
        (data['callType'] as num?)?.toInt() ?? callKitCallTypeVideo;

    final batch = _firestore.batch();
    batch.update(ref, {
      'participantIds': FieldValue.arrayUnion([invitedUid]),
    });
    batch.set(_incomingRef(invitedUid, callId), {
      'callId': callId,
      'channelName': channelName,
      'callerId': me.uid,
      'callerName': callerName,
      'participantIds': [...participantIds, invitedUid],
      'sourceChatId': data['sourceChatId'] ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'callType': callType,
    });
    await batch.commit();
  }

  Future<String> _displayNameForUid(String uid) async {
    final snap = await _firestore.collection('users').doc(uid).get();
    final data = snap.data() ?? {};
    final fullName = (data['fullName'] as String? ?? '').trim();
    if (fullName.isNotEmpty) return fullName;
    final username = (data['username'] as String? ?? '').trim();
    if (username.isNotEmpty) return username;
    return 'Пользователь';
  }
}
