import 'package:flutter/material.dart';

import '../services/review_settings.dart';
import '../widgets/gakuji_faded_scroll.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';

class ReviewLimitsPage extends StatefulWidget {
  const ReviewLimitsPage({super.key});

  @override
  State<ReviewLimitsPage> createState() => _ReviewLimitsPageState();
}

class _ReviewLimitsPageState extends State<ReviewLimitsPage> {
  ReviewSettings settings = ReviewSettings.defaults;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final loaded = await ReviewSettingsStore.load();
    if (!mounted) return;

    setState(() {
      settings = loaded;
      loading = false;
    });
  }

  Future<void> _setNewLimit(int value) async {
    final updated = settings.copyWith(newLimit: value);
    await ReviewSettingsStore.save(updated);
    if (!mounted) return;
    setState(() => settings = updated);
  }

  Future<void> _setReviewLimit(int value) async {
    final updated = settings.copyWith(reviewLimit: value);
    await ReviewSettingsStore.save(updated);
    if (!mounted) return;
    setState(() => settings = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: GakujiColors.deckBlue,
                      ),
                    )
                  : GakujiFadedScroll(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                        children: [
                          _limitCard(
                            title: 'New Limit',
                            description:
                                'Learning cards count toward this limit until they graduate.',
                            value: settings.newLimit,
                            onChanged: _setNewLimit,
                          ),
                          const SizedBox(height: 16),
                          _limitCard(
                            title: 'Review Limit',
                            description:
                                'The maximum number of due Review cards shown each day.',
                            value: settings.reviewLimit,
                            onChanged: _setReviewLimit,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return GakujiTopBar(
      leftIcon: GakujiTopBar.backIcon,
      leftIconSize: GakujiTopBar.backIconSize,
      leftIconColor: GakujiColors.darkGray,
      onLeftTap: () => Navigator.pop(context),
      title: 'Review Limits',
      titleStyle: GakujiText.large.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }

  Widget _limitCard({
    required String title,
    required String description,
    required int value,
    required Future<void> Function(int value) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      decoration: BoxDecoration(
        color: GakujiColors.warmCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: GakujiColors.warmDivider,
          width: 1.5,
        ),
        boxShadow: [GakujiShadows.soft],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.medium.copyWith(
                    color: GakujiColors.darkGray,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  textScaler: TextScaler.noScaling,
                  style: GakujiText.xSmall.copyWith(
                    color: GakujiColors.mediumGray,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _stepper(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _stepper({
    required int value,
    required Future<void> Function(int value) onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepButton(
          icon: Icons.remove_rounded,
          enabled: value > 0,
          onTap: () => onChanged((value - 5).clamp(0, 9999).toInt()),
        ),
        SizedBox(
          width: 54,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: GakujiText.medium.copyWith(
              color: GakujiColors.darkGray,
            ),
          ),
        ),
        _stepButton(
          icon: Icons.add_rounded,
          enabled: value < 9999,
          onTap: () => onChanged((value + 5).clamp(0, 9999).toInt()),
        ),
      ],
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled
          ? GakujiColors.deckBlue.withValues(alpha: 0.12)
          : GakujiColors.softBorder.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icon,
            size: 24,
            color: enabled
                ? GakujiColors.deckBlue
                : GakujiColors.mediumGray.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}
