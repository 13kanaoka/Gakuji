import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'screens/email_verification_gate.dart';
import 'screens/login_page.dart';
import 'screens/main_shell.dart';
import 'screens/username_onboarding_gate.dart';
import 'services/app_theme_controller.dart';
import 'services/dictionary_service.dart';
import 'services/gakuji_user_data_store.dart';
import 'services/writing_recognition_service.dart';
import 'widgets/gakuji_styles.dart';

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
            stream: FirebaseAuth.instance.userChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final user = snapshot.data;
              if (user != null) {
                // Anonymous Firebase Auth is Gakuji's guest session. It keeps
                // the existing UID-based data layer working without forcing
                // email verification or a public username.
                if (user.isAnonymous) {
                  return _SignedInApp(user: user);
                }

                return EmailVerificationGate(
                  user: user,
                  child: UsernameOnboardingGate(
                    user: user,
                    child: _SignedInApp(user: user),
                  ),
                );
              }
              return const LoginPage();

            },
          ),

          builder: (context, child) {
            return Actions(
              actions: <Type, Action<Intent>>{
                EditableTextTapOutsideIntent:
                    CallbackAction<EditableTextTapOutsideIntent>(
                  onInvoke: (intent) {
                    intent.focusNode.unfocus();
                    return null;
                  },
                ),
              },
              child: _ThemeRebuildBoundary(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}

class _SignedInApp extends StatefulWidget {
  final User user;
  
  const _SignedInApp({required this.user});

  @override
  State<_SignedInApp> createState() => _SignedInAppState();
}

class _SignedInAppState extends State<_SignedInApp> with WidgetsBindingObserver {
  bool _loading = true;
  double _loadingProgress = 0.08;
  Timer? _loadingProgressTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLoadingProgress();
    _loadUserData();
  }

  @override
  void dispose() {
    _loadingProgressTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startLoadingProgress() {
    _loadingProgressTimer?.cancel();
    _loadingProgressTimer = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) {
        if (!mounted || !_loading) {
          _loadingProgressTimer?.cancel();
          return;
        }

        final increment = _loadingProgress < 0.55
            ? 0.025
            : _loadingProgress < 0.78
                ? 0.012
                : 0.004;

        setState(() {
          _loadingProgress = (_loadingProgress + increment)
              .clamp(0.0, 0.92)
              .toDouble();
        });
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _loading) return;
    // Resuming is a cheap opportunity to retry any cloud intersection work
    // that may have failed while the device was offline. Local use never waits.
    unawaited(_syncAfterLaunch());
  }

  Future<void> _loadUserData() async {
    await GakujiUserDataStore.load();

    if (!mounted) return;

    setState(() {
      if (_loadingProgress < 0.32) {
        _loadingProgress = 0.32;
      }
    });

    final needsInitialCloudHydration =
        GakujiUserDataStore.needsInitialCloudHydration;

    // A registered account with no local workspace yet must finish its first
    // cloud pull before MainShell is built. Otherwise Library is constructed
    // against an intentionally empty deck list and can stay visually stale
    // until the user manually refreshes it. Existing local accounts still open
    // immediately and keep the normal local-first background sync behavior.
    if (needsInitialCloudHydration) {
      setState(() {
        if (_loadingProgress < 0.48) {
          _loadingProgress = 0.48;
        }
      });

      await GakujiUserDataStore.syncAfterLaunch();
      if (!mounted) return;

      setState(() {
        _loadingProgress = 1.0;
      });
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
    }

    _loadingProgressTimer?.cancel();
    setState(() {
      _loadingProgress = 1.0;
      _loading = false;
    });

    if (!needsInitialCloudHydration) {
      unawaited(_syncAfterLaunch());
    }
  }

  Future<void> _syncAfterLaunch() async {
    final changed = await GakujiUserDataStore.syncAfterLaunch();
    if (!mounted || !changed) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _AccountSetupLoadingScreen(progress: _loadingProgress);
    }
    return const MainShell();
  }
}

class _AccountSetupLoadingScreen extends StatelessWidget {
  final double progress;

  const _AccountSetupLoadingScreen({
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gakujiColors.warmBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Setting things up',
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: GakujiText.medium.copyWith(
                  color: context.gakujiColors.darkGray,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Fetching your decks and account data...',
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: GakujiText.xSmall.copyWith(
                  color: context.gakujiColors.mediumGray,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 250,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 8,
                        backgroundColor: context.gakujiColors.softBorder,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          GakujiColors.reading,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
