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
  materialStatusCache('material_status_cache');

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
}
