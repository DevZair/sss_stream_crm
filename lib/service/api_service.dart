// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';

import 'package:sss_watsapp/core/constants/api_constants.dart';

import 'utils/custom_intercepter.dart';
import 'db_service.dart';

enum Method { get, post, put, patch, delete }

@immutable
class ApiService {
  const ApiService._();

  static String get _resolvedBaseUrl {
    final stored = DBService.baseUrl;
    final base = stored.isNotEmpty ? stored : ApiConstants.baseUrl;
    if (base.startsWith('http')) return base;
    return 'https://$base';
  }

  static final Dio _dio = Dio()
    ..options = BaseOptions(
      baseUrl: _resolvedBaseUrl,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      followRedirects: false,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      maxRedirects: 5,
    )
    ..httpClientAdapter = _buildHttpAdapter()
    ..interceptors.add(CustomInterceptor());

  static HttpClientAdapter _buildHttpAdapter() {
    final adapter = IOHttpClientAdapter();
    adapter.onHttpClientCreate = (client) {
      final allowedHost = Uri.tryParse(_resolvedBaseUrl)?.host;
      client.badCertificateCallback = (cert, host, port) {
        // Allow self-signed/invalid cert for our API host to prevent TLS handshake issues
        // on emulators and some Android/iOS devices.
        if (allowedHost != null && allowedHost.isNotEmpty) {
          return host == allowedHost;
        }
        return true;
      };
      return client;
    };
    return adapter;
  }

  static FutureOr<T> request<T>(
    String path, {
    Method method = Method.post,
    Object? data,
    Map<String, Object?>? headers,
    Map<String, Object?>? queryParams,
    FormData? formData,
    bool followRedirects = false,
    bool includeAuthHeader = true,
  }) async {
    final resolvedToken = _tokenForPath(path);
    final rawToken = resolvedToken.isNotEmpty
        ? resolvedToken
        : ApiConstants.apiToken;

    final isMultipart = formData != null;
    final newHeaders = <String, Object?>{'lang': DBService.languageCode};

    if (includeAuthHeader && rawToken.isNotEmpty) {
      newHeaders['Authorization'] = 'Bearer $rawToken';
    }

    if (headers != null) newHeaders.addAll(headers);

    final requestData = formData ?? data;

    try {
      final response = await _dio.request<Object?>(
        path,
        data: requestData,
        queryParameters: queryParams,
        options: Options(
          method: method.name,
          headers: newHeaders,
          contentType: isMultipart
              ? Headers.multipartFormDataContentType
              : Headers.jsonContentType,
          followRedirects: followRedirects,
          maxRedirects: followRedirects ? 5 : 0,
        ),
      );

      // Manually handle redirects to keep headers/method/payload consistent.
      if (followRedirects &&
          response.statusCode != null &&
          response.statusCode! >= 300 &&
          response.statusCode! < 400) {
        final location = response.headers.value('location');
        if (location != null && location.isNotEmpty) {
          return await request<T>(
            location,
            method: method,
            data: data,
            headers: headers,
            queryParams: queryParams,
            formData: formData,
            followRedirects: true,
          );
        }
      }

      if (response.statusCode == null || response.statusCode! > 204) {
        final json = _asMap(response.data);
        _throwApiError(json);
      }

      return const JsonDecoder().cast<String, T>().convert(
        jsonEncode(response.data ?? {}),
      );
    } on DioException catch (error, stackTrace) {
      final json = _asMap(error.response?.data);
      _throwApiError(json, stackTrace: stackTrace);
    } on Object catch (error, stackTrace) {
      Error.safeToString(error);
      stackTrace.toString();
      rethrow;
    }
  }

  static String _tokenForPath(String path) {
    final normalized = path.toLowerCase();
    // Never attach existing tokens to login endpoints to avoid 401.
    if (normalized.contains('/company/login') ||
        normalized.contains('/auth/admin/login') ||
        normalized.contains('/auth/login')) {
      return '';
    }

    if (normalized.contains('/auth/admin/')) {
      return DBService.superAdminAccessToken;
    }

    final isTourPath = normalized.contains('/tour/');

    if (isTourPath && DBService.tourAccessToken.isNotEmpty) {
      return DBService.tourAccessToken;
    }

    if (DBService.accessToken.isNotEmpty) {
      return DBService.accessToken;
    }

    return '';
  }

  static Never throwError() => throw Error.throwWithStackTrace(
    const JsonEncoder().cast<Map<String, Object?>, String>().convert({
      'description': 'Server Error',
      'status': 'Server Error',
      'data': 'Server Error',
      'message': "Can't send request",
      'isError': true,
    }),
    StackTrace.current,
  );

  static Map<String, Object?> _asMap(Object? data) {
    if (data is Map<String, Object?>) return data;
    if (data is Map<Object?, Object?>) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    final convert = const JsonEncoder().cast<Object?, String?>().convert(
      data ?? {},
    );
    return const JsonDecoder()
        .cast<String, Map<String, Object?>>()
        .convert(convert ?? '{}');
  }

  static Never _throwApiError(
    Map<String, Object?> json, {
    StackTrace? stackTrace,
  }) {
    if (json case {
      'status': final String? status,
      'description': final String? description,
      'data': final String? data,
    }) {
      throw Error.throwWithStackTrace(
        const JsonEncoder().cast<Map<String, Object?>, String>().convert({
          'description': description,
          'status': status,
          'data': data,
          'message': "Can't send request",
          'isError': true,
        }),
        stackTrace ?? StackTrace.current,
      );
    }

    final detail = _extractDetail(json);
    if (detail != null && detail.isNotEmpty) {
      throw Error.throwWithStackTrace(
        detail,
        stackTrace ?? StackTrace.current,
      );
    }

    throwError();
  }

  static String? _extractDetail(Map<String, Object?> json) {
    final detail = json['detail'];
    if (detail is String && detail.isNotEmpty) {
      return detail;
    }
    if (detail is List) {
      final parts = detail
          .map((item) {
            if (item is Map && item['msg'] is String) {
              return item['msg'] as String;
            }
            return item.toString();
          })
          .where((msg) => msg.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) return parts.join(', ');
    }
    final message = json['message'];
    if (message is String && message.isNotEmpty) return message;
    return null;
  }
}
