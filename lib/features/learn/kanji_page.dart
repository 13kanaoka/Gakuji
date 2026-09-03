import 'package:flutter/material.dart';

import 'package:gakuji/core/widgets/gakuji_deck_transition.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';

class KanjiPage extends StatelessWidget {
  const KanjiPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: gakujiLearningHeroTag('kanji'),
      createRectTween: gakujiDeckRectTween,
      flightShuttleBuilder: gakujiDeckFlightShuttleBuilder,
      child: Material(
        type: MaterialType.transparency,
        child: Scaffold(
          backgroundColor: GakujiColors.warmBackground,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                GakujiTopBar(
                  leftIcon: Icons.close_rounded,
                  leftIconSize: GakujiTopBar.iconSize,
                  leftIconColor: GakujiColors.darkGray,
                  onLeftTap: () => Navigator.of(context).pop(),
                  title: 'Kanji',
                  titleStyle: GakujiText.pageTitle.copyWith(
                    color: GakujiColors.darkGray,
                  ),
                ),
                const Expanded(
                  child: SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
