import 'package:equatable/equatable.dart';

class AuthSession extends Equatable {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    this.userName,
  });

  final String accessToken;
  final String refreshToken;
  final String? userName;

  @override
  List<Object?> get props => [accessToken, refreshToken, userName];
}
