import 'package:flutter_test/flutter_test.dart';

import 'package:orbit/main.dart';

void main() {
  testWidgets('Landing screen renders onboarding prompt', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OrbitApp());

    expect(find.text('Orbit'), findsOneWidget);
    expect(find.text('What should we call you?'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
  });
}
