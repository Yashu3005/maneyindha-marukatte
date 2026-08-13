import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStore {
  static String? accessToken;
  static String? refreshToken;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('accessToken');
    refreshToken = prefs.getString('refreshToken');
  }

  static Future<void> save(String? access, String? refresh) async {
    accessToken = access;
    refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    if (access == null) {
      await prefs.remove('accessToken');
      await prefs.remove('refreshToken');
    } else {
      await prefs.setString('accessToken', access);
      if (refresh != null) await prefs.setString('refreshToken', refresh);
    }
  }
}

class ApiClient {
  ApiClient._();

  static final Dio dio = _build();

  static Dio _build() {
    final dio = Dio(BaseOptions(
      baseUrl: const String.fromEnvironment('API_BASE_URL',
          defaultValue: 'http://localhost:5050/api/v1'),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = TokenStore.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      // Access tokens expire after 15 min — silently refresh and retry
      // instead of surfacing "Invalid or expired token" to the user.
      onError: (e, handler) async {
        final req = e.requestOptions;
        final is401 = e.response?.statusCode == 401;
        final canRetry = req.extra['retried'] != true &&
            TokenStore.refreshToken != null &&
            !req.path.contains('/auth/');
        if (is401 && canRetry) {
          try {
            final fresh = await Dio(BaseOptions(baseUrl: dio.options.baseUrl))
                .post('/auth/refresh',
                    data: {'refreshToken': TokenStore.refreshToken});
            final data = Map<String, dynamic>.from(fresh.data['data'] as Map);
            await TokenStore.save(
                data['accessToken'] as String?, data['refreshToken'] as String?);
            req.extra['retried'] = true;
            req.headers['Authorization'] = 'Bearer ${TokenStore.accessToken}';
            final response = await dio.fetch(req);
            return handler.resolve(response);
          } catch (_) {
            // refresh failed → fall through with the original error
          }
        }
        handler.next(e);
      },
    ));
    return dio;
  }
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
