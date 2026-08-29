import 'package:flutter/material.dart';

import '../services/account_auth_service.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';

class AccountInformationPage extends StatefulWidget {
  const AccountInformationPage({super.key});

  @override
  State<AccountInformationPage> createState() => _AccountInformationPageState();
}

class _AccountInformationPageState extends State<AccountInformationPage> {
  GakujiAuthProfile? _profile;
  bool _isWorking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    // Firebase Auth restores the signed-in user's email/provider metadata on
    // device. Render that cached account state immediately instead of briefly
    // showing a loading state while Firebase performs a network reload.
    try {
      _profile = GakujiAccountAuthService.currentProfileFromCache();
    } on GakujiAuthException catch (error) {
      _errorMessage = error.message;
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await GakujiAccountAuthService.loadCurrentProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _errorMessage = null;
      });
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not refresh account information right now.';
      });
    }
  }

  Future<void> _openPasswordFlow() async {
    final profile = _profile;
    if (profile == null) return;

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => profile.hasPassword
            ? const _ChangePasswordPage()
            : AddPasswordPage(initialEmail: profile.email),
      ),
    );

    if (!mounted || changed != true) return;

    setState(() {
      _profile = GakujiAccountAuthService.currentProfileFromCache();
      _errorMessage = null;
    });
  }

  Future<void> _openEmailFlow() async {
    final profile = _profile;
    if (profile == null) return;

    if (!profile.hasPassword) {
      _showMessage('Add Email & Password sign-in before changing your email.');
      return;
    }

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _ChangeEmailPage(currentEmail: profile.email ?? ''),
      ),
    );

    if (!mounted || changed != true) return;
    _showMessage('Verification sent to your new email. The address changes after you confirm it.');
  }

  Future<void> _connectGoogle() async {
    final profile = _profile;
    if (profile == null || profile.hasGoogle || _isWorking) return;

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      final updated = await GakujiAccountAuthService.linkGoogle();
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _isWorking = false;
      });
      _showMessage('Google connected to this Gakuji account.');
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _errorMessage = error.message;
      });
    }
  }

  Future<void> _sendVerification() async {
    if (_isWorking) return;

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      await GakujiAccountAuthService.sendCurrentEmailVerification();
      if (!mounted) return;
      setState(() {
        _isWorking = false;
      });
      _showMessage('Verification email sent.');
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _errorMessage = error.message;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2200),
          backgroundColor: Colors.black.withValues(alpha: 0.86),
          content: Text(
            message,
            textScaler: TextScaler.noScaling,
            style: GakujiText.snackBar,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gakujiColors.warmBackground,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: GakujiTopBar(
              leftIcon: GakujiTopBar.backIcon,
              leftIconSize: GakujiTopBar.backIconSize,
              leftIconColor: context.gakujiColors.darkGray,
              onLeftTap: () => Navigator.pop(context),
              title: 'Account Information',
              titleStyle: GakujiText.medium.copyWith(
                color: context.gakujiColors.darkGray,
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: GakujiColors.reading,
              onRefresh: _loadProfile,
              child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
                      children: [
                        Text(
                          'Sign-in Details',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.medium.copyWith(
                            color: context.gakujiColors.darkGray,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'These sign-in methods all open the same Gakuji account. Your account stays tied to its permanent internal ID, not to one email address.',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.xSmall.copyWith(
                            color: context.gakujiColors.mediumGray,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _settingRow(
                          label: 'Email',
                          onTap: _openEmailFlow,
                        ),
                        if (_profile?.email != null &&
                            _profile?.emailVerified == false) ...[
                          const SizedBox(height: 10),
                          _inlineAction(
                            label: 'Email not verified',
                            actionLabel: 'Send verification',
                            onTap: _isWorking ? null : _sendVerification,
                          ),
                        ],
                        const SizedBox(height: 28),
                        Text(
                          'Sign-in Methods',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.medium.copyWith(
                            color: context.gakujiColors.darkGray,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _settingRow(
                          label: 'Email & Password',
                          trailingText: _profile?.hasPassword == true
                              ? null
                              : 'Add',
                          onTap: _openPasswordFlow,
                        ),
                        const SizedBox(height: 12),
                        _settingRow(
                          label: 'Google',
                          trailingText: _profile?.hasGoogle == true
                              ? 'Connected'
                              : _isWorking
                                  ? 'Connecting...'
                                  : 'Add',
                          onTap: _profile?.hasGoogle == true || _isWorking
                              ? null
                              : _connectGoogle,
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 18),
                          Text(
                            _errorMessage!,
                            textScaler: TextScaler.noScaling,
                            style: GakujiText.xSmall.copyWith(
                              color: GakujiColors.pinRed,
                              height: 1.3,
                            ),
                          ),
                        ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingRow({
    required String label,
    String? trailingText,
    required VoidCallback? onTap,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.small.copyWith(
                      color: context.gakujiColors.darkGray,
                    ),
                  ),
                ),
                if (trailingText != null)
                  Text(
                    trailingText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.xSmall.copyWith(
                      color: context.gakujiColors.mediumGray,
                    ),
                  ),
                if (trailingText != null && onTap == null)
                  const SizedBox(width: 6),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 30,
                    color: context.gakujiColors.mediumGray,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inlineAction({
    required String label,
    required String actionLabel,
    required VoidCallback? onTap,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: GakujiColors.pinRed,
            ),
          ),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            actionLabel,
            textScaler: TextScaler.noScaling,
            style: GakujiText.xSmall.copyWith(
              color: GakujiColors.reading,
            ),
          ),
        ),
      ],
    );
  }
}

class AddPasswordPage extends StatefulWidget {
  final String? initialEmail;

  const AddPasswordPage({
    super.key,
    this.initialEmail,
  });

  @override
  State<AddPasswordPage> createState() => _AddPasswordPageState();
}

class _AddPasswordPageState extends State<AddPasswordPage> {
  late final TextEditingController _emailController;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (email.isEmpty) {
      setState(() => _error = 'Enter an email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Use a password with at least 6 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await GakujiAccountAuthService.linkPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SecurityFormScaffold(
      title: 'Add Password',
      heading: 'Email & Password',
      description:
          'Add a password so this same Gakuji account can be accessed without Google.',
      error: _error,
      children: [
        _SecurityField(
          controller: _emailController,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          enabled: widget.initialEmail == null || widget.initialEmail!.isEmpty,
        ),
        const SizedBox(height: 12),
        _SecurityField(
          controller: _passwordController,
          label: 'Password',
          obscureText: true,
        ),
        const SizedBox(height: 12),
        _SecurityField(
          controller: _confirmController,
          label: 'Confirm password',
          obscureText: true,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 24),
        _SecurityPrimaryButton(
          label: _isSaving ? 'Saving...' : 'Add Password',
          enabled: !_isSaving,
          onTap: _save,
        ),
      ],
    );
  }
}

class _ChangePasswordPage extends StatefulWidget {
  const _ChangePasswordPage();

  @override
  State<_ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<_ChangePasswordPage> {
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final current = _currentController.text;
    final next = _newController.text;
    final confirm = _confirmController.text;

    if (current.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (next.length < 6) {
      setState(() => _error = 'Use a new password with at least 6 characters.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await GakujiAccountAuthService.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = error.message;
      });
    }
  }

  Future<void> _resetPassword() async {
    try {
      final profile = await GakujiAccountAuthService.loadCurrentProfile();
      final email = profile.email;
      if (!mounted) return;

      if (email == null || email.isEmpty) {
        setState(() => _error = 'This account does not have an email address.');
        return;
      }

      await GakujiAccountAuthService.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Password reset email sent.',
            style: GakujiText.snackBar,
          ),
        ),
      );
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SecurityFormScaffold(
      title: 'Password',
      heading: 'Change Password',
      description: 'Confirm your current password before choosing a new one.',
      error: _error,
      children: [
        _SecurityField(
          controller: _currentController,
          label: 'Current password',
          obscureText: true,
        ),
        const SizedBox(height: 12),
        _SecurityField(
          controller: _newController,
          label: 'New password',
          obscureText: true,
        ),
        const SizedBox(height: 12),
        _SecurityField(
          controller: _confirmController,
          label: 'Confirm new password',
          obscureText: true,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isSaving ? null : _resetPassword,
            child: Text(
              'Forgot current password?',
              textScaler: TextScaler.noScaling,
              style: GakujiText.xSmall.copyWith(
                color: GakujiColors.reading,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _SecurityPrimaryButton(
          label: _isSaving ? 'Saving...' : 'Change Password',
          enabled: !_isSaving,
          onTap: _save,
        ),
      ],
    );
  }
}

class _ChangeEmailPage extends StatefulWidget {
  final String currentEmail;

  const _ChangeEmailPage({required this.currentEmail});

  @override
  State<_ChangeEmailPage> createState() => _ChangeEmailPageState();
}

class _ChangeEmailPageState extends State<_ChangeEmailPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final nextEmail = _emailController.text.trim();
    final password = _passwordController.text;

    if (nextEmail.isEmpty) {
      setState(() => _error = 'Enter your new email address.');
      return;
    }
    if (nextEmail.toLowerCase() == widget.currentEmail.toLowerCase()) {
      setState(() => _error = 'That is already your current email.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await GakujiAccountAuthService.requestEmailChange(
        currentPassword: password,
        newEmail: nextEmail,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SecurityFormScaffold(
      title: 'Email',
      heading: 'Change Email',
      description:
          'Current: ${widget.currentEmail}\nWe will send a verification link to the new address before it replaces this one.',
      error: _error,
      children: [
        _SecurityField(
          controller: _emailController,
          label: 'New email',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _SecurityField(
          controller: _passwordController,
          label: 'Current password',
          obscureText: true,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 24),
        _SecurityPrimaryButton(
          label: _isSaving ? 'Sending...' : 'Send Verification',
          enabled: !_isSaving,
          onTap: _save,
        ),
      ],
    );
  }
}

class _SecurityFormScaffold extends StatelessWidget {
  final String title;
  final String heading;
  final String description;
  final String? error;
  final List<Widget> children;

  const _SecurityFormScaffold({
    required this.title,
    required this.heading,
    required this.description,
    required this.error,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gakujiColors.warmBackground,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: GakujiTopBar(
              leftIcon: GakujiTopBar.backIcon,
              leftIconSize: GakujiTopBar.backIconSize,
              leftIconColor: context.gakujiColors.darkGray,
              onLeftTap: () => Navigator.pop(context),
              title: title,
              titleStyle: GakujiText.large.copyWith(
                color: context.gakujiColors.darkGray,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 38, 28, 32),
              children: [
                Text(
                  heading,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.medium.copyWith(
                    color: context.gakujiColors.darkGray,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.xSmall.copyWith(
                    color: context.gakujiColors.mediumGray,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                ...children,
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    error!,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.xSmall.copyWith(
                      color: GakujiColors.pinRed,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final bool enabled;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  const _SecurityField({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.enabled = true,
    this.keyboardType,
    this.onSubmitted,
  });

  @override
  State<_SecurityField> createState() => _SecurityFieldState();
}

class _SecurityFieldState extends State<_SecurityField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
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
        controller: widget.controller,
        enabled: widget.enabled,
        obscureText: _obscured,
        autocorrect: false,
        enableSuggestions: !widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.onSubmitted == null
            ? TextInputAction.next
            : TextInputAction.done,
        onSubmitted: widget.onSubmitted,
        style: GakujiText.small.copyWith(
          color: context.gakujiColors.darkGray,
        ),
        decoration: InputDecoration(
          hintText: widget.label,
          hintStyle: GakujiText.small.copyWith(
            color: context.gakujiColors.softGray,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          suffixIcon: widget.obscureText
              ? IconButton(
                  onPressed: widget.enabled
                      ? () => setState(() => _obscured = !_obscured)
                      : null,
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 22,
                    color: context.gakujiColors.mediumGray,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _SecurityPrimaryButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _SecurityPrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: enabled
            ? GakujiColors.reading
            : GakujiColors.reading.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
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
}
