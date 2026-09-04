import 'package:flutter_test/flutter_test.dart';
import 'package:alfaeq_yemen/main.dart';

void main() {
  testWidgets('Alfaeq Yemen app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const AlfaeqYemenApp());
    await tester.pump();

    expect(find.byType(AlfaeqYemenApp), findsOneWidget);
  });
}
