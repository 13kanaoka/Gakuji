import 'package:flutter/material.dart';
import 'package:gakuji/core/widgets/gakuji_deck_transition.dart';

import 'package:gakuji/features/learn/widgets/gakuji_learning_card.dart';
import 'package:gakuji/core/theme/gakuji_styles.dart';
import 'package:gakuji/core/widgets/gakuji_top_bar.dart';
import 'package:gakuji/features/learn/kana_page.dart';
import 'package:gakuji/features/learn/kanji_page.dart';

class LearningPage extends StatelessWidget {
  const LearningPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            GakujiTopBar(
              title: 'Learning',
              titleStyle: GakujiText.pageTitle.copyWith(
                color: GakujiColors.darkGray,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  GakujiSpacing.contentHorizontal,
                  0,
                  GakujiSpacing.contentHorizontal,
                  GakujiSpacing.pageBottom,
                ),
                child: Column(
                  children: [
                    Hero(
                      tag: gakujiLearningHeroTag('kana'),
                      createRectTween: gakujiDeckRectTween,
                      flightShuttleBuilder: gakujiDeckFlightShuttleBuilder,
                      child: Material(
                        type: MaterialType.transparency,
                        child: GakujiLearningCard(
                          label: 'Kana',
                          subtitle: 'Practice Hiragana\nand Katakana',
                          backgroundAsset:
                              'assets/images/learning_kana_pattern.png',
                          onTap: () {
                            Navigator.of(context).push(
                              gakujiLearningRoute<void>(
                                page: const KanaPage(),
                                enableSwipeBack: false,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Hero(
                      tag: gakujiLearningHeroTag('kanji'),
                      createRectTween: gakujiDeckRectTween,
                      flightShuttleBuilder: gakujiDeckFlightShuttleBuilder,
                      child: Material(
                        type: MaterialType.transparency,
                        child: GakujiLearningCard(
                          label: 'Kanji',
                          subtitle: 'Practice Kanji\nand Readings',
                          backgroundAsset:
                              'assets/images/learning_kanji_pattern.png',
                          onTap: () {
                            Navigator.of(context).push(
                              gakujiLearningRoute<void>(
                                page: const KanjiPage(),
                                enableSwipeBack: false,
                              ),
                            );
                          },
                        ),
                      ),
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
}
