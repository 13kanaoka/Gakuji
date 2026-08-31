import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:gakuji/features/auth/services/account_auth_service.dart';
import 'package:gakuji/features/auth/services/account_username_service.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';

enum _AuthView {
  landing,
  signIn,
  createAccount,
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  _AuthView _view = _AuthView.landing;
  _AuthView? _outgoingView;
  late final AnimationController _panelController;
  int _panelDirection = 1;
  bool _isBusy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _successMessage;

  bool get _isCreateAccount => _view == _AuthView.createAccount;
  bool get _isSignIn => _view == _AuthView.signIn;

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _panelController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailPassword() async {
    if (_isBusy) return;

    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (_isCreateAccount) {
      final usernameValidation = GakujiUsernameService.validate(username);
      if (!usernameValidation.isValid) {
        _setError(
          usernameValidation.message ?? 'Enter a valid Gakuji username.',
        );
        return;
      }
    }

    if (email.isEmpty) {
      _setError('Enter your email address.');
      return;
    }

    if (password.isEmpty) {
      _setError('Enter your password.');
      return;
    }

    if (_isCreateAccount) {
      if (password.length < 6) {
        _setError('Use a password with at least 6 characters.');
        return;
      }

      if (password != confirmPassword) {
        _setError('Passwords do not match.');
        return;
      }
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      if (_isCreateAccount) {
        final credential =
            await GakujiAccountAuthService.createEmailPasswordAccount(
          email: email,
          password: password,
          sendVerification: false,
        );

        try {
          await GakujiUsernameService.saveUsername(username);
        } on GakujiUsernameException catch (error) {
          await _rollbackNewAccount(credential.user);
          if (!mounted) return;
          setState(() {
            _errorMessage = error.message;
          });
          return;
        } catch (_) {
          await _rollbackNewAccount(credential.user);
          if (!mounted) return;
          setState(() {
            _errorMessage =
                'Could not reserve that username. Please try again.';
          });
          return;
        }

        // The account and username are now tied to the same Firebase UID.
        // Verification stays as the final gate before the user can enter Gakuji.
        try {
          await GakujiAccountAuthService.sendCurrentEmailVerification();
        } on GakujiAuthException {
          // The verification gate can resend the email if this first delivery
          // fails, so do not destroy an otherwise valid account here.
        }
      } else {
        await GakujiAccountAuthService.signInWithEmailPassword(
          email: email,
          password: password,
        );
      }
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not complete sign-in. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _rollbackNewAccount(User? user) async {
    try {
      await user?.delete();
    } catch (_) {
      // Best-effort rollback. Signing out below still prevents this temporary
      // account from being treated as the active Gakuji account.
    }

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  Future<void> _signInWithGoogle() async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            error.message ?? 'Google sign-in failed. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Google sign-in failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    if (_isBusy) return;

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _setError('Enter your email first, then choose Forgot password.');
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await GakujiAccountAuthService.sendPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _successMessage = 'Password reset email sent.';
      });
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _setError(String message) {
    setState(() {
      _errorMessage = message;
      _successMessage = null;
    });
  }

  Future<void> _openView(_AuthView view) async {
    if (_isBusy || _panelController.isAnimating || view == _view) return;

    FocusScope.of(context).unfocus();

    final previousView = _view;
    final direction = view == _AuthView.landing ? -1 : 1;

    setState(() {
      _outgoingView = previousView;
      _panelDirection = direction;
      _view = view;
      _errorMessage = null;
      _successMessage = null;
      _passwordController.clear();
      _confirmPasswordController.clear();
    });

    await _panelController.forward(from: 0);

    if (!mounted) return;
    setState(() {
      _outgoingView = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final safeTop = mediaQuery.padding.top;
    final safeBottom = mediaQuery.padding.bottom;

    return Scaffold(
      backgroundColor: context.gakujiColors.warmBackground,
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final usableHeight =
              (constraints.maxHeight - safeTop - safeBottom).clamp(0.0, double.infinity);

          // The title still respects the device safe area, but the sliding
          // panel itself uses the full screen width so it can travel cleanly
          // beyond the visible edge instead of being clipped by SafeArea.
          final titleTop = safeTop +
              (usableHeight * 0.16).clamp(100.0, 145.0).toDouble();
          final panelTop = safeTop +
              (usableHeight * 0.35).clamp(245.0, 300.0).toDouble();
          const panelTravel = 1.22;

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: titleTop,
                left: 0,
                right: 0,
                child: Text(
                  'Gakuji',
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.xLarge.copyWith(
                    color: context.gakujiColors.darkGray,
                    fontSize: 44,
                    height: 1,
                  ),
                ),
              ),
              if (_view != _AuthView.landing)
                Positioned(
                  top: safeTop + 4,
                  left: 4,
                  child: IconButton(
                    onPressed: _isBusy
                        ? null
                        : () => _openView(_AuthView.landing),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: context.gakujiColors.darkGray,
                      size: 24,
                    ),
                  ),
                ),
              Positioned(
                top: panelTop,
                left: 0,
                right: 0,
                bottom: safeBottom + 8,
                child: AnimatedBuilder(
                  animation: _panelController,
                  builder: (context, _) {
                    final progress = Curves.easeInOutCubic.transform(
                      _panelController.value,
                    );
                    final outgoing = _outgoingView;
                    final direction = _panelDirection.toDouble();

                    return IgnorePointer(
                      ignoring: _panelController.isAnimating,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          if (outgoing != null)
                            FractionalTranslation(
                              translation: Offset(
                                -direction * panelTravel * progress,
                                0,
                              ),
                              child: _panelFrame(outgoing),
                            ),
                          FractionalTranslation(
                            translation: outgoing == null
                                ? Offset.zero
                                : Offset(
                                    direction *
                                        panelTravel *
                                        (1 - progress),
                                    0,
                                  ),
                            child: _panelFrame(_view),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _panelFrame(_AuthView view) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: _buildPanel(view),
      ),
    );
  }

  Widget _buildPanel(_AuthView view) {
    switch (view) {
      case _AuthView.landing:
        return _landingPanel();
      case _AuthView.signIn:
        return _signInPanel();
      case _AuthView.createAccount:
        return _createAccountPanel();
    }
  }

  Widget _landingPanel() {
    final landingTopOffset =
        (MediaQuery.sizeOf(context).height * 0.07).clamp(40.0, 60.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: landingTopOffset),
        _primaryButton(
          label: 'Log In',
          onTap: () => _openView(_AuthView.signIn),
        ),
        const SizedBox(height: 24),
        _secondaryButton(
          label: 'Create Account',
          onTap: () => _openView(_AuthView.createAccount),
        ),
      ],
    );
  }

  Widget _signInPanel() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            controller: _emailController,
            hintText: 'Email',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _passwordController,
            hintText: 'Password',
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitEmailPassword(),
            suffixIcon: _passwordVisibilityButton(
              obscured: _obscurePassword,
              onTap: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isBusy ? null : _sendPasswordReset,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Forgot password?',
                textScaler: TextScaler.noScaling,
                style: GakujiText.xSmall.copyWith(
                  color: GakujiColors.reading,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _messageArea(),
          _primaryButton(
            label: 'Log In',
            onTap: _isBusy ? null : _submitEmailPassword,
          ),
          const SizedBox(height: 20),
          _socialDivider(label: 'Log in with'),
          const SizedBox(height: 14),
          _googleButton(label: 'Google'),
        ],
      ),
    );
  }

  Widget _createAccountPanel() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            controller: _usernameController,
            hintText: 'Username',
            prefixText: '@',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _emailController,
            hintText: 'Email',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _passwordController,
            hintText: 'Password',
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            suffixIcon: _passwordVisibilityButton(
              obscured: _obscurePassword,
              onTap: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          _field(
            controller: _confirmPasswordController,
            hintText: 'Confirm password',
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitEmailPassword(),
            suffixIcon: _passwordVisibilityButton(
              obscured: _obscureConfirmPassword,
              onTap: () {
                setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                });
              },
            ),
          ),
          const SizedBox(height: 18),
          _messageArea(),
          _primaryButton(
            label: 'Create Account',
            onTap: _isBusy ? null : _submitEmailPassword,
          ),
          const SizedBox(height: 18),
          _socialDivider(label: 'Continue with'),
          const SizedBox(height: 14),
          _googleButton(label: 'Google'),
        ],
      ),
    );
  }

  Widget _messageArea() {
    if (_errorMessage == null && _successMessage == null) {
      return const SizedBox.shrink();
    }

    final isError = _errorMessage != null;
    final message = _errorMessage ?? _successMessage!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: GakujiText.xSmall.copyWith(
          color: isError ? GakujiColors.pinRed : GakujiColors.writing,
          height: 1.25,
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hintText,
    TextInputType? keyboardType,
    bool obscureText = false,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    Widget? suffixIcon,
    String? prefixText,
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
      child: TextField(
        controller: controller,
        enabled: !_isBusy,
        keyboardType: keyboardType,
        obscureText: obscureText,
        autocorrect: false,
        enableSuggestions: !obscureText,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: GakujiText.small.copyWith(
          color: context.gakujiColors.darkGray,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GakujiText.small.copyWith(
            color: context.gakujiColors.softGray,
          ),
          prefixText: prefixText,
          prefixStyle: GakujiText.small.copyWith(
            color: context.gakujiColors.mediumGray,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  Widget _passwordVisibilityButton({
    required bool obscured,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: _isBusy ? null : onTap,
      icon: Icon(
        obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        color: context.gakujiColors.mediumGray,
        size: 22,
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
            ? GakujiColors.reading.withValues(alpha: 0.55)
            : GakujiColors.reading,
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
            child: _isBusy && (_isSignIn || _isCreateAccount)
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(
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
      height: 56,
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
                color: context.gakujiColors.darkGray,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialDivider({required String label}) {
    return Column(
      children: [
        Text(
          'or',
          textScaler: TextScaler.noScaling,
          style: GakujiText.xSmall.copyWith(
            color: context.gakujiColors.mediumGray,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textScaler: TextScaler.noScaling,
          style: GakujiText.xSmall.copyWith(
            color: context.gakujiColors.darkGray,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _googleButton({required String label}) {
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
          onTap: _isBusy ? null : _signInWithGoogle,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.gakujiColors.whiteCard,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.gakujiColors.warmDivider,
                    ),
                  ),
                  child: Text(
                    'G',
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.small.copyWith(
                      color: GakujiColors.reading,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.small.copyWith(
                    color: context.gakujiColors.darkGray,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
