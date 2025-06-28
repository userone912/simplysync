// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:sildaprayona_simplysync/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp(isFirstRun: true));

    // Verify that the onboarding screen appears for first run
    expect(find.text('Welcome to simplySync'), findsOneWidget);
  });
  
  testWidgets('App launches to home screen for returning users', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp(isFirstRun: false));

    // Verify that the home screen appears for returning users
    expect(find.text('simplySync'), findsOneWidget);
  });
}
