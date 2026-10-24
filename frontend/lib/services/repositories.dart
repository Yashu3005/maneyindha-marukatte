import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

List<Map<String, dynamic>> _asList(dynamic data) {
  if (data is! List) return [];
  return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

Map<String, dynamic> _asMap(dynamic data) {
  if (data is! Map) return {};
  return Map<String, dynamic>.from(data);
}

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

final orderProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.dio.get('/orders/$id');
  return _asMap(res.data['data']);
});

final myBusinessesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/businesses/mine');
  return _asList(res.data['data']);
});

final wishlistProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ApiClient.dio.get('/wishlist');
  return _asMap(res.data['data']);
});

final notificationsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ApiClient.dio.get('/notifications');
  return _asMap(res.data['data']);
});

final addressesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/users/me/addresses');
  return _asList(res.data['data']);
});

final categoriesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/admin/categories');
  return _asList(res.data['data']);
});

final supportTicketsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/support/mine');
  return _asList(res.data['data']);
});

final afterSalesRequestsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/orders/after-sales/entrepreneur');
  return _asList(res.data['data']);
});

final entrepreneurInsightsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.dio.get('/businesses/$id/insights');
  return _asMap(res.data['data']);
});

// Admin Providers
final adminStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ApiClient.dio.get('/admin/stats');
  return _asMap(res.data['data']);
});

final adminBusinessesProvider = FutureProvider.family<
    List<Map<String, dynamic>>, String>((ref, status) async {
  final res = await ApiClient.dio
      .get('/admin/verifications', queryParameters: {'status': status});
  return _asList(res.data['data']);
});

final adminEntrepreneursProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, query) async {
  final res = await ApiClient.dio
      .get('/admin/entrepreneurs', queryParameters: {'q': query});
  return _asList(res.data['data']);
});

final adminProductsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, status) async {
  final res = await ApiClient.dio
      .get('/admin/products', queryParameters: {'status': status});
  return _asList(res.data['data']);
});

final adminCategoriesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/admin/categories');
  return _asList(res.data['data']);
});

final adminTrendProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, period) async {
  final res = await ApiClient.dio
      .get('/admin/ai-trend-analysis', queryParameters: {'period': period});
  return _asList(res.data['data']);
});

final adminTicketsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, type) async {
  final res = await ApiClient.dio
      .get('/support/admin', queryParameters: {'type': type});
  return _asList(res.data['data']);
});

final adminActivityLogsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/admin/activity-logs');
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

/// Currently selected delivery address in customer shell
final selectedDeliveryAddressProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);
