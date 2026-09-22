import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/screens/login_page.dart';

void main() {
  testWidgets('الفائق يمن renders the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('الفائق يمن'), findsOneWidget);
    expect(find.text('تسجيل الدخول إلى حسابك'), findsOneWidget);
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
    expect(find.text('كلمة المرور'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });
}
