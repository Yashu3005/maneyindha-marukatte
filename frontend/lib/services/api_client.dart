import 'package:dio/dio.dart';

/// Single Dio instance with auth interceptor. Base URL from --dart-define.
class ApiClient {
  ApiClient._();
  static final Dio dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE_URL',
        defaultValue: 'http://localhost:5000/api/v1'),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Phase 2: attach access token; refresh on 401.
        handler.next(options);
      },
    ));
}
