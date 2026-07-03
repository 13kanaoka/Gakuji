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

  static const bool useIphonePreviewFrame = true;
  static const bool showScreenSizeDebugLabel = true;

  static const Size iphonePreviewSize = Size(393, 852);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gakuji',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const MainShell(),
      builder: (context, child) {
        Widget app = child ?? const SizedBox.shrink();

        if (useIphonePreviewFrame) {
          app = _IphonePreviewFrame(
            child: app,
          );
        }

        if (!showScreenSizeDebugLabel) {
          return app;
        }

        return Stack(
          children: [
            app,
            const _ScreenSizeDebugLabel(),
          ],
        );
      },
    );
  }
}

class _IphonePreviewFrame extends StatelessWidget {
  final Widget child;

  const _IphonePreviewFrame({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final originalMediaQuery = MediaQuery.of(context);

    final previewMediaQuery = originalMediaQuery.copyWith(
      size: MyApp.iphonePreviewSize,
      padding: const EdgeInsets.only(
        top: 47,
        bottom: 34,
      ),
      viewPadding: const EdgeInsets.only(
        top: 47,
        bottom: 34,
      ),
      viewInsets: EdgeInsets.zero,
    );

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Center(
        child: Container(
          width: MyApp.iphonePreviewSize.width,
          height: MyApp.iphonePreviewSize.height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(38),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: MediaQuery(
            data: previewMediaQuery,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ScreenSizeDebugLabel extends StatelessWidget {
  const _ScreenSizeDebugLabel();

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final devicePixelRatio = mediaQuery.devicePixelRatio;

    return Positioned(
      left: 10,
      bottom: 10,
      child: IgnorePointer(
        child: Material(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 5,
            ),
            child: Text(
              '${size.width.toStringAsFixed(0)} x ${size.height.toStringAsFixed(0)}  DPR ${devicePixelRatio.toStringAsFixed(1)}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}