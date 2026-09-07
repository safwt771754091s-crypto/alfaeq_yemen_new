import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/main.dart';

void main() {
  testWidgets('الفائق يمن renders the fresh home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const AlfaeqYemenApp());

    expect(find.text('الفائق يمن'), findsOneWidget);
    expect(find.text('مرحباً بك في الفائق يمن'), findsOneWidget);
    expect(find.text('الأقسام'), findsOneWidget);
    expect(find.text('المتاجر'), findsOneWidget);
    expect(find.text('المطاعم'), findsOneWidget);
  });
}
