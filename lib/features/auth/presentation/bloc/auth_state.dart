part of 'auth_bloc.dart';

enum AuthStatus { initial, loading, success, failure }

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.initial,
    this.errorMessage = '',
    this.obscurePassword = true,
  });

  final AuthStatus status;
  final String errorMessage;
  final bool obscurePassword;

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    bool? obscurePassword,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      obscurePassword: obscurePassword ?? this.obscurePassword,
    );
  }

  @override
  List<Object?> get props => [status, errorMessage, obscurePassword];
}
