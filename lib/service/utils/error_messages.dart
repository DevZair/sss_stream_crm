import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

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
  if (text.contains('SocketException')) {
    return 'Нет подключения к интернету.';
  }
  if (text.contains('Timeout')) {
    return 'Время ожидания истекло. Попробуйте ещё раз.';
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
