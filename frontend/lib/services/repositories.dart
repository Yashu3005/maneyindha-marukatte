import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

List<Map<String, dynamic>> _asList(dynamic data) =>
    (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

Map<String, dynamic> _asMap(dynamic data) =>
    Map<String, dynamic>.from(data as Map);

final businessesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/businesses');
  return _asList(res.data['data']);
});

/// Shops near a point the user shared. Key is "lat,lng" so the provider can be cached per position.
final nearbyBusinessesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, key) async {
  final parts = key.split(',');
  final res = await ApiClient.dio.get('/businesses/nearby', queryParameters: {
    'lat': parts[0], 'lng': parts[1], 'radiusKm': 25,
  });
  return _asList(res.data['data']);
});

final businessProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.dio.get('/businesses/$id');
  return _asMap(res.data['data']);
});

final productsProvider = FutureProvider.family<List<Map<String, dynamic>>, String?>(
    (ref, businessId) async {
  final res = await ApiClient.dio.get('/products',
      queryParameters: businessId == null ? null : {'business': businessId});
  return _asList(res.data['data']);
});

final productProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.dio.get('/products/$id');
  return _asMap(res.data['data']);
});

final cartProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ApiClient.dio.get('/cart');
  return _asMap(res.data['data']);
});

final ordersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/orders/mine');
  return _asList(res.data['data']);
});

final myBusinessesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/businesses/mine');
  return _asList(res.data['data']);
});

final adminBusinessesProvider = FutureProvider.family<
    List<Map<String, dynamic>>, String>((ref, status) async {
  final res = await ApiClient.dio
      .get('/admin/verifications', queryParameters: {'status': status});
  return _asList(res.data['data']);
});

final imagesProvider =
    FutureProvider.family<List<String>, String>((ref, query) async {
  final res = await ApiClient.dio
      .get('/images', queryParameters: {'q': query, 'count': 6});
  return (res.data['data'] as List).map((e) => e.toString()).toList();
});

final businessReviewsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final res = await ApiClient.dio.get('/reviews/business/$id');
  return _asList(res.data['data']);
});

/// Scratch state carried through the seller onboarding steps.
final sellerOnboardingProvider =
    StateProvider<Map<String, dynamic>>((ref) => {});

/// Where to download the app, as configured on the server. `configured == false` means: show nothing.
final appDownloadProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final res = await ApiClient.dio.get('/app/download');
    return Map<String, dynamic>.from(res.data['data'] as Map);
  } catch (_) {
    return {'configured': false};
  }
});
