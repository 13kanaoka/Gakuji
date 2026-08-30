import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/gakuji_page_route.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/account_auth_service.dart';
import '../services/account_username_service.dart';
import '../services/gakuji_cloud_sync_service.dart';
import '../services/gakuji_user_data_store.dart';
import '../services/gakuji_user_repository.dart';
import '../widgets/gakuji_action_dialog.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import 'account_information_page.dart';
import 'username_settings_page.dart';

class ProfileSettingsPage extends StatefulWidget {
  final String? initialUsername;

  const ProfileSettingsPage({
    super.key,
    this.initialUsername,
  });

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  static const String _profileIconPreferenceKey = 'profile_icon_index';

  static const List<Color> _temporaryProfileColors = [
    GakujiColors.reading,
    GakujiColors.writing,
    GakujiColors.hybrid,
  ];

  int selectedProfileIconIndex = 0;
  int savedProfileIconIndex = 0;

  String? accountUsername;
  bool _isDeletingAccount = false;

  bool get hasUnsavedChanges =>
      selectedProfileIconIndex != savedProfileIconIndex;

  bool get _isGuest => FirebaseAuth.instance.currentUser?.isAnonymous == true;

  @override
  void initState() {
    super.initState();
    accountUsername = _isGuest
        ? null
        : widget.initialUsername ??
            GakujiUsernameService.cachedCurrentProfile?.username;
    _loadProfileIcon();
  }

  Future<void> _loadProfileIcon() async {
    var savedIndex = int.tryParse(
      await GakujiUserRepository.loadPreference(_profileIconPreferenceKey) ?? '',
    );

    if (savedIndex == null) {
      // One-time migration from the old device-global preference.
      final prefs = await SharedPreferences.getInstance();
      final legacyIndex = prefs.getInt(_profileIconPreferenceKey);
      if (legacyIndex != null) {
        savedIndex = legacyIndex;
        await GakujiUserRepository.savePreference(
          key: _profileIconPreferenceKey,
          value: legacyIndex.toString(),
        );
        await prefs.remove(_profileIconPreferenceKey);
        GakujiCloudSyncService.schedulePush();
      }
    }

    final safeIndex = (savedIndex ?? 0)
        .clamp(0, _temporaryProfileColors.length - 1)
        .toInt();

    if (!mounted) return;

    setState(() {
      selectedProfileIconIndex = safeIndex;
      savedProfileIconIndex = safeIndex;
    });
  }

  String get _accountUsernameDisplay {
    if (_isGuest) return 'Guest';
    final username = accountUsername;
    if (username == null || username.isEmpty) return 'Set username';
    return username;
  }

  Future<void> _openProfileIconPicker() async {
    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomSafePadding = MediaQuery.paddingOf(sheetContext).bottom;

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              24,
              18,
              24,
              26 + bottomSafePadding,
            ),
            decoration: BoxDecoration(
              color: sheetContext.gakujiColors.warmCard,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border.all(
                color: sheetContext.gakujiColors.warmDivider,
                width: 1.2,
              ),
            ),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetHandle(sheetContext),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose Profile Icon',
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.sectionTitle.copyWith(
                        color: sheetContext.gakujiColors.darkGray,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      _temporaryProfileColors.length,
                      (index) => _profileIconChoice(
                        sheetContext,
                        index: index,
                        selected: index == selectedProfileIconIndex,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedIndex == null || !mounted) return;

    setState(() {
      selectedProfileIconIndex = selectedIndex;
    });
  }

  Future<void> _saveChanges() async {
    if (!hasUnsavedChanges) return;

    await GakujiUserRepository.savePreference(
      key: _profileIconPreferenceKey,
      value: selectedProfileIconIndex.toString(),
    );
    GakujiCloudSyncService.schedulePush();

    if (!mounted) return;

    setState(() {
      savedProfileIconIndex = selectedProfileIconIndex;
    });
  }

