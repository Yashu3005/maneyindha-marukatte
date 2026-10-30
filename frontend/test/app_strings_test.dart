import 'package:flutter_test/flutter_test.dart';
import 'package:maneyindha_marukatte/l10n/app_strings.dart';

void main() {
  test('every language has every translation, and none is blank', () {
    for (final code in AppStrings.codes.where((c) => c != 'en')) {
      final table = AppStrings.table(code)!;
      expect(table.keys.toSet(), AppStrings.keys.toSet(), reason: 'language $code is missing or has extra keys');
      for (final e in table.entries) {
        expect(e.value.trim(), isNotEmpty, reason: '$code / ${e.key}');
      }
    }
  });

  test('English and unknown text fall back to the English key itself', () {
    expect(AppStrings.t('en', 'Orders'), 'Orders');
    expect(AppStrings.t('kn', 'A sentence nobody translated'), 'A sentence nobody translated');
    expect(AppStrings.t('xx', 'Orders'), 'Orders');
  });

  test('a translated word is different from the English key', () {
    for (final code in ['kn', 'hi', 'ta', 'te']) {
      expect(AppStrings.t(code, 'Orders'), isNot('Orders'));
    }
  });
}
