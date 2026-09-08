import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/main.dart';

void main() {
  testWidgets('الفائق يمن renders the fresh home screen', (WidgetTester tester) async {
    // AuthGate requires a live Firebase Auth instance. This widget test targets
    // the home UI itself, so it intentionally renders HomePage directly.
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('الفائق يمن'), findsOneWidget);
    expect(find.text('مرحباً بك في الفائق يمن'), findsOneWidget);
    expect(find.text('الأقسام الـ16'), findsOneWidget);
  });
}
