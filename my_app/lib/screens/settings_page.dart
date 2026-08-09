import 'package:flutter/material.dart';

import '../services/app_theme_controller.dart';
import '../services/review_settings.dart';
import '../widgets/gakuji_faded_scroll.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import 'profile_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ThemeMode selectedThemeMode = ThemeMode.light;
  ThemeMode savedThemeMode = ThemeMode.light;

  ReviewSettings reviewSettings = ReviewSettings.defaults;
  ReviewSettings savedReviewSettings = ReviewSettings.defaults;

  bool isLoadingSettings = true;
  bool isSavingSettings = false;

  @override
  void initState() {
    super.initState();

    selectedThemeMode = appThemeController.themeMode;
    savedThemeMode = appThemeController.themeMode;

    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final loadedSettings = await ReviewSettingsStore.load();

    if (!mounted) return;

    setState(() {
      reviewSettings = loadedSettings;
      savedReviewSettings = loadedSettings;
      isLoadingSettings = false;
    });
  }

  bool get hasUnsavedChanges {
    return selectedThemeMode != savedThemeMode ||
        reviewSettings.newLimit != savedReviewSettings.newLimit ||
        reviewSettings.reviewLimit != savedReviewSettings.reviewLimit;
  }

  void _changeReviewLimit({
    required bool isNewCardLimit,
    required int change,
  }) {
    final currentValue = isNewCardLimit
        ? reviewSettings.newLimit
        : reviewSettings.reviewLimit;
    final updatedValue = (currentValue + change).clamp(0, 9999).toInt();

    if (updatedValue == currentValue) return;

    final updatedSettings = isNewCardLimit
        ? reviewSettings.copyWith(newLimit: updatedValue)
        : reviewSettings.copyWith(reviewLimit: updatedValue);

    setState(() {
      reviewSettings = updatedSettings;
    });
  }

  Future<void> _saveChanges() async {
    if (isSavingSettings || isLoadingSettings || !hasUnsavedChanges) {
      return;
    }

    setState(() {
      isSavingSettings = true;
    });

    try {
      await Future.wait([
        ReviewSettingsStore.save(reviewSettings),
        appThemeController.saveThemeMode(selectedThemeMode),
      ]);

      if (!mounted) return;

      setState(() {
        savedThemeMode = selectedThemeMode;
        savedReviewSettings = reviewSettings;
        isSavingSettings = false;
      });

      _showTemporaryMessage('Settings saved');
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isSavingSettings = false;
      });

      _showTemporaryMessage('Could not save settings');
    }
  }

  Future<bool> _handleBack() async {
    if (isSavingSettings) return false;
    if (!hasUnsavedChanges) return true;

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: dialogContext.gakujiColors.warmCard,
          title: Text(
            'Discard changes?',
            textScaler: TextScaler.noScaling,
            style: GakujiText.medium.copyWith(
              color: context.gakujiColors.darkGray,
            ),
          ),
          content: Text(
            'Your settings changes have not been saved yet.',
            textScaler: TextScaler.noScaling,
            style: GakujiText.small.copyWith(
              color: context.gakujiColors.mediumGray,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                textScaler: TextScaler.noScaling,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Discard',
                textScaler: TextScaler.noScaling,
              ),
            ),
          ],
        );
      },
    );

    if (!(shouldDiscard ?? false)) return false;

    setState(() {
      selectedThemeMode = savedThemeMode;
      reviewSettings = savedReviewSettings;
    });

    appThemeController.previewThemeMode(savedThemeMode);

    return true;
  }

  Future<void> _handleBackTap() async {
    final canLeave = await _handleBack();

    if (!mounted || !canLeave) return;

    Navigator.pop(context);
  }

  void _showTemporaryMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1300),
          backgroundColor: Colors.black.withOpacity(0.86),
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
    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        backgroundColor: context.gakujiColors.warmBackground,
      body: Column(
        children: [
          _settingsHeader(context),
          Expanded(
            child: GakujiFadedScroll(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                children: [
                  _profileCard(),
                  const SizedBox(height: 28),
                  _sectionTitle('Theme'),
                  const SizedBox(height: 12),
                  _themeDropdown(),
                  const SizedBox(height: 28),
                  _sectionTitle('Daily Review Limits'),
                  const SizedBox(height: 12),
                  _limitControl(
                    label: 'New card limit',
                    value: reviewSettings.newLimit,
                    onDecrease: () {
                      _changeReviewLimit(
                        isNewCardLimit: true,
                        change: -5,
                      );
                    },
                    onIncrease: () {
                      _changeReviewLimit(
                        isNewCardLimit: true,
                        change: 5,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _limitControl(
                    label: 'Review card limit',
                    value: reviewSettings.reviewLimit,
                    onDecrease: () {
                      _changeReviewLimit(
                        isNewCardLimit: false,
                        change: -5,
                      );
                    },
                    onIncrease: () {
                      _changeReviewLimit(
                        isNewCardLimit: false,
                        change: 5,
                      );
                    },
                  ),
                  const SizedBox(height: 56),
                  _aboutButton(),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _settingsHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GakujiTopBar(
            leftIcon: GakujiTopBar.backIcon,
            leftIconSize: GakujiTopBar.backIconSize,
            leftIconColor: context.gakujiColors.darkGray,
            onLeftTap: _handleBackTap,
            title: 'Settings',
            titleStyle: GakujiText.large.copyWith(
              color: context.gakujiColors.darkGray,
            ),
            rightWidget: _topRightAction(),
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _topRightAction() {
    return TextButton(
      onPressed: isSavingSettings || isLoadingSettings
          ? null
          : hasUnsavedChanges
              ? _saveChanges
              : _handleBackTap,
      style: TextButton.styleFrom(
        foregroundColor: hasUnsavedChanges
            ? GakujiColors.deckBlue
            : context.gakujiColors.softGray,
        disabledForegroundColor: context.gakujiColors.softGray,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(76, 44),
      ),
      child: Text(
        isSavingSettings
            ? 'Saving'
            : hasUnsavedChanges
                ? 'Save'
                : 'Cancel',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 16,
          height: 1,
          fontWeight:
              hasUnsavedChanges ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
    );
  }

  Widget _profileCard() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ProfileSettingsPage(),
          ),
        );
      },
      child: Container(
        height: 92,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
        decoration: BoxDecoration(
          color: context.gakujiColors.warmCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: context.gakujiColors.warmDivider,
            width: 1.5,
          ),
          boxShadow: [GakujiShadows.soft],
        ),
        child: Row(
          children: [
            _profileIcon(),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                'Profile',
                textScaler: TextScaler.noScaling,
                style: GakujiText.medium.copyWith(
                  color: context.gakujiColors.darkGray,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.gakujiColors.darkGray,
              size: 36,
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileIcon() {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        color: context.gakujiColors.softBorder,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        color: context.gakujiColors.mediumGray,
        size: 46,
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      textScaler: TextScaler.noScaling,
      style: GakujiText.medium.copyWith(
        color: context.gakujiColors.darkGray,
      ),
    );
  }

  Widget _themeDropdown() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: _settingsControlDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ThemeMode>(
          value: selectedThemeMode,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          dropdownColor: context.gakujiColors.warmCard,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: context.gakujiColors.darkGray,
          ),
          style: GakujiText.small.copyWith(
            color: context.gakujiColors.darkGray,
          ),
          items: const [
            DropdownMenuItem(
              value: ThemeMode.light,
              child: Text(
                'Light mode',
                textScaler: TextScaler.noScaling,
              ),
            ),
            DropdownMenuItem(
              value: ThemeMode.dark,
              child: Text(
                'Dark mode',
                textScaler: TextScaler.noScaling,
              ),
            ),
          ],
          onChanged: isSavingSettings || isLoadingSettings
              ? null
              : (value) {
                  if (value == null) return;

                  setState(() {
                    selectedThemeMode = value;
                  });

                  appThemeController.previewThemeMode(value);
                },
        ),
      ),
    );
  }

  BoxDecoration _settingsControlDecoration() {
    return BoxDecoration(
      color: context.gakujiColors.warmCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: context.gakujiColors.warmDivider,
        width: 1.5,
      ),
      boxShadow: [GakujiShadows.soft],
    );
  }

  Widget _limitControl({
    required String label,
    required int value,
    required VoidCallback onDecrease,
    required VoidCallback onIncrease,
  }) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: _settingsControlDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: context.gakujiColors.darkGray,
              ),
            ),
          ),
          _limitStepButton(
            icon: Icons.remove_rounded,
            enabled: value > 0,
            onTap: onDecrease,
          ),
          SizedBox(
            width: 54,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: context.gakujiColors.darkGray,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _limitStepButton(
            icon: Icons.add_rounded,
            enabled: value < 9999,
            onTap: onIncrease,
          ),
        ],
      ),
    );
  }

  Widget _limitStepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final buttonColor = enabled
        ? GakujiColors.deckBlue.withOpacity(0.12)
        : context.gakujiColors.softBorder.withOpacity(0.45);
    final iconColor = enabled
        ? GakujiColors.deckBlue
        : context.gakujiColors.mediumGray.withOpacity(0.45);

    return Material(
      color: buttonColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        splashColor: GakujiColors.deckBlue.withOpacity(0.10),
        highlightColor: GakujiColors.deckBlue.withOpacity(0.05),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 23,
            color: iconColor,
          ),
        ),
      ),
    );
  }

  Widget _aboutButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: GakujiColors.deckBlue,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Version, credits, app information',
              textScaler: TextScaler.noScaling,
              style: GakujiText.small.copyWith(
                color: GakujiColors.deckBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: GakujiColors.deckBlue,
            size: 28,
          ),
        ],
      ),
    );
  }
}
