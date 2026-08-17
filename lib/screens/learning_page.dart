import 'package:flutter/material.dart';

import '../widgets/gakuji_learning_card.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';
import 'kana_page.dart';
import 'kanji_page.dart';

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
              titleStyle: GakujiText.large.copyWith(
                color: GakujiColors.darkGray,
              ),
            ),
            const SizedBox(height: 54),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  22,
                  0,
                  22,
                  GakujiSpacing.pageBottom,
                ),
                child: Column(
                  children: [
                    GakujiLearningCard(
                      label: 'Kana',
                      subtitle: 'Practice Hiragana\nand Katakana',
                      backgroundAsset:
                          'assets/images/learning_kana_pattern.png',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => const KanaPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    GakujiLearningCard(
                      label: 'Kanji',
                      subtitle: 'Practice Kanji\nand Readings',
                      backgroundAsset:
                          'assets/images/learning_kanji_pattern.png',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => const KanjiPage(),
                          ),
                        );
                      },
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
