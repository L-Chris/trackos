// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:trackos/screens/settings_screen.dart';

void main() {
  testWidgets('settings screen renders controls without overflow on a small screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('追踪间隔'), findsOneWidget);
    expect(find.text('服务器 URL'), findsOneWidget);
    expect(find.byIcon(Icons.save), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
