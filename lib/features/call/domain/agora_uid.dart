/// Stable 31-bit Agora UID derived from Firebase Auth UID.
int firebaseUidToAgoraUid(String firebaseUid) {
  var h = 0;
  for (final c in firebaseUid.codeUnits) {
    h = (h * 31 + c) & 0x7FFFFFFF;
  }
  if (h == 0) h = 1;
  return h;
}
