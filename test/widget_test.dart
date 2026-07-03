// Smoke test: the app boots and the main shell renders with its navigation.
//
// This intentionally pumps MyApp directly instead of calling main(), so the
// background dictionary/handwriting-model loads never start. The dictionary
// database asset is gitignored and may be missing on fresh checkouts; nothing
// here may depend on it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_app/main.dart';
import 'package:my_app/screens/main_shell.dart';

void main() {
  setUp(() {
    // Deck/folder storage reads SharedPreferences; back it with an empty
    // in-memory store so no platform plugin is needed.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app boots into the main shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(MainShell), findsOneWidget);

    // The nav icons are present. "At least one" keeps this from failing if
    // the same icon is later also used elsewhere or more nav items are added.
    expect(find.byIcon(Icons.home), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.search), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.folder_copy_outlined), findsAtLeastNWidgets(1));
  });
}
