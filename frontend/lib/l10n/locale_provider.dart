import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_strings.dart';

/// The language the person chose. Remembered on this device; English until they choose.
class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _load();
  }

  static const _key = 'app_locale';

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final code = p.getString(_key);
      if (code != null && AppStrings.codes.contains(code)) state = Locale(code);
    } catch (_) {/* storage can be unavailable (private window): stay on English */}
  }

  Future<void> choose(String code) async {
    if (!AppStrings.codes.contains(code)) return;
    state = Locale(code);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, code);
    } catch (_) {/* not remembered, still applied for this visit */}
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) => LocaleNotifier());
