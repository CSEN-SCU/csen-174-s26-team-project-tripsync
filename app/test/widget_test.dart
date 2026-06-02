import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbit/main.dart';

void main() {
  testWidgets('Landing screen shows Orbit wordmark + Google sign-in button',
      (WidgetTester tester) async {
    // We render the landing widget directly to avoid Firebase init in tests.
    await tester.pumpWidget(
      const MaterialApp(home: OrbitLandingScreen()),
    );

    expect(find.text('Orbit'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    // The previous guest sign-in copy should no longer appear.
    expect(find.text('Continue as guest'), findsNothing);
    expect(find.text('What should we call you?'), findsNothing);
  });
}
