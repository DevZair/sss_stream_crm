import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../service/utils/error_messages.dart';
import '../../domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this.authRepository}) : super(const AuthState()) {
    on<AuthLoginSubmitted>(_onLoginSubmitted);
    on<AuthTogglePasswordVisibility>(_onTogglePasswordVisibility);
  }

  final AuthRepository authRepository;

  Future<void> _onLoginSubmitted(
    AuthLoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final username = event.username.trim();
    final fullName = event.fullName.trim();
    final userId = event.userId.trim();

    if (username.isEmpty ||
        fullName.isEmpty ||
        userId.isEmpty ||
        event.password.trim().length < 6) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage:
              'Заполните все поля и укажите пароль не короче 6 символов.',
        ),
      );
      return;
    }

    emit(state.copyWith(status: AuthStatus.loading, errorMessage: ''));

    try {
      await authRepository.login(
        username: username,
        password: event.password,
        fullName: fullName,
        userId: userId,
      );

      emit(state.copyWith(status: AuthStatus.success));
    } catch (error, stackTrace) {
      debugPrint('Login error: $error\n$stackTrace');
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: friendlyError(error),
        ),
      );
    }
  }

  void _onTogglePasswordVisibility(
    AuthTogglePasswordVisibility event,
    Emitter<AuthState> emit,
  ) {
    emit(state.copyWith(obscurePassword: !state.obscurePassword));
  }
}
