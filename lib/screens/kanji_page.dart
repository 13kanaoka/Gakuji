import 'package:flutter/material.dart';

import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';

class KanjiPage extends StatelessWidget {
  const KanjiPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            GakujiTopBar(
              leftIcon: GakujiTopBar.backIcon,
              leftIconSize: GakujiTopBar.backIconSize,
              leftIconColor: GakujiColors.darkGray,
              onLeftTap: () => Navigator.of(context).pop(),
              title: 'Kanji',
              titleStyle: GakujiText.large.copyWith(
                color: GakujiColors.darkGray,
              ),
            ),
            const Expanded(
              child: SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
