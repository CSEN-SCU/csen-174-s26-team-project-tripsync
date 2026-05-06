import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tripsync/main.dart';

void main() {
  testWidgets('Landing screen renders onboarding prompt', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TripSyncApp());

    expect(find.text('TripSync'), findsOneWidget);
    expect(find.text('What should we call you?'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
