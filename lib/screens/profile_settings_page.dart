import 'package:flutter/material.dart';

import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';

class ProfileSettingsPage extends StatelessWidget {
  const ProfileSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            const Expanded(
              child: SizedBox.shrink(),
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
      title: 'Profile',
      titleStyle: GakujiText.large.copyWith(
        color: GakujiColors.darkGray,
      ),
    );
  }
}
