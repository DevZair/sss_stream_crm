part of 'auth_bloc.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthLoginSubmitted extends AuthEvent {
  const AuthLoginSubmitted({
    required this.username,
    required this.password,
    required this.fullName,
    required this.userId,
  });

  final String username;
  final String password;
  final String fullName;
  final String userId;

  @override
  List<Object?> get props => [username, password, fullName, userId];
}

class AuthTogglePasswordVisibility extends AuthEvent {
  const AuthTogglePasswordVisibility();
}
