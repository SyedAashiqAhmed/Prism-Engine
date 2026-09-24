import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_engine/main.dart';

void main() {
  testWidgets('Dashboard screen mounts without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PrismEngineApp(),
      ),
    );
    // Let async initState complete (notification listener init is async)
    await tester.pump(const Duration(milliseconds: 500));

    // App title should be present in the MaterialApp
    expect(find.text('Prism Engine'), findsWidgets);
  });
}
