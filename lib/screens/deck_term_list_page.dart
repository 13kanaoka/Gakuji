import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/term.dart';
import '../widgets/gakuji_top_bar.dart';
import 'dictionary_detail_page.dart';

class DeckTermListPage extends StatelessWidget {
  static const Color deckBlue = Color(0xFF4D7EF7);
  static const Color dividerGray = Color(0xFFC8C8C8);
  static const Color metadataGray = Color(0xFF6F6F6F);

  final Deck deck;

  const DeckTermListPage({
    super.key,
    required this.deck,
  });

  @override
  Widget build(BuildContext context) {
    final terms = deck.terms;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            GakujiTopBar(
              leftIcon: Icons.arrow_back_ios_new,
              onLeftTap: () => Navigator.pop(context),
              title: 'Terms',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
              child: _header(terms.length),
            ),
            Expanded(
              child: terms.isEmpty
                  ? const Center(
                      child: Text(
                        'No terms yet',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : _termList(context, terms),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(int termsCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          deck.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            fontSize: 34,
            height: 0.98,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$termsCount terms',
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            fontSize: 16,
            height: 1,
            fontWeight: FontWeight.w500,
            color: metadataGray,
          ),
        ),
      ],
    );
  }

  Widget _termList(BuildContext context, List<Term> terms) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Colors.black,
            Colors.black,
            Color(0x00000000),
          ],
          stops: [
            0.0,
            0.035,
            0.94,
            1.0,
          ],
        ).createShader(bounds);
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 120),
        itemCount: terms.length,
        separatorBuilder: (context, index) {
          return const Divider(
            height: 1,
            thickness: 1,
            color: dividerGray,
          );
        },
        itemBuilder: (context, index) {
          final term = terms[index];

          return _TermListTile(
            term: term,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DictionaryDetailPage(word: term),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TermListTile extends StatelessWidget {
  static const Color deckBlue = Color(0xFF4D7EF7);

  final Term term;
  final VoidCallback onTap;

  const _TermListTile({
    required this.term,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleText =
        term.kanjiBracketText.isNotEmpty ? term.kanjiBracketText : term.kanji;
    final readingText = term.reading.trim();

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 9, 0, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 10,
                      runSpacing: 0,
                      children: [
                        Text(
                          titleText,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        if (readingText.isNotEmpty)
                          Text(
                            '【$readingText】',
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              fontSize: 19,
                              height: 1,
                              fontWeight: FontWeight.w600,
                              color: deckBlue,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      term.cardMeaning,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.1,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right,
                size: 27,
                color: Color(0xFF8A8A8A),
              ),
            ],
          ),
        ),
      ),
    );
  }
}