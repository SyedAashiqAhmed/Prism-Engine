import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_engine/main.dart';

void main() {
  testWidgets('PrismEngineApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PrismEngineApp(),
      ),
    );

    expect(find.text('Prism Engine'), findsOneWidget);
    expect(find.text('Sprint 0 Initialized'), findsOneWidget);
  });
}
