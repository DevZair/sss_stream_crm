/// Agora RTC. Переопределение: `--dart-define=AGORA_APP_ID=...`
/// Без App Certificate токен можно не задавать. С Certificate — бэкенд или
/// `--dart-define=AGORA_TOKEN=...` для проверки.
abstract final class AgoraConstants {
  static const String appId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: 'ca7bbe49bdc7463387e22130c992466c',
  );

  static const String token = String.fromEnvironment(
    'AGORA_TOKEN',
    defaultValue: '',
  );

  static String get rtcToken => token.trim();
}
