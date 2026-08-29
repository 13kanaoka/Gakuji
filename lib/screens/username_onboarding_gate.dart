import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/account_username_service.dart';
import '../widgets/gakuji_styles.dart';
import 'username_settings_page.dart';

/// Places the mandatory username setup in front of newly-created accounts
/// while allowing accounts created before the username rollout to continue.
///
/// Wrap the signed-in app with this widget after Firebase authentication has
/// resolved. Existing users without usernames are deliberately grandfathered.
class UsernameOnboardingGate extends StatefulWidget {
  final User user;
  final Widget child;

  const UsernameOnboardingGate({
    super.key,
    required this.user,
    required this.child,
  });

  @override
  State<UsernameOnboardingGate> createState() =>
      _UsernameOnboardingGateState();
}

class _UsernameOnboardingGateState extends State<UsernameOnboardingGate> {
  String get _setupCompletePreferenceKey =>
      'gakuji_username_setup_complete_${widget.user.uid}';

  bool _isLoading = true;
  bool _requiresUsername = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _evaluateAccount();
  }

  @override
  void didUpdateWidget(covariant UsernameOnboardingGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _evaluateAccount();
    }
  }

  Future<void> _evaluateAccount() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    // Once this UID has completed account setup on this installation, never
    // make ordinary app launch depend on Firestore again. Username editing is
    // still cloud-backed from Account settings when the user explicitly opens
    // it.
    final prefs = await SharedPreferences.getInstance();
    final cachedSetup = prefs.getBool(_setupCompletePreferenceKey) ?? false;
    if (cachedSetup) {
      if (!mounted) return;
      setState(() {
        _requiresUsername = false;
        _isLoading = false;
      });
      return;
    }

    try {
      final profile = await GakujiUsernameService.loadCurrentProfile();
      final requiresUsername =
          GakujiUsernameService.shouldRequireInitialUsername(
        user: widget.user,
        profile: profile,
      );

      if (!requiresUsername) {
        await prefs.setBool(_setupCompletePreferenceKey, true);
      }

      if (!mounted) return;

      setState(() {
        _requiresUsername = requiresUsername;
        _isLoading = false;
      });
    } catch (_) {
      // Account metadata is not study data. A temporary Firestore outage must
      // never lock an already-authenticated user out of the local app. Do not
      // cache this fallback; the username requirement is checked again the next
      // time connectivity is available.
      if (!mounted) return;
      setState(() {
        _requiresUsername = false;
        _isLoading = false;
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.gakujiColors.warmBackground,
        body: const Center(
          child: CircularProgressIndicator(
            color: GakujiColors.deckBlue,
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: context.gakujiColors.warmBackground,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.small.copyWith(
                      color: context.gakujiColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: _evaluateAccount,
                    style: TextButton.styleFrom(
                      foregroundColor: GakujiColors.deckBlue,
                    ),
                    child: Text(
                      'Try Again',
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.small.copyWith(
                        color: GakujiColors.deckBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_requiresUsername) {
      return UsernameSettingsPage(
        requiredSetup: true,
        onSetupComplete: _evaluateAccount,
      );
    }

    return widget.child;
  }
}
