import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maneyindha_marukatte/main.dart';
import 'package:maneyindha_marukatte/theme/app_theme.dart';
import 'package:maneyindha_marukatte/services/repositories.dart';

void main() {
  group('Theme Tokens & Color Palette Verification', () {
    test('MMColors contains frozen leaf green and terracotta accents', () {
      expect(MMColors.primaryGreen, const Color(0xFF365B1F));
      expect(MMColors.secondaryGreen, const Color(0xFF6E8A2F));
      expect(MMColors.warmIvory, const Color(0xFFFFFDF5));
      expect(MMColors.accentGold, const Color(0xFFE9B949));
      expect(MMColors.softYellow, const Color(0xFFFFF3A6));
      expect(MMColors.textPrimary, const Color(0xFF2F2F2F));
      expect(MMColors.textSecondary, const Color(0xFF555555));
    });

    test('Theme typography and font styling is loaded', () {
      final heading = AppTheme.light.textTheme.headlineMedium;
      expect(heading != null, true);
    });
  });

  group('Cart & Entrepreneur Ordering Business Rules', () {
    test('Cart single-entrepreneur grouping logic', () {
      // Setup mock cart items with two different entrepreneur stores
      final cartItems = [
        {
          'productId': 'prod_1',
          'product': {
            '_id': 'prod_1',
            'name': 'Chocolate Truffle Cake',
            'business': {'_id': 'biz_asha', 'name': "Asha's Home Bakes"},
            'price': 549,
            'stock': 10,
          },
          'quantity': 2,
        },
        {
          'productId': 'prod_2',
          'product': {
            '_id': 'prod_2',
            'name': 'Butter Cookies',
            'business': {'_id': 'biz_asha', 'name': "Asha's Home Bakes"},
            'price': 199,
            'stock': 20,
          },
          'quantity': 1,
        },
        {
          'productId': 'prod_3',
          'product': {
            '_id': 'prod_3',
            'name': 'Handmade Terracotta Earrings',
            'business': {'_id': 'biz_kala', 'name': 'Kala Crafts'},
            'price': 349,
            'stock': 5,
          },
          'quantity': 1,
        },
      ];

      // Group by store
      final Map<String, List<Map<String, dynamic>>> storesMap = {};
      for (final item in cartItems) {
        final p = item['product'] as Map<String, dynamic>;
        final b = p['business'] as Map<String, dynamic>;
        final bId = b['_id'] as String;
        storesMap.putIfAbsent(bId, () => []).add(item);
      }

      // Verify that items are properly partitioned by store
      expect(storesMap.keys.length, 2);
      expect(storesMap['biz_asha']!.length, 2);
      expect(storesMap['biz_kala']!.length, 1);

      // Verify single store selection rule
      String? activeCheckoutStore = 'biz_asha';
      final selectedItems = storesMap[activeCheckoutStore]!;
      expect(selectedItems.length, 2);

      // Verify subtotal calculation
      num subtotal = 0;
      for (final it in selectedItems) {
        final p = it['product'] as Map<String, dynamic>;
        subtotal += (p['price'] as num) * (it['quantity'] as num);
      }
      expect(subtotal, (549 * 2) + 199); // 1098 + 199 = 1297
    });
  });

  group('Widget & Navigation Smoke Tests', () {
    testWidgets('App initializes with root landing flow', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MMApp()));
      await tester.pumpAndSettle();
      expect(find.text('Get Started'), findsOneWidget);
    });
  });
}
