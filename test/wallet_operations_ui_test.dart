import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/screens/wallet_operations_page.dart';

void main() {
  testWidgets('wallet operations exposes transfer deposit and withdraw modes', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WalletOperationsPage()));

    expect(find.text('عمليات المحفظة'), findsOneWidget);
    expect(find.text('تحويل'), findsOneWidget);
    expect(find.text('إيداع'), findsOneWidget);
    expect(find.text('سحب'), findsOneWidget);
    expect(find.text('معرف المستفيد'), findsOneWidget);

    await tester.tap(find.text('إيداع'));
    await tester.pump();
    expect(find.text('معرف المستفيد'), findsNothing);

    await tester.tap(find.text('سحب'));
    await tester.pump();
    expect(find.text('معرف المستفيد'), findsNothing);
  });
}
