import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStore {
  static String? accessToken;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('accessToken');
  }

  static Future<void> save(String? token) async {
    accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove('accessToken');
    } else {
      await prefs.setString('accessToken', token);
    }
  }
}

class ApiClient {
  ApiClient._();

  static final Dio dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE_URL',
        defaultValue: 'http://localhost:5050/api/v1'),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = TokenStore.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
}

/// Extract the API error message from a Dio error, or a fallback.
String apiError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map && data['error']['message'] != null) {
      return data['error']['message'].toString();
    }
    return e.message ?? 'Network error';
  }
  return e.toString();
}
