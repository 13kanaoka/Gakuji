import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/main_shell.dart';
import 'services/dictionary_service.dart';
import 'services/writing_recognition_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Start loading the dictionary database in the background.
  // This does not block the app from opening.
  unawaited(DictionaryService.loadDictionary());

  // Start loading/downloading the Japanese handwriting model in the background.
  // This does not block the app from opening.
  unawaited(WritingRecognitionService.ensureJapaneseModelDownloaded());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cards',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}