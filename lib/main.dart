import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'screens/login_page.dart';
import 'screens/main_shell.dart';
import 'services/app_theme_controller.dart';
import 'services/dictionary_service.dart';
import 'services/gakuji_user_data_store.dart';
import 'services/writing_recognition_service.dart';
import 'widgets/gakuji_styles.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await GoogleSignIn.instance.initialize();

  // Load saved user data before the app opens.
  // This keeps decks, folders, pinned decks, and saved terms from resetting.
  await GakujiUserDataStore.load();

  // Restore the user's saved Light / Dark preference.
  await appThemeController.load();

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

  static const Size iphonePortraitPreviewSize = Size(393, 852);
  static const Size iphoneLandscapePreviewSize = Size(852, 393);

  ThemeData _themeFor(Brightness brightness) {
    final palette = brightness == Brightness.dark
        ? GakujiPalette.dark
        : GakujiPalette.light;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: GakujiColors.deckBlue,
      brightness: brightness,
      surface: palette.warmCard,
    ).copyWith(
      onSurface: palette.darkGray,
      outline: palette.softBorder,
      outlineVariant: palette.warmDivider,
      surfaceContainerHighest: palette.whiteCard,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.warmBackground,
      colorScheme: colorScheme,
      fontFamilyFallback: const [
        GakujiFonts.japanese,
      ],
      dividerColor: palette.warmDivider,
      dialogTheme: DialogThemeData(
        backgroundColor: palette.warmCard,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.warmBackground,
        surfaceTintColor: Colors.transparent,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(
            palette.warmCard,
          ),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        palette,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appThemeController,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Gakuji',
          theme: _themeFor(Brightness.light),
          darkTheme: _themeFor(Brightness.dark),
          themeMode: appThemeController.themeMode,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasData) {
                return const MainShell();
              }

              return const LoginPage();
            },
          ),
          builder: (context, child) {
            Widget app = _ThemeRebuildBoundary(
              child: child ?? const SizedBox.shrink(),
            );

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
      },
    );
  }
}

class _ThemeRebuildBoundary extends StatefulWidget {
  final Widget child;

  const _ThemeRebuildBoundary({
    required this.child,
  });

  @override
  State<_ThemeRebuildBoundary> createState() =>
      _ThemeRebuildBoundaryState();
}

class _ThemeRebuildBoundaryState extends State<_ThemeRebuildBoundary> {
  @override
  void initState() {
    super.initState();
    appThemeController.addListener(_rebuildActiveApp);
  }

  @override
  void dispose() {
    appThemeController.removeListener(_rebuildActiveApp);
    super.dispose();
  }

  void _rebuildActiveApp() {
    if (!mounted) return;

    void markForRebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markForRebuild);
    }

    context.visitChildElements(markForRebuild);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
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
    final originalSize = originalMediaQuery.size;
    final isLandscape = originalSize.width > originalSize.height;

    final previewSize = isLandscape
        ? MyApp.iphoneLandscapePreviewSize
        : MyApp.iphonePortraitPreviewSize;

    final previewPadding = isLandscape
        ? const EdgeInsets.only(
            left: 47,
            right: 34,
          )
        : const EdgeInsets.only(
            top: 47,
            bottom: 34,
          );

    final previewMediaQuery = originalMediaQuery.copyWith(
      size: previewSize,
      padding: previewPadding,
      viewPadding: previewPadding,
      viewInsets: EdgeInsets.zero,
    );

    return Container(
      color: context.isGakujiDarkMode
          ? const Color(0xFF0D0E10)
          : const Color(0xFF1E1E1E),
      child: Center(
        child: Container(
          width: previewSize.width,
          height: previewSize.height,
          decoration: BoxDecoration(
            color: context.gakujiColors.warmBackground,
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
              '${size.width.toStringAsFixed(0)} x '
              '${size.height.toStringAsFixed(0)}  '
              'DPR ${devicePixelRatio.toStringAsFixed(1)}',
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
