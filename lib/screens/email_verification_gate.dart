import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/account_auth_service.dart';
import '../widgets/gakuji_styles.dart';

class EmailVerificationGate extends StatefulWidget {
  final User user;
  final Widget child;

  const EmailVerificationGate({
    super.key,
    required this.user,
    required this.child,
  });

  @override
  State<EmailVerificationGate> createState() => _EmailVerificationGateState();
}

class _EmailVerificationGateState extends State<EmailVerificationGate>
    with WidgetsBindingObserver {
  static const int _resendCooldownSeconds = 60;

  bool _isChecking = false;
  bool _isSending = false;
  String? _message;
  bool _verified = false;
  int _resendSecondsRemaining = 0;
  Timer? _resendTimer;

  bool get _usesPassword {
    final current = FirebaseAuth.instance.currentUser ?? widget.user;
    return current.providerData.any(
      (provider) => provider.providerId == 'password',
    );
  }

  bool get _requiresVerification {
    final current = FirebaseAuth.instance.currentUser ?? widget.user;
    return _usesPassword && !current.emailVerified && !_verified;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _requiresVerification) {
      unawaited(_refreshVerificationStatus(showNotVerifiedMessage: false));
    }
  }

  Future<void> _checkVerification() async {
    await _refreshVerificationStatus(showNotVerifiedMessage: true);
  }

  Future<void> _refreshVerificationStatus({
    required bool showNotVerifiedMessage,
  }) async {
    if (_isChecking) return;

    if (mounted) {
      setState(() {
        _isChecking = true;
        if (showNotVerifiedMessage) {
          _message = null;
        }
      });
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();
      final refreshed = FirebaseAuth.instance.currentUser;

      if (!mounted) return;

      if (refreshed?.emailVerified == true) {
        setState(() {
          _verified = true;
          _isChecking = false;
          _message = null;
        });
        return;
      }

      setState(() {
        _isChecking = false;
        if (showNotVerifiedMessage) {
          _message = 'That email is not verified yet.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        if (showNotVerifiedMessage) {
          _message = 'Could not refresh verification status. Try again.';
        }
      });
    }
  }

  Future<void> _resendVerification() async {
    if (_isSending || _resendSecondsRemaining > 0) return;

    setState(() {
      _isSending = true;
      _message = null;
    });

    try {
      await GakujiAccountAuthService.sendCurrentEmailVerification();
      if (!mounted) return;

      setState(() {
        _isSending = false;
        _message = 'Verification email sent.';
      });
      _startResendCooldown();
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _message = error.message;
      });
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();

    setState(() {
      _resendSecondsRemaining = _resendCooldownSeconds;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendSecondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _resendSecondsRemaining = 0;
        });
        return;
      }

      setState(() {
        _resendSecondsRemaining -= 1;
      });
    });
  }

  Future<void> _signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (!_requiresVerification) return widget.child;

    final email = FirebaseAuth.instance.currentUser?.email ??
        widget.user.email ??
        '';
    final resendDisabled = _isSending || _resendSecondsRemaining > 0;
    final resendLabel = _isSending
        ? 'Sending...'
        : _resendSecondsRemaining > 0
            ? 'Resend in ${_resendSecondsRemaining}s'
            : 'Resend Email';

    return Scaffold(
      backgroundColor: context.gakujiColors.warmBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 36, 28, 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.mark_email_unread_rounded,
                    size: 76,
                    color: GakujiColors.deckBlue,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Verify your email',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.large.copyWith(
                      color: context.gakujiColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a verification link to\n$email',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.xSmall.copyWith(
                      color: context.gakujiColors.mediumGray,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Open the link in your email, then return to Gakuji. We will check again automatically.',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.xSmall.copyWith(
                      color: context.gakujiColors.mediumGray,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Didn\'t get it? Check your spam folder or resend the email below.',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.xSmall.copyWith(
                      color: context.gakujiColors.softGray,
                      height: 1.35,
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.xSmall.copyWith(
                        color: _message == 'Verification email sent.'
                            ? GakujiColors.writing
                            : GakujiColors.pinRed,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _primaryButton(
                    label: _isChecking ? 'Checking...' : 'I Verified My Email',
                    onTap: _isChecking ? null : _checkVerification,
                  ),
                  const SizedBox(height: 10),
                  _secondaryButton(
                    label: resendLabel,
                    onTap: resendDisabled ? null : _resendVerification,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _signOut,
                    child: Text(
                      'Use another account',
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.xSmall.copyWith(
                        color: context.gakujiColors.mediumGray,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: onTap == null
            ? GakujiColors.deckBlue.withValues(alpha: 0.55)
            : GakujiColors.deckBlue,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: context.gakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.gakujiColors.warmDivider,
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: onTap == null
                    ? context.gakujiColors.softGray
                    : context.gakujiColors.darkGray,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
