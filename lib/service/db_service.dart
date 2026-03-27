import 'package:shared_preferences/shared_preferences.dart';

enum StorageKeys {
  accessToken('access_token'),
  refreshToken('refresh_token'),
  tourAccessToken('tour_access_token'),
  tourRefreshToken('tour_refresh_token'),
  superAdminAccessToken('super_admin_access_token'),
  superAdminRefreshToken('super_admin_refresh_token'),
  languageCode('language_code'),
  fcmToken('fcm_token'),
  baseUrl('base_url'),
  materialStatusCache('material_status_cache'),
  firebaseUid('firebase_uid'),
  currentUserName('current_user_name'),
  currentFullName('current_full_name'),
  currentInternalUserId('current_internal_user_id'),
  authEmail('auth_email');

  const StorageKeys(this.key);
  final String key;
}

late final SharedPreferences $storage;

class DBService {
  static Future<void> initialize() async {
    $storage = await SharedPreferences.getInstance();
  }

  static String get accessToken {
    return $storage.getString(StorageKeys.accessToken.name) ?? '';
  }

  static set accessToken(String token) {
    $storage.setString(StorageKeys.accessToken.name, token);
  }

  static String get refreshToken {
    return $storage.getString(StorageKeys.refreshToken.name) ?? '';
  }

  static set refreshToken(String token) {
    $storage.setString(StorageKeys.refreshToken.name, token);
  }

  static String get tourAccessToken {
    return $storage.getString(StorageKeys.tourAccessToken.name) ?? '';
  }

  static set tourAccessToken(String token) {
    $storage.setString(StorageKeys.tourAccessToken.name, token);
  }

  static String get tourRefreshToken {
    return $storage.getString(StorageKeys.tourRefreshToken.name) ?? '';
  }

  static set tourRefreshToken(String token) {
    $storage.setString(StorageKeys.tourRefreshToken.name, token);
  }

  static String get superAdminAccessToken {
    return $storage.getString(StorageKeys.superAdminAccessToken.name) ?? '';
  }

  static set superAdminAccessToken(String token) {
    $storage.setString(StorageKeys.superAdminAccessToken.name, token);
  }

  static String get superAdminRefreshToken {
    return $storage.getString(StorageKeys.superAdminRefreshToken.name) ?? '';
  }

  static set superAdminRefreshToken(String token) {
    $storage.setString(StorageKeys.superAdminRefreshToken.name, token);
  }

  static String get languageCode {
    return $storage.getString(StorageKeys.languageCode.name) ?? 'ru';
  }

  static set languageCode(String code) {
    $storage.setString(StorageKeys.languageCode.name, code);
  }

  static String get fcmToken {
    return $storage.getString(StorageKeys.fcmToken.name) ?? '';
  }

  static set fcmToken(String token) {
    $storage.setString(StorageKeys.fcmToken.name, token);
  }

  static String get baseUrl {
    return $storage.getString(StorageKeys.baseUrl.name) ?? '';
  }

  static set baseUrl(String token) {
    $storage.setString(StorageKeys.baseUrl.name, token);
  }

  static String get firebaseUid {
    return $storage.getString(StorageKeys.firebaseUid.name) ?? '';
  }

  static set firebaseUid(String value) {
    $storage.setString(StorageKeys.firebaseUid.name, value);
  }

  static String get currentUserName {
    return $storage.getString(StorageKeys.currentUserName.name) ?? '';
  }

  static set currentUserName(String value) {
    $storage.setString(StorageKeys.currentUserName.name, value);
  }

  static String get currentFullName {
    return $storage.getString(StorageKeys.currentFullName.name) ?? '';
  }

  static set currentFullName(String value) {
    $storage.setString(StorageKeys.currentFullName.name, value);
  }

  static String get currentInternalUserId {
    return $storage.getString(StorageKeys.currentInternalUserId.name) ?? '';
  }

  static set currentInternalUserId(String value) {
    $storage.setString(StorageKeys.currentInternalUserId.name, value);
  }

  static String get authEmail {
    return $storage.getString(StorageKeys.authEmail.name) ?? '';
  }

  static set authEmail(String value) {
    $storage.setString(StorageKeys.authEmail.name, value);
  }

  static Future<void> clearSession() async {
    await Future.wait([
      $storage.remove(StorageKeys.accessToken.name),
      $storage.remove(StorageKeys.refreshToken.name),
      $storage.remove(StorageKeys.firebaseUid.name),
      $storage.remove(StorageKeys.currentUserName.name),
      $storage.remove(StorageKeys.currentFullName.name),
      $storage.remove(StorageKeys.currentInternalUserId.name),
      $storage.remove(StorageKeys.authEmail.name),
    ]);
  }
}
