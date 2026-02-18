import 'package:dio/dio.dart';
import 'logger.dart';

class CustomInterceptor extends Interceptor {
  const CustomInterceptor();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final requestData = _formatRequestData(options.data);
    info('''
------------------------------------------------------------
        === Request (${options.method}) ===
        === Url: ${options.uri} ===
        === Headers: ${options.headers} ===
        === Data: $requestData
------------------------------------------------------------''');
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    info('''
------------------------------------------------------------
=== Response (${response.statusCode}) ===
=== Url: ${response.realUri} ===
=== Method (${response.requestOptions.method}) ===
=== Data: ${response.data}
------------------------------------------------------------''');
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    info('''
------------------------------------------------------------
=== Error (${err.response?.statusCode}) ===
=== Url: ${err.response?.realUri} ===
=== Method (${err.response?.requestOptions.method}) ===
=== Data: ${err.response?.data}
------------------------------------------------------------''');
    super.onError(err, handler);
  }
}

String _formatRequestData(Object? data) {
  if (data is FormData) {
    final fields = data.fields
        .map((entry) => '${entry.key}=${entry.value}')
        .toList();
    final files = data.files
        .map(
          (entry) => '${entry.key}:${entry.value.filename ?? 'unnamed'}',
        )
        .toList();
    return 'FormData{fields: $fields, files: $files}';
  }
  return '$data';
}