  Widget _profileIconChoice(
    BuildContext sheetContext, {
    required int index,
    required bool selected,
  }) {
    final color = _temporaryProfileColors[index];

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () => Navigator.pop(sheetContext, index),
        customBorder: const CircleBorder(),
        splashColor: color.withValues(alpha: 0.12),
        highlightColor: color.withValues(alpha: 0.06),
        child: Container(
          width: 82,
          height: 82,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? GakujiColors.reading : Colors.transparent,
              width: 3,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [GakujiShadows.soft],
            ),
            child: Icon(
              Icons.person_rounded,
              size: 48,
              color: sheetContext.gakujiColors.warmCard,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUsernameSettings() async {
    if (_isGuest) {
      _showTemporaryMessage('Create an account before choosing a username');
      return;
    }

    final changed = await Navigator.push<bool>(
      context,
      GakujiPageRoute(
        builder: (_) => const UsernameSettingsPage(),
      ),
    );

    if (!mounted || changed != true) return;

    setState(() {
      accountUsername = GakujiUsernameService.cachedCurrentProfile?.username;
    });

    _showTemporaryMessage('Username saved');
  }

  Future<void> _openAccountInformation() async {
    await Navigator.push(
      context,
      GakujiPageRoute(
        builder: (_) => const AccountInformationPage(),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    if (_isDeletingAccount || _isGuest) return;

    final confirmed = await showGakujiActionDialog(
      context: context,
      title: 'Delete Account?',
      message:
          'This permanently deletes your Gakuji account, synced study data, and sign-in access. Local data on this device will also be erased. Your username stays reserved for 14 days, then returns to the pool. This cannot be undone.',
      primaryLabel: 'Delete Account',
      primaryDestructive: true,
    );

    if (confirmed != true || !mounted) return;

    GakujiAuthProfile profile;
    try {
      profile = await GakujiAccountAuthService.loadCurrentProfile();
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      _showTemporaryMessage(error.message);
      return;
    }

    if (!mounted) return;

    String? currentPassword;
    if (profile.hasPassword) {
      currentPassword = await showGakujiPasswordConfirmationDialog(
        context: context,
        title: 'Confirm Password',
        message:
            'Enter your current password to confirm permanent account deletion.',
        primaryLabel: 'Delete Account',
        destructive: true,
      );

      if (currentPassword == null || !mounted) return;
    }

    setState(() {
      _isDeletingAccount = true;
    });

    try {
      await GakujiAccountAuthService.deleteCurrentAccount(
        currentPassword: currentPassword,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on GakujiAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isDeletingAccount = false;
      });
      _showTemporaryMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isDeletingAccount = false;
      });
      _showTemporaryMessage(
        'Could not delete the account. Nothing was removed locally.',
      );
    }
  }

  Widget _sheetHandle(BuildContext sheetContext) {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: sheetContext.gakujiColors.softBorder,
        borderRadius: BorderRadius.circular(GakujiRadius.pill),
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showGakujiActionDialog(
      context: context,
      title: _isGuest ? 'Leave Guest Session?' : 'Sign Out?',
      message: _isGuest
          ? 'Signing out will erase the guest study data stored on this device. Guest data is not synced and cannot be recovered.'
          : 'You will be signed out of Gakuji on this device. Your synced account data will remain available when you sign back in.',
      primaryLabel: 'Sign Out',
      primaryDestructive: true,
    );

    if (confirmed != true || !mounted) return;

    try {
      await GakujiUserDataStore.reset();
    } on GakujiUnsyncedDataException catch (error) {
      if (!mounted) return;
      _showTemporaryMessage(error.message);
      return;
    }

    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showTemporaryMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
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
          _header(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  _profileIcon(),
                  const SizedBox(height: 12),
                  Text(
                    _accountUsernameDisplay,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.deckMeta.copyWith(
                      color: context.gakujiColors.mediumGray,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Account Details',
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.actionLabel.copyWith(
                        fontSize: (GakujiText.actionLabel.fontSize ?? 16) + 2,
                        color: context.gakujiColors.darkGray,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_isGuest) ...[
                    _accountSettingRow(
                      label: 'Username',
                      trailingText: _accountUsernameDisplay,
                      onTap: _openUsernameSettings,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _accountSettingRow(
                    label: _isGuest ? 'Create Account' : 'Account Information',
                    onTap: _openAccountInformation,
                  ),
                  const Spacer(),
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      children: [
                        _signOutButton(),
                        if (!_isGuest) ...[
                          const SizedBox(height: 4),
                          _deleteAccountButton(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: GakujiTopBar(
        leftIcon: GakujiTopBar.backIcon,
        leftIconSize: GakujiTopBar.backIconSize,
        leftIconColor: context.gakujiColors.darkGray,
        onLeftTap: () => Navigator.pop(context),
        title: 'Account',
        titleStyle: GakujiText.pageTitle.copyWith(
          color: context.gakujiColors.darkGray,
        ),
        rightWidget: _topRightAction(),
      ),
    );
  }

  Widget _topRightAction() {
    if (!hasUnsavedChanges) {
      return const SizedBox(width: 76, height: 44);
    }

    return TextButton(
      onPressed: _saveChanges,
      style: TextButton.styleFrom(
        foregroundColor: GakujiColors.reading,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(76, 44),
      ),
      child: Text(
        'Save',
        textScaler: TextScaler.noScaling,
        style: GakujiText.actionLabel.copyWith(
          color: GakujiColors.reading,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _profileIcon() {
    final colorIndex = selectedProfileIconIndex.clamp(
      0,
      _temporaryProfileColors.length - 1,
    );
    final iconColor = _temporaryProfileColors[colorIndex];

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: _openProfileIconPicker,
        customBorder: const CircleBorder(),
        splashColor: iconColor.withValues(alpha: 0.12),
        highlightColor: iconColor.withValues(alpha: 0.06),
        child: Container(
          width: 134,
          height: 134,
          decoration: BoxDecoration(
            color: iconColor,
            shape: BoxShape.circle,
            boxShadow: [GakujiShadows.soft],
          ),
          child: Icon(
            Icons.person_rounded,
            size: 90,
            color: context.gakujiColors.warmCard,
          ),
        ),
      ),
    );
  }

  Widget _accountSettingRow({
    required String label,
    required VoidCallback onTap,
    String? trailingText,
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
          splashColor: GakujiColors.reading.withValues(alpha: 0.08),
          highlightColor: GakujiColors.reading.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.actionLabel.copyWith(
                      color: context.gakujiColors.darkGray,
                    ),
                  ),
                ),
                if (trailingText != null) ...[
                  Text(
                    trailingText,
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.actionLabel.copyWith(
                      color: context.gakujiColors.mediumGray,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  size: 30,
                  color: context.gakujiColors.mediumGray,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _signOutButton() {
    return _bottomAccountAction(
      icon: Icons.logout_rounded,
      label: 'Sign Out',
      onTap: _signOut,
    );
  }

  Widget _deleteAccountButton() {
    return _bottomAccountAction(
      icon: Icons.delete_outline_rounded,
      label: _isDeletingAccount ? 'Deleting Account...' : 'Delete Account',
      onTap: _isDeletingAccount ? () {} : _deleteAccount,
    );
  }

  Widget _bottomAccountAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: GakujiColors.pinRed.withValues(alpha: 0.08),
        highlightColor: GakujiColors.pinRed.withValues(alpha: 0.04),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Icon(icon, color: GakujiColors.pinRed, size: 28),
              const SizedBox(width: 10),
              Text(
                label,
                textScaler: TextScaler.noScaling,
                style: GakujiText.actionLabel.copyWith(
                  color: GakujiColors.pinRed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
