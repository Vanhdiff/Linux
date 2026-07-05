import 'package:flutter_test/flutter_test.dart';
import 'package:trading_desk/app/app.dart';

void main() {
  testWidgets('App renders shell', (WidgetTester tester) async {
    await tester.pumpWidget(const TradingDeskApp());

    expect(find.text('Dashboard'), findsWidgets);
  });
}
