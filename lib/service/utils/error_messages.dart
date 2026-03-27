import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Maps raw errors to short, user-friendly messages.
String friendlyError(Object? error) {
  if (error == null) return 'Что-то пошло не так. Попробуйте позже.';

  if (error is SocketException) {
    return 'Нет подключения к интернету.';
  }
  if (error is TimeoutException) {
    return 'Время ожидания истекло. Попробуйте ещё раз.';
  }
  if (error is DioException) {
    final status = error.response?.statusCode ?? error.type.index;
    if (status == 401 || status == 403) {
      return 'Нет доступа. Проверьте авторизацию.';
    }
    if (status == 404) {
      return 'Данные не найдены.';
    }
    if (status >= 500) {
      return 'Сервер недоступен. Попробуйте позже.';
    }
  }
  if (error is FirebaseAuthException) {
    final rawMessage = '${error.code} ${error.message ?? ''}';
    if (rawMessage.contains('CONFIGURATION_NOT_FOUND')) {
      return 'Firebase Authentication не инициализирован в проекте. Откройте Authentication в Firebase Console, нажмите Get started и включите Email/Password.';
    }
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
        return 'Неверный пароль.';
      case 'invalid-email':
        return 'Некорректный логин или ID пользователя.';
      case 'internal-error':
        return 'Firebase Authentication настроен не полностью. Проверьте Authentication -> Get started -> Sign-in method -> Email/Password.';
      case 'user-not-found':
        return 'Пользователь не найден.';
      case 'email-already-in-use':
        return 'Такой пользователь уже существует.';
      case 'weak-password':
        return 'Пароль слишком простой.';
      case 'operation-not-allowed':
        return 'Этот метод входа не включен в Firebase Console.';
      case 'network-request-failed':
        return 'Нет подключения к интернету.';
      case 'too-many-requests':
        return 'Слишком много попыток. Повторите позже.';
      default:
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
    }
  }
  if (error is FirebaseException) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
  }
  if (error is FormatException) {
    return error.message;
  }
  if (error is StateError) {
    final message = error.message.toString().trim();
    if (message.isNotEmpty) return message;
  }

  // Parse JSON-ish error strings like {"description":"Server Error",...}
  final decoded = _decodeErrorPayload(error);
  if (decoded != null) {
    final desc =
        decoded['description'] ?? decoded['message'] ?? decoded['detail'];
    if (desc is String && desc.trim().isNotEmpty) {
      return desc;
    }
  }

  final text = error.toString();
  if (text.contains('CONFIGURATION_NOT_FOUND')) {
    return 'В Firebase Authentication не настроен этот метод входа.';
  }
  if (text.contains('FIRAuthErrorDomain Code=17999') ||
      text.contains('FIRAuthInternalErrorDomain')) {
    return 'Firebase Authentication настроен не полностью. Проверьте Email/Password в консоли Firebase.';
  }
  if (text.contains('SocketException')) {
    return 'Нет подключения к интернету.';
  }
  if (text.contains('Timeout')) {
    return 'Время ожидания истекло. Попробуйте ещё раз.';
  }
  if (text.contains('permission-denied')) {
    return 'Нет доступа к данным Firebase.';
  }

  return 'Ошибка: $text';
}

Map<String, Object?>? _decodeErrorPayload(Object? error) {
  try {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, Object?>) return data;
      if (data is String) return jsonDecode(data) as Map<String, Object?>?;
    }
    if (error is String) {
      if (error.trim().startsWith('{')) {
        return jsonDecode(error) as Map<String, Object?>?;
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}
