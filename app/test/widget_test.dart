import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tripsync/main.dart';

void main() {
  testWidgets('Landing screen renders TripSync branding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TripSyncApp());

    expect(find.text('TripSync'), findsOneWidget);
    expect(find.byIcon(Icons.explore), findsOneWidget);
  });
}
