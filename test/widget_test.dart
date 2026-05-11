import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_inv_mssql/main.dart';

void main() {
  testWidgets('InvPro app logs in and renders dashboard', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const InvProApp());
    expect(find.text('InvPro login'), findsOneWidget);

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('POS'), findsWidgets);

    await tester.tap(find.text('POS').first);
    await tester.pumpAndSettle();

    expect(find.text('Sell items'), findsOneWidget);
    expect(find.text('Payment'), findsOneWidget);
  });
}
