import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_inv_mssql/main.dart';

void main() {
  testWidgets('InvPro app logs in and renders dashboard', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const InvProApp());
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.text('Sign in to continue'), findsOneWidget);

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
