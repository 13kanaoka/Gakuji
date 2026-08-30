import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:gakuji/app/app.dart';
import 'package:gakuji/core/services/app_theme_controller.dart';
import 'package:gakuji/core/services/writing_recognition_service.dart';
import 'package:gakuji/data/dictionary/dictionary_service.dart';
import 'package:gakuji/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await GoogleSignIn.instance.initialize();

  // Restore the user's saved Light / Dark preference.
  await appThemeController.load();

  // Start loading the dictionary database in the background.
  // This does not block the app from opening.
  unawaited(DictionaryService.loadDictionary());

  // Provision the Japanese handwriting model as soon as Gakuji starts.
  // ML Kit keeps the downloaded model on-device, so later launches only verify
  // that the cached model is still present. This never blocks the app opening.
  unawaited(WritingRecognitionService.preloadJapaneseModel());

  runApp(const MyApp());
}
