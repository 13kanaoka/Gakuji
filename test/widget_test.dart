// Smoke test: the main shell mounts and shows its tab navigation.
//
// This pumps MainShell inside a bare MaterialApp rather than the real MyApp.
// MyApp gates on Firebase Auth before it builds anything, and standing up
// Firebase Core + Auth + a mock signed-in user for a smoke test isn't worth
// it. MainShell is what "the app boots into" once past auth.
//
// MainShell's tab pages touch the on-device SQLite database on init, so the
// test installs the FFI sqflite factory and points the databases at a
// throwaway temp directory. The dictionary database asset is gitignored and
// may be missing; DictionaryService falls back to its in-memory seed list when
// it can't open the real one, so nothing here depends on it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gakuji/app/main_shell.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dbDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    // Isolate the on-device databases to a temp dir that's wiped after the test.
    dbDir = await Directory.systemTemp.createTemp('gakuji_widget_test_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  tearDown(() async {
    if (dbDir.existsSync()) {
      await dbDir.delete(recursive: true);
    }
  });

  testWidgets('main shell mounts with its tab navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[GakujiPalette.light],
        ),
        home: const MainShell(),
      ),
    );
    // Let the init-time async database reads settle.
    await tester.pumpAndSettle();

    expect(find.byType(MainShell), findsOneWidget);

    // Three tabs in the pill nav: the dictionary icon plus two image-asset icons.
    expect(find.byIcon(Icons.search_rounded), findsAtLeastNWidgets(1));
    expect(find.byType(ImageIcon), findsNWidgets(2));
  });
}
