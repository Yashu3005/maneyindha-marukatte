import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/app_strings.dart';
import 'l10n/locale_provider.dart';
import 'theme/app_theme.dart';
import 'routing/app_router.dart';

void main() {
  usePathUrlStrategy(); // real addresses such as /admin/login instead of /#/admin/login
  runApp(const ProviderScope(child: MMApp()));
}

class MMApp extends ConsumerWidget {
  const MMApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Maneyindha Marukatte',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(appRouterProvider),
      locale: ref.watch(localeProvider),
      supportedLocales: AppStrings.locales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      locale: ref.watch(localeProvider),
      supportedLocales: AppStrings.locales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}
