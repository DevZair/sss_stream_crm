import 'package:flutter_test/flutter_test.dart';
import 'package:sss_watsapp/features/call/domain/agora_uid.dart';

void main() {
  test('firebaseUidToAgoraUid is stable and positive', () {
    const uid = 'test_firebase_uid_abc';
    final a = firebaseUidToAgoraUid(uid);
    final b = firebaseUidToAgoraUid(uid);
    expect(a, b);
    expect(a, greaterThan(0));
    expect(a, lessThanOrEqualTo(0x7FFFFFFF));
  });

  test('firebaseUidToAgoraUid differs for different inputs', () {
    final a = firebaseUidToAgoraUid('user_a');
    final b = firebaseUidToAgoraUid('user_b');
    expect(a, isNot(b));
  });
}
