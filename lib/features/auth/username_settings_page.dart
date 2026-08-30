import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gakuji/features/auth/services/account_username_service.dart';
import 'package:gakuji/features/auth/widgets/gakuji_action_dialog.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';

class UsernameSettingsPage extends StatefulWidget {
  final bool requiredSetup;
  final VoidCallback? onSetupComplete;

  const UsernameSettingsPage({
    super.key,
    this.requiredSetup = false,
    this.onSetupComplete,
  });

  @override
  State<UsernameSettingsPage> createState() => _UsernameSettingsPageState();
}

class _UsernameSettingsPageState extends State<UsernameSettingsPage> {
  final TextEditingController _usernameController = TextEditingController();
  final FocusNode _usernameFocusNode = FocusNode();

  Timer? _availabilityDebounce;
  GakujiUsernameProfile? _profile;
  GakujiUsernameAvailability? _availability;
  GakujiUsernameValidation? _validation;

  bool _isLoading = true;
  bool _isChecking = false;
  bool _isSaving = false;
  bool _isReverting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _availabilityDebounce?.cancel();
    _usernameController.dispose();
    _usernameFocusNode.dispose();
    super.dispose();
  }

  bool get _hasUsername => _profile?.hasUsername ?? false;

  bool get _cooldownActive =>
      _hasUsername && (_profile?.isChangeCooldownActive ?? false);

  String? get _previousUsername {
    final previousUsername = _profile?.previousUsername?.trim();
    if (previousUsername == null || previousUsername.isEmpty) return null;
    return previousUsername;
  }

  bool get _canRevert =>
      !widget.requiredSetup &&
      !_isLoading &&
      !_isSaving &&
      !_isReverting &&
      _cooldownActive &&
      _previousUsername != null;

  bool get _showRulesCard =>
      _validation != null && !_validation!.isValid;

  bool get _isSameAsCurrent {
    final normalized = GakujiUsernameService.normalize(_usernameController.text);
    return _profile?.usernameNormalized == normalized && normalized.isNotEmpty;
  }

  bool get _canSave {
    if (_isLoading ||
        _isChecking ||
        _isSaving ||
        _isReverting ||
        _cooldownActive) {
      return false;
    }
    if (_validation?.isValid != true) return false;
    if (_availability?.isAvailable != true) return false;
    if (_isSameAsCurrent) return false;
    return true;
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await GakujiUsernameService.loadCurrentProfile();

      if (!mounted) return;

      _usernameController.text = profile.username ?? '';
      _validation = profile.hasUsername
          ? GakujiUsernameService.validate(profile.username!)
          : null;

      setState(() {
        _profile = profile;
        _isLoading = false;
        _loadError = null;
        _availability = profile.hasUsername
            ? const GakujiUsernameAvailability(
                isAvailable: false,
                isCurrentUsername: true,
                message: 'This is your current username.',
              )
            : null;
      });

      if (!profile.hasUsername) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _usernameFocusNode.requestFocus();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load your username right now.';
      });
    }
  }

  void _handleUsernameChanged(String value) {
    _availabilityDebounce?.cancel();
    final validation = GakujiUsernameService.validate(value);
    final sameAsCurrent =
        _profile?.usernameNormalized == validation.normalized &&
        validation.normalized.isNotEmpty;

    setState(() {
      _validation = value.trim().isEmpty ? null : validation;
      _availability = sameAsCurrent
          ? const GakujiUsernameAvailability(
              isAvailable: false,
              isCurrentUsername: true,
              message: 'This is your current username.',
            )
          : null;
      _isChecking = false;
    });

    if (value.trim().isEmpty || !validation.isValid || sameAsCurrent) {
      return;
    }

    _availabilityDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _checkAvailability(value),
    );
  }

  Future<void> _checkAvailability(String value) async {
    if (!mounted) return;

    setState(() {
      _isChecking = true;
      _availability = null;
    });

    try {
      final result = await GakujiUsernameService.checkAvailability(value);

      if (!mounted ||
          GakujiUsernameService.normalize(value) !=
              GakujiUsernameService.normalize(_usernameController.text)) {
        return;
      }

      setState(() {
        _availability = result;
        _isChecking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _availability = const GakujiUsernameAvailability(
          isAvailable: false,
          isCurrentUsername: false,
          message: 'Could not check availability. Try again.',
        );
        _isChecking = false;
      });
    }
  }

  Future<void> _saveUsername() async {
    if (!_canSave) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final profile = await GakujiUsernameService.saveUsername(
        _usernameController.text,
      );

      if (!mounted) return;

      setState(() {
        _profile = profile;
        _usernameController.text = profile.username ?? _usernameController.text;
        _availability = const GakujiUsernameAvailability(
          isAvailable: false,
          isCurrentUsername: true,
          message: 'This is your current username.',
        );
        _validation = profile.username == null
            ? null
            : GakujiUsernameService.validate(profile.username!);
        _isSaving = false;
      });

      if (widget.requiredSetup) {
        widget.onSetupComplete?.call();
        return;
      }

      Navigator.pop(context, true);
    } on GakujiUsernameException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _availability = GakujiUsernameAvailability(
          isAvailable: false,
          isCurrentUsername: false,
          message: error.message,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _availability = const GakujiUsernameAvailability(
          isAvailable: false,
          isCurrentUsername: false,
          message: 'Could not save username. Try again.',
        );
      });
    }
  }

  Future<void> _confirmRevertUsername() async {
    if (!_canRevert) return;

    final previousUsername = _previousUsername!;
    final confirmed = await showGakujiActionDialog(
      context: context,
      title: 'Revert Username?',
      message: 'Previous: $previousUsername',
      primaryLabel: 'Revert',
      primaryColor: GakujiColors.reading,
      messageStyle: GakujiText.small.copyWith(
        color: context.gakujiColors.mediumGray,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isReverting = true;
      _loadError = null;
    });

    try {
      final profile = await GakujiUsernameService.revertToPreviousUsername();

      if (!mounted) return;

      setState(() {
        _profile = profile;
        _usernameController.text = profile.username ?? _usernameController.text;
        _availability = const GakujiUsernameAvailability(
          isAvailable: false,
          isCurrentUsername: true,
          message: 'This is your current username.',
        );
        _validation = profile.username == null
            ? null
            : GakujiUsernameService.validate(profile.username!);
        _isReverting = false;
      });

      Navigator.pop(context, true);
    } on GakujiUsernameException catch (error) {
      if (!mounted) return;
      setState(() {
        _isReverting = false;
        _loadError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isReverting = false;
        _loadError = 'Could not revert your username right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      backgroundColor: context.gakujiColors.warmBackground,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 38, 28, 36),
              children: [
                Text(
                  widget.requiredSetup ? 'Choose your username' : 'Username',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.actionLabel.copyWith(
                    fontSize: (GakujiText.actionLabel.fontSize ?? 16) + 2,
                    color: context.gakujiColors.darkGray,
                  ),
                ),
                if (widget.requiredSetup) ...[
                  const SizedBox(height: 8),
                  Text(
                    'This is the name that will identify you as a Gakuji deck creator.',
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.body.copyWith(
                      color: context.gakujiColors.mediumGray,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _usernameField(),
                if (_canRevert || _isReverting) ...[
                  const SizedBox(height: 4),
                  _revertAction(),
                ],
                if (!_cooldownActive) ...[
                  const SizedBox(height: 10),
                  _statusLine(),
                ],
                if (_showRulesCard) ...[
                  const SizedBox(height: 24),
                  _rulesCard(),
                ],
                if (_hasUsername) ...[
                  const SizedBox(height: 24),
                  _cooldownCard(),
                ],
                if (_loadError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _loadError!,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.deckMeta.copyWith(
                      color: GakujiColors.pinRed,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (!widget.requiredSetup) return page;

    return PopScope(
      canPop: false,
      child: page,
    );
  }

  Widget _header() {
    return SafeArea(
      bottom: false,
      child: GakujiTopBar(
        leftIcon: widget.requiredSetup ? null : GakujiTopBar.backIcon,
        leftIconSize: GakujiTopBar.backIconSize,
        leftIconColor: context.gakujiColors.darkGray,
        onLeftTap: widget.requiredSetup ? null : () => Navigator.pop(context),
        title: widget.requiredSetup ? 'Set Username' : 'Username',
        titleStyle: GakujiText.pageTitle.copyWith(
          color: context.gakujiColors.darkGray,
        ),
        rightWidget: _topRightAction(),
      ),
    );
  }

  Widget _topRightAction() {
    final showSave = _canSave || _isSaving;

    if (!showSave) {
      return const SizedBox(width: 76, height: 44);
    }

    return TextButton(
      onPressed: _isSaving ? null : _saveUsername,
      style: TextButton.styleFrom(
        foregroundColor: GakujiColors.reading,
        disabledForegroundColor: context.gakujiColors.softGray,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(76, 44),
      ),
      child: Text(
        _isSaving ? 'Saving' : 'Save',
        textScaler: TextScaler.noScaling,
        style: GakujiText.actionLabel.copyWith(
          color: GakujiColors.reading,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _revertAction() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _canRevert ? _confirmRevertUsername : null,
        style: TextButton.styleFrom(
          foregroundColor: GakujiColors.reading,
          disabledForegroundColor: context.gakujiColors.softGray,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          _isReverting ? 'Reverting…' : 'Revert',
          textScaler: TextScaler.noScaling,
          style: GakujiText.deckMeta.copyWith(
            color: GakujiColors.reading,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _usernameField() {
    final enabled =
        !_isLoading && !_isSaving && !_isReverting && !_cooldownActive;

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: context.gakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _statusBorderColor(),
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: TextField(
        controller: _usernameController,
        focusNode: _usernameFocusNode,
        enabled: enabled,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.none,
        inputFormatters: [
          LengthLimitingTextInputFormatter(20),
        ],
        onChanged: _handleUsernameChanged,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          if (_canSave) _saveUsername();
        },
        style: GakujiText.actionLabel.copyWith(
          color: context.gakujiColors.darkGray,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixStyle: GakujiText.actionLabel.copyWith(
            color: context.gakujiColors.mediumGray,
          ),
          hintText: _isLoading ? 'Loading...' : 'username',
          hintStyle: GakujiText.actionLabel.copyWith(
            color: context.gakujiColors.softGray,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Color _statusBorderColor() {
    if (_availability?.isAvailable == true) {
      return GakujiColors.writing;
    }

    if ((_validation != null && !_validation!.isValid) ||
        (_availability != null &&
            !_availability!.isAvailable &&
            !_availability!.isCurrentUsername)) {
      return GakujiColors.pinRed;
    }

    return context.gakujiColors.warmDivider;
  }

  Widget _statusLine() {
    String text;
    Color color;

    if (_usernameController.text.trim().isEmpty) {
      text = '3–20 characters';
      color = context.gakujiColors.mediumGray;
    } else if (_validation != null && !_validation!.isValid) {
      text = _validation!.message ?? 'That username cannot be used.';
      color = GakujiColors.pinRed;
    } else if (_isChecking) {
      text = 'Checking availability...';
      color = context.gakujiColors.mediumGray;
    } else if (_availability != null) {
      text = _availability!.message;
      color = _availability!.isAvailable
          ? GakujiColors.writing
          : _availability!.isCurrentUsername
              ? context.gakujiColors.mediumGray
              : GakujiColors.pinRed;
    } else {
      text = 'Usernames are not case-sensitive.';
      color = context.gakujiColors.mediumGray;
    }

    return Row(
      children: [
        if (_isChecking) ...[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: GakujiColors.reading,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            textScaler: TextScaler.noScaling,
            style: GakujiText.deckMeta.copyWith(
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _rulesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: context.gakujiColors.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.gakujiColors.warmDivider,
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Text(
        '3–20 characters • letters, numbers, and _ • globally unique • restricted and reserved names are blocked',
        textScaler: TextScaler.noScaling,
        style: GakujiText.deckMeta.copyWith(
          color: context.gakujiColors.mediumGray,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _cooldownCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: GakujiColors.reading.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GakujiColors.reading.withValues(alpha: 0.24),
          width: 1.5,
        ),
      ),
      child: Text(
        _cooldownActive
            ? '${_cooldownRemainingText()} Your previous username remains reserved until the same cooldown ends.'
            : 'After a username change, you must wait 14 days before changing it again. Your previous username is reserved for those same 14 days.',
        textScaler: TextScaler.noScaling,
        style: GakujiText.deckMeta.copyWith(
          color: context.gakujiColors.mediumGray,
          height: 1.4,
        ),
      ),
    );
  }

  String _cooldownRemainingText() {
    final availableAt = _profile?.usernameChangeAvailableAt;
    if (availableAt == null) return 'Username can be changed.';

    final remaining = availableAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return 'Username can be changed.';

    final days = (remaining.inHours / 24).ceil();
    if (days <= 1) return 'You can change your username again in less than a day.';
    return 'You can change your username again in $days days.';
  }
}
