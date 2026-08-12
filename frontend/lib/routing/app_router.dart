import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _Placeholder('Splash')),
      GoRoute(path: '/home', builder: (_, __) => const _Placeholder('Home')),
      // Phase 4+: onboarding, auth, search, product, business, cart, checkout...
    ],
  );
});

class _Placeholder extends StatelessWidget {
  final String title;
  const _Placeholder(this.title);

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('Maneyindha Marukatte — $title')));
}
