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

/// What the customer asked for on the home screen. Immutable with value equality so Riverpod can cache per filter set.
class ShopFilters {
  final String? category;      // category name
  final double minRating;      // 0 = any
  final bool openNow;
  final bool hasVideo;
  final String sort;           // 'nearest' (needs a position) | 'rating' | 'newest'
  final String? pos;           // "lat,lng" once the customer shared their location
  final double radiusKm;
  const ShopFilters({
    this.category,
    this.minRating = 0,
    this.openNow = false,
    this.hasVideo = false,
    this.sort = 'rating',
    this.pos,
    this.radiusKm = 25,
  });

  ShopFilters copyWith({
    Object? category = _keep,
    double? minRating,
    bool? openNow,
    bool? hasVideo,
    String? sort,
    Object? pos = _keep,
    double? radiusKm,
  }) =>
      ShopFilters(
        category: identical(category, _keep) ? this.category : category as String?,
        minRating: minRating ?? this.minRating,
        openNow: openNow ?? this.openNow,
        hasVideo: hasVideo ?? this.hasVideo,
        sort: sort ?? this.sort,
        pos: identical(pos, _keep) ? this.pos : pos as String?,
        radiusKm: radiusKm ?? this.radiusKm,
      );

  /// Number of filters the customer has switched on (shown on the Filters button).
  int get activeCount =>
      (category != null ? 1 : 0) +
      (minRating > 0 ? 1 : 0) +
      (openNow ? 1 : 0) +
      (hasVideo ? 1 : 0);

  Map<String, dynamic> toQuery() {
    final q = <String, dynamic>{};
    if (category != null) q['category'] = category;
    if (minRating > 0) q['minRating'] = minRating;
    if (openNow) q['openNow'] = true;
    if (hasVideo) q['hasVideo'] = true;
    if (pos != null) {
      final parts = pos!.split(',');
      q['lat'] = parts[0];
      q['lng'] = parts[1];
      q['radiusKm'] = radiusKm;
      // 'nearest' is the server default near a position; other sorts re-order within the radius.
      if (sort != 'nearest') q['sort'] = sort;
    } else {
      q['sort'] = sort == 'nearest' ? 'rating' : sort;
    }
    return q;
  }

  @override
  bool operator ==(Object other) =>
      other is ShopFilters &&
      other.category == category &&
      other.minRating == minRating &&
      other.openNow == openNow &&
      other.hasVideo == hasVideo &&
      other.sort == sort &&
      other.pos == pos &&
      other.radiusKm == radiusKm;

  @override
  int get hashCode => Object.hash(category, minRating, openNow, hasVideo, sort, pos, radiusKm);
}

const Object _keep = Object();

/// Shops matching the filters; uses "near me" when a position was shared, otherwise all approved shops.
final shopsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, ShopFilters>((ref, f) async {
  final res = await ApiClient.dio.get(f.pos == null ? '/businesses' : '/businesses/nearby',
      queryParameters: f.toQuery());
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

/// Orders received by the shops I own (shop owners only). Kept apart from [ordersProvider], which is what I placed.
final receivedOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/orders/received');
  return _asList(res.data['data']);
});

/// My notifications ({ items, unread }), newest first.
final notificationsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ApiClient.dio.get('/notifications');
  return _asMap(res.data['data']);
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

/// Star spread for a shop: { average, count, distribution: {1..5} }.
final ratingSummaryProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.dio.get('/businesses/$id/rating-summary');
  return _asMap(res.data['data']);
});

/// Items from the customer's delivered orders that they have not rated yet.
final toRateProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/reviews/to-rate');
  return _asList(res.data['data']);
});

/// Badge, progress and reward coupons for the signed-in customer.
final rewardsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ApiClient.dio.get('/rewards/me');
  return _asMap(res.data['data']);
});

/// Admin only.
final adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ApiClient.dio.get('/admin/stats');
  return _asMap(res.data['data']);
});

/// Admin only. Key: "role|query" (either part may be empty).
final adminUsersProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, key) async {
  final i = key.indexOf('|');
  final role = key.substring(0, i);
  final q = key.substring(i + 1);
  final res = await ApiClient.dio.get('/admin/users', queryParameters: {
    if (role.isNotEmpty) 'role': role,
    if (q.isNotEmpty) 'q': q,
    'limit': 50,
  });
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
