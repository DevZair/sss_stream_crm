import 'package:sss_watsapp/core/constants/api_constants.dart';
import 'package:sss_watsapp/service/api_service.dart';

import '../models/auth_response.dart';

class AuthRemoteDataSource {
  Future<AuthResponse> login({
    required String username,
    required String password,
    required String fullName,
    required String userId,
  }) async {
    final result = await ApiService.request<Map<String, dynamic>>(
      ApiConstants.loginPath,
      method: Method.post,
      data: {
        'username': username,
        'password': password,
        'full_name': fullName,
        'user_id': userId,
      },
      includeAuthHeader: false,
    );

    return AuthResponse.fromJson(Map<String, dynamic>.from(result));
  }
}
