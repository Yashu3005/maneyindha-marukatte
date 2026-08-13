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
