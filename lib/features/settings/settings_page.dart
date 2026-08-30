import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_page_route.dart';

import 'package:gakuji/features/auth/services/account_username_service.dart';
import 'package:gakuji/core/services/app_theme_controller.dart';
import 'package:gakuji/data/sync/gakuji_local_preferences.dart';
import 'package:gakuji/data/sync/gakuji_user_repository.dart';
import 'package:gakuji/data/review/review_settings.dart';
import 'package:gakuji/core/widgets/gakuji_faded_scroll.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/auth/profile_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const String blueCardTextPreferenceKey =
      GakujiLocalPreferences.blueCardTextPreferenceKey;
  static const String _profileIconPreferenceKey = 'profile_icon_index';
  static const int reviewLimitStep = 5;

  static const List<Color> _profileColors = [
    GakujiColors.reading,
    GakujiColors.writing,
    GakujiColors.hybrid,
  ];

  ThemeMode selectedThemeMode = ThemeMode.light;
  ThemeMode savedThemeMode = ThemeMode.light;
  GakujiTextSize selectedTextSize = GakujiTextSize.small;
  GakujiTextSize savedTextSize = GakujiTextSize.small;

  ReviewSettings reviewSettings = ReviewSettings.defaults;
  ReviewSettings savedReviewSettings = ReviewSettings.defaults;

  bool selectedBlueCardText = false;
  bool savedBlueCardText = false;

  bool isLoadingSettings = true;
  bool isSavingSettings = false;

  int _accountProfileIconIndex = 0;
  String? _accountUsername;

  bool get _isGuest => FirebaseAuth.instance.currentUser?.isAnonymous == true;

  String get _accountCardLabel {
    if (_isGuest) return 'Guest';
    final username = _accountUsername?.trim();
    if (username == null || username.isEmpty) return 'Account';
    return username;
  }

  @override
  void initState() {
    super.initState();

    selectedThemeMode = appThemeController.themeMode;
    savedThemeMode = appThemeController.themeMode;
    selectedTextSize = appThemeController.textSize;
    savedTextSize = appThemeController.textSize;

    final cachedBlueCardText =
        GakujiLocalPreferences.peekBool(blueCardTextPreferenceKey);
    if (cachedBlueCardText != null) {
      selectedBlueCardText = cachedBlueCardText;
      savedBlueCardText = cachedBlueCardText;
    }

    _accountUsername = _isGuest
        ? null
        : GakujiUsernameService.cachedCurrentProfile?.username;

    _loadSettings();
    _loadAccountCardIdentity();
  }

  Future<void> _loadAccountCardIdentity() async {
    var profileIconIndex = int.tryParse(
      await GakujiUserRepository.loadPreference(_profileIconPreferenceKey) ?? '',
    );

    profileIconIndex = (profileIconIndex ?? 0)
        .clamp(0, _profileColors.length - 1)
        .toInt();

    final username = _isGuest
        ? null
        : GakujiUsernameService.cachedCurrentProfile?.username;

    if (!mounted) return;

    setState(() {
      _accountProfileIconIndex = profileIconIndex!;
      _accountUsername = username;
    });
  }

  Future<void> _openAccountPage() async {
    await Navigator.push(
      context,
      GakujiPageRoute(
        builder: (_) => ProfileSettingsPage(
          initialUsername: _accountUsername,
        ),
      ),
    );

    if (!mounted) return;
    await _loadAccountCardIdentity();
  }

  Future<void> _loadSettings() async {
    final loadedSettings = await ReviewSettingsStore.load();
    final loadedBlueCardText =
        await GakujiLocalPreferences.loadBool(blueCardTextPreferenceKey) ??
            false;

    if (!mounted) return;

    setState(() {
      reviewSettings = loadedSettings;
      savedReviewSettings = loadedSettings;
      selectedBlueCardText = loadedBlueCardText;
      savedBlueCardText = loadedBlueCardText;
      isLoadingSettings = false;
    });
  }

  bool get hasUnsavedChanges {
    return selectedThemeMode != savedThemeMode ||
        selectedTextSize != savedTextSize ||
        selectedBlueCardText != savedBlueCardText ||
        reviewSettings.newLimit != savedReviewSettings.newLimit ||
        reviewSettings.reviewLimit != savedReviewSettings.reviewLimit;
  }

  void _setReviewLimit({
    required bool isNewCardLimit,
    required int value,
  }) {
    final sanitizedValue = value.clamp(0, 9999).toInt();
    final currentValue = isNewCardLimit
        ? reviewSettings.newLimit
        : reviewSettings.reviewLimit;

    if (sanitizedValue == currentValue) return;

    setState(() {
      reviewSettings = isNewCardLimit
          ? reviewSettings.copyWith(newLimit: sanitizedValue)
          : reviewSettings.copyWith(reviewLimit: sanitizedValue);
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
        appThemeController.saveTextSize(selectedTextSize),
        GakujiLocalPreferences.saveBool(
          blueCardTextPreferenceKey,
          selectedBlueCardText,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        savedThemeMode = selectedThemeMode;
        savedTextSize = selectedTextSize;
        savedReviewSettings = reviewSettings;
        savedBlueCardText = selectedBlueCardText;
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
            style: GakujiText.sectionTitle.copyWith(
              color: dialogContext.gakujiColors.darkGray,
            ),
          ),
          content: Text(
            'Your settings changes have not been saved yet.',
            textScaler: TextScaler.noScaling,
            style: GakujiText.body.copyWith(
              color: dialogContext.gakujiColors.mediumGray,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Cancel',
                textScaler: TextScaler.noScaling,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
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
      selectedTextSize = savedTextSize;
      reviewSettings = savedReviewSettings;
      selectedBlueCardText = savedBlueCardText;
    });

    appThemeController.previewThemeMode(savedThemeMode);
    appThemeController.previewTextSize(savedTextSize);

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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldPop = await _handleBack();

        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: context.gakujiColors.warmBackground,
        body: Column(
          children: [
            _settingsHeader(context),
            Expanded(
              child: GakujiFadedScroll(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
                  children: [
                    _profileCard(),
                    const SizedBox(height: 28),
                    _sectionTitle('Appearance'),
                    const SizedBox(height: 12),
                    _toggleSettingRow(
                      label: 'Dark mode',
                      value: selectedThemeMode == ThemeMode.dark,
                      onChanged: isSavingSettings || isLoadingSettings
                          ? null
                          : (enabled) {
                              final updatedMode = enabled
                                  ? ThemeMode.dark
                                  : ThemeMode.light;

                              setState(() {
                                selectedThemeMode = updatedMode;
                              });

                              appThemeController.previewThemeMode(updatedMode);
                            },
                    ),
                    const SizedBox(height: 12),
                    _toggleSettingRow(
                      label: 'Blue Card Text',
                      value: selectedBlueCardText,
                      onChanged: isSavingSettings || isLoadingSettings
                          ? null
                          : (enabled) {
                              setState(() {
                                selectedBlueCardText = enabled;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    _fontSizeSettingRow(),
                    const SizedBox(height: 28),
                    _sectionTitle('Daily Review Limits'),
                    const SizedBox(height: 12),
                    _limitSettingRow(
                      label: 'New card limit',
                      value: reviewSettings.newLimit,
                      onTap: () => _openLimitPicker(isNewCardLimit: true),
                    ),
                    const SizedBox(height: 12),
                    _limitSettingRow(
                      label: 'Review card limit',
                      value: reviewSettings.reviewLimit,
                      onTap: () => _openLimitPicker(isNewCardLimit: false),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(28, 0, 28, 18),
              child: _aboutButton(),
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
            titleStyle: GakujiText.pageTitle.copyWith(
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
    if (!hasUnsavedChanges && !isSavingSettings) {
      return const SizedBox(width: 76, height: 44);
    }

    return TextButton(
      onPressed: isSavingSettings || isLoadingSettings ? null : _saveChanges,
      style: TextButton.styleFrom(
        foregroundColor: GakujiColors.reading,
        disabledForegroundColor: context.gakujiColors.softGray,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(76, 44),
      ),
      child: Text(
        isSavingSettings ? 'Saving' : 'Save',
        textScaler: TextScaler.noScaling,
        style: GakujiText.actionLabel.copyWith(
          color: GakujiColors.reading,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _profileCard() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openAccountPage,
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
                _accountCardLabel,
                textScaler: TextScaler.noScaling,
                style: _settingsSubheaderStyle(),
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
    final colorIndex = _accountProfileIconIndex.clamp(
      0,
      _profileColors.length - 1,
    );

    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        color: _profileColors[colorIndex],
        shape: BoxShape.circle,
        boxShadow: [GakujiShadows.soft],
      ),
      child: Icon(
        Icons.person_rounded,
        color: context.gakujiColors.warmCard,
        size: 44,
      ),
    );
  }

  TextStyle _settingsSubheaderStyle() {
    final baseStyle = GakujiText.actionLabel;
    return baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 16) + 2,
      color: context.gakujiColors.darkGray,
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      textScaler: TextScaler.noScaling,
      style: _settingsSubheaderStyle(),
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

  Widget _toggleSettingRow({
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
      decoration: _settingsControlDecoration(),
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
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: GakujiColors.reading,
          ),
        ],
      ),
    );
  }

  String _fontSizeLabel(GakujiTextSize size) {
    switch (size) {
      case GakujiTextSize.small:
        return 'Small';
      case GakujiTextSize.medium:
        return 'Medium';
      case GakujiTextSize.large:
        return 'Large';
    }
  }

  Widget _fontSizeSettingRow() {
    final disabled = isSavingSettings || isLoadingSettings;

    return Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
      decoration: _settingsControlDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<GakujiTextSize>(
          value: selectedTextSize,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          dropdownColor: context.gakujiColors.warmCard,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: disabled
                ? context.gakujiColors.softGray
                : context.gakujiColors.mediumGray,
            size: 30,
          ),
          selectedItemBuilder: (context) {
            return GakujiTextSize.values.map((size) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      'Font Size',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: GakujiText.actionLabel.copyWith(
                        color: disabled
                            ? context.gakujiColors.softGray
                            : context.gakujiColors.darkGray,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _fontSizeLabel(size),
                    textScaler: TextScaler.noScaling,
                    style: GakujiText.actionLabel.copyWith(
                      color: disabled
                          ? context.gakujiColors.softGray
                          : context.gakujiColors.mediumGray,
                    ),
                  ),
                ],
              );
            }).toList();
          },
          items: GakujiTextSize.values.map((size) {
            return DropdownMenuItem<GakujiTextSize>(
              value: size,
              child: Text(
                _fontSizeLabel(size),
                textScaler: TextScaler.noScaling,
                style: GakujiText.actionLabel.copyWith(
                  color: context.gakujiColors.darkGray,
                ),
              ),
            );
          }).toList(),
          onChanged: disabled
              ? null
              : (value) {
                  if (value == null || value == selectedTextSize) return;

                  setState(() {
                    selectedTextSize = value;
                  });

                  appThemeController.previewTextSize(value);
                },
        ),
      ),
    );
  }

  Widget _limitSettingRow({
    required String label,
    required int value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isSavingSettings || isLoadingSettings ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: GakujiColors.reading.withValues(alpha: 0.08),
        highlightColor: GakujiColors.reading.withValues(alpha: 0.04),
        child: Ink(
          height: 54,
          padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
          decoration: _settingsControlDecoration(),
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
              Text(
                '$value',
                textScaler: TextScaler.noScaling,
                style: GakujiText.actionLabel.copyWith(
                  color: context.gakujiColors.mediumGray,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: context.gakujiColors.mediumGray,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLimitPicker({
    required bool isNewCardLimit,
  }) async {
    final currentValue = isNewCardLimit
        ? reviewSettings.newLimit
        : reviewSettings.reviewLimit;
    final title = isNewCardLimit ? 'New Card Limit' : 'Review Card Limit';

    final pickedValue = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var workingValue = currentValue;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            void changeWorkingValue(int change) {
              final updatedValue =
                  (workingValue + change).clamp(0, 9999).toInt();

              if (updatedValue == workingValue) return;

              setSheetState(() {
                workingValue = updatedValue;
              });
            }

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
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: sheetContext.gakujiColors.softBorder,
                          borderRadius: BorderRadius.circular(
                            GakujiRadius.pill,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.sectionTitle.copyWith(
                            color: sheetContext.gakujiColors.darkGray,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Daily maximum',
                          textScaler: TextScaler.noScaling,
                          style: GakujiText.deckMeta.copyWith(
                            color: sheetContext.gakujiColors.mediumGray,
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _limitPickerStepButton(
                            icon: Icons.remove_rounded,
                            enabled: workingValue > 0,
                            onTap: () => changeWorkingValue(
                              -reviewLimitStep,
                            ),
                          ),
                          SizedBox(
                            width: 118,
                            child: Text(
                              '$workingValue',
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.noScaling,
                              style: GakujiText.large.copyWith(
                                color: sheetContext.gakujiColors.darkGray,
                              ),
                            ),
                          ),
                          _limitPickerStepButton(
                            icon: Icons.add_rounded,
                            enabled: workingValue < 9999,
                            onTap: () => changeWorkingValue(reviewLimitStep),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: _sheetActionButton(
                              label: 'Cancel',
                              filled: false,
                              onTap: () => Navigator.of(sheetContext).pop(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _sheetActionButton(
                              label: 'Use Limit',
                              filled: true,
                              onTap: () => Navigator.of(sheetContext).pop(
                                workingValue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || pickedValue == null) return;

    _setReviewLimit(
      isNewCardLimit: isNewCardLimit,
      value: pickedValue,
    );
  }

  Widget _limitPickerStepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled
          ? GakujiColors.reading.withValues(alpha: 0.12)
          : context.gakujiColors.softBorder.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        splashColor: GakujiColors.reading.withValues(alpha: 0.10),
        highlightColor: GakujiColors.reading.withValues(alpha: 0.05),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            size: 28,
            color: enabled
                ? GakujiColors.reading
                : context.gakujiColors.mediumGray.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }

  Widget _sheetActionButton({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final backgroundColor =
        filled ? GakujiColors.reading : context.gakujiColors.warmCard;
    final foregroundColor =
        filled ? Colors.white : context.gakujiColors.darkGray;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: filled
              ? GakujiColors.reading
              : context.gakujiColors.warmDivider,
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
              style: GakujiText.actionLabel.copyWith(
                color: foregroundColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _aboutButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(12),
        splashColor: GakujiColors.reading.withValues(alpha: 0.08),
        highlightColor: GakujiColors.reading.withValues(alpha: 0.04),
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: GakujiColors.reading,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'About Gakuji',
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.actionLabel.copyWith(
                    color: GakujiColors.reading,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: GakujiColors.reading,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
