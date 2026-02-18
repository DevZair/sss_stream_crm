import '../../domain/entities/auth_session.dart';

class AuthResponse {
  AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    this.userName,
  });

  final String accessToken;
  final String refreshToken;
  final String? userName;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final nested = json['data'];
    final Map<String, dynamic> source = nested is Map<String, dynamic>
        ? nested
        : json;

    String pick(List<String> keys) {
      for (final key in keys) {
        final value = source[key] ?? json[key];
        if (value is String && value.isNotEmpty) return value;
      }
      return '';
    }

    final token = pick(['access_token', 'accessToken', 'token']);
    final refresh = pick(['refresh_token', 'refreshToken', 'refresh']);

    final name = source['user'] is Map<String, dynamic>
        ? (source['user'] as Map<String, dynamic>)['name'] as String?
        : source['name'] as String?;

    return AuthResponse(
      accessToken: token,
      refreshToken: refresh,
      userName: name,
    );
  }

  AuthSession toEntity() {
    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userName: userName,
    );
  }
}
