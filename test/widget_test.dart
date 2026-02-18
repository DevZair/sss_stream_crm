// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sss_watsapp/app.dart';
import 'package:sss_watsapp/service/db_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await DBService.initialize();
  });

  testWidgets('Login screen renders core elements', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const App());

    expect(find.text('Войти'), findsWidgets);
    expect(find.text('Логин'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);

    final buttonFinder = find.widgetWithText(ElevatedButton, 'Войти');
    ElevatedButton button = tester.widget(buttonFinder);
    expect(button.onPressed, isNull);

    await tester.enterText(find.byType(TextField).at(0), 'user123');
    await tester.enterText(find.byType(TextField).at(1), 'Test User');
    await tester.enterText(find.byType(TextField).at(2), '12345');
    await tester.enterText(find.byType(TextField).at(3), '123456');
    await tester.pump();

    button = tester.widget(buttonFinder);
    expect(button.onPressed, isNotNull);
  });
}
