import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      debugShowCheckedModeBanner: false,
    );
  }
}
