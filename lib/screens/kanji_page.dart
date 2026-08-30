import 'package:flutter/material.dart';

import 'package:gakuji/widgets/gakuji_deck_transition.dart';
import 'package:gakuji/widgets/gakuji_styles.dart';
import 'package:gakuji/widgets/gakuji_top_bar.dart';

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
                  leftIcon: GakujiTopBar.backIcon,
                  leftIconSize: GakujiTopBar.backIconSize,
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
