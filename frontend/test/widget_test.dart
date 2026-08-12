import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maneyindha_marukatte/main.dart';

void main() {
  testWidgets('App builds and shows landing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MMApp()));
    expect(find.text('Get Started'), findsOneWidget);
  });
}
