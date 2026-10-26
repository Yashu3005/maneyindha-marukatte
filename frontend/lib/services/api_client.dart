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

  /// Saves the access token (and, when given, a new refresh token).
  /// Passing a null access token signs out and clears both.
  static Future<void> save(String? token, {String? refresh}) async {
    accessToken = token;
    final newRefresh = token == null ? null : (refresh ?? refreshToken);
    refreshToken = newRefresh;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove('accessToken');
    } else {
      await prefs.setString('accessToken', token);
    }
    if (newRefresh == null) {
      await prefs.remove('refreshToken');
    } else {
      await prefs.setString('refreshToken', newRefresh);
    }
  }
}

class ApiClient {
  ApiClient._();

  static const String _baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://localhost:5050/api/v1');

  static BaseOptions _options() => BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      );

  /// Access tokens last 15 minutes; trade the stored refresh token for a new
  /// pair. Uses a bare Dio (no interceptors) so it cannot recurse.
  static Future<bool> _refresh() async {
    final refresh = TokenStore.refreshToken;
    if (refresh == null) return false;
    try {
      final res = await Dio(_options())
          .post('/auth/refresh', data: {'refreshToken': refresh});
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      await TokenStore.save(data['accessToken'] as String?,
          refresh: data['refreshToken'] as String?);
      return TokenStore.accessToken != null;
    } catch (_) {
      return false;
    }
  }

  static final Dio dio = Dio(_options())
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = TokenStore.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (err, handler) async {
        final req = err.requestOptions;
        final expired = err.response?.statusCode == 401 &&
            !req.path.startsWith('/auth/') &&
            req.extra['retried'] != true;
        if (expired && await _refresh()) {
          req.extra['retried'] = true;
          req.headers['Authorization'] = 'Bearer ${TokenStore.accessToken}';
          try {
            final retry = await Dio(_options()).fetch(req);
            return handler.resolve(retry);
          } on DioException catch (e) {
            return handler.next(e);
          }
        }
        handler.next(err);
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
