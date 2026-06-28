import 'package:flutter/material.dart';

import '../data/deck_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../widgets/gakuji_top_bar.dart';
import 'kanji_dictionary_detail_page.dart';

class DictionaryDetailPage extends StatefulWidget {
  final Term word;

  const DictionaryDetailPage({
    super.key,
    required this.word,
  });

  @override
  State<DictionaryDetailPage> createState() => _DictionaryDetailPageState();
}

class _DictionaryDetailPageState extends State<DictionaryDetailPage> {
  static const Color sectionColor = Color(0xFFEAF4E9);
  static const Color accentGreen = Color(0xFF6E9A3E);
  static const Color dividerColor = Color(0xFFE3E3E3);

  Deck get defaultDeck =>
      decks.firstWhere((deck) => deck.name == 'Gakuji test deck');

  String get sourceId => widget.word.sourceId ?? widget.word.id;

  bool deckContainsWord(Deck deck) {
    return deck.terms.any((term) => term.sourceId == sourceId);
  }

  Term copiedWordForDeck(Deck deck) {
    return Term.deckCopyFrom(
      widget.word,
      id: '${deck.id}_${sourceId}_${DateTime.now().microsecondsSinceEpoch}',
      marked: false,
    );
  }

  bool get isSaved {
    return deckContainsWord(defaultDeck);
  }

  void toggleDefaultDeck() {
    setState(() {
      if (isSaved) {
        defaultDeck.terms.removeWhere((term) => term.sourceId == sourceId);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from deck')),
        );
      } else {
        defaultDeck.terms.add(copiedWordForDeck(defaultDeck));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to Gakuji test deck')),
        );
      }
    });
  }

  void openDeckPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Choose Deck',
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ),
            const Divider(),
            ...decks.map((deck) {
              final exists = deckContainsWord(deck);

              return ListTile(
                title: Text(deck.name),
                trailing: exists
                    ? const Icon(
                        Icons.check,
                        color: Colors.green,
                      )
                    : null,
                onTap: () {
                  setState(() {
                    if (!exists) {
                      deck.terms.add(copiedWordForDeck(deck));
                    }
                  });

                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        exists
                            ? 'Already saved to ${deck.name}'
                            : 'Saved to ${deck.name}',
                      ),
                    ),
                  );
                },
              );
            }).toList(),
          ],
        );
      },
    );
  }

  void openKanjiDetail(Term word) {
    if (!word.hasKanjiDetails) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KanjiDictionaryDetailPage(
          kanjiEntry: word,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            GakujiTopBar(
              leftIcon: Icons.arrow_back_ios_new,
              onLeftTap: () => Navigator.pop(context),
              title: word.kanji,
              rightWidget: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _topActionButton(
                    icon: isSaved ? Icons.favorite : Icons.favorite_border,
                    iconColor: isSaved ? Colors.red : Colors.grey,
                    onTap: toggleDefaultDeck,
                  ),
                  const SizedBox(width: GakujiTopBar.actionGap),
                  _topActionButton(
                    icon: Icons.menu_book_outlined,
                    iconColor: Colors.black,
                    onTap: openDeckPicker,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  _entryHeader(word),
                  _noteSection(word),
                  _kanjiSection(word),
                  _examplesSection(word),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryHeader(Term word) {
    final definitions = word.displayDefinitions;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  word.kanji,
                  style: const TextStyle(
                    fontSize: 46,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    word.reading,
                    style: const TextStyle(
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (word.isCommon) _commonBadge(),
            ],
          ),
          const SizedBox(height: 34),
          Text(
            word.partOfSpeech,
            style: const TextStyle(
              fontSize: 25,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          ...definitions.asMap().entries.map((entry) {
            return _definitionRow(
              index: entry.key,
              definition: entry.value,
              relatedTerms: entry.key == definitions.length - 1
                  ? word.relatedTerms
                  : const [],
            );
          }),
        ],
      ),
    );
  }

  Widget _definitionRow({
    required int index,
    required String definition,
    required List<String> relatedTerms,
  }) {
    final letter = String.fromCharCode(65 + index);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                letter,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 24,
                  height: 1.25,
                  color: Colors.black,
                ),
                children: [
                  TextSpan(text: definition),
                  if (relatedTerms.isNotEmpty)
                    TextSpan(
                      text: ' (see also: ${relatedTerms.join(', ')})',
                      style: const TextStyle(color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _commonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: accentGreen,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'Common',
        style: TextStyle(
          fontSize: 18,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _noteSection(Term word) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Note'),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 30),
          child: Text(
            word.note ?? 'Write a note',
            style: TextStyle(
              fontSize: 22,
              color: word.note == null ? accentGreen : Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _kanjiSection(Term word) {
    final canOpenKanjiDetails = word.hasKanjiDetails;
    final firstCharacter = word.kanji.isEmpty ? '' : word.kanji.substring(0, 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Kanji'),
        InkWell(
          onTap: canOpenKanjiDetails ? () => openKanjiDetail(word) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    firstCharacter,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        word.kanjiMeaning,
                        style: const TextStyle(fontSize: 23),
                      ),
                      if (word.kunyomi.isNotEmpty)
                        Text(
                          word.kunyomi.join(', '),
                          style: const TextStyle(fontSize: 21),
                        ),
                      if (word.onyomi.isNotEmpty)
                        Text(
                          word.onyomi.join(', '),
                          style: const TextStyle(fontSize: 21),
                        ),
                    ],
                  ),
                ),
                if (canOpenKanjiDetails)
                  const Icon(
                    Icons.chevron_right,
                    size: 36,
                    color: Colors.grey,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _examplesSection(Term word) {
    final examples = word.examples;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Examples'),
        if (examples.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Text(
              'No examples yet',
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey,
              ),
            ),
          )
        else
          ...examples.asMap().entries.map((entry) {
            final isLast = entry.key == examples.length - 1;
            return _exampleRow(
              example: entry.value,
              showDivider: !isLast,
            );
          }),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: Text(
            'More Examples',
            style: TextStyle(
              fontSize: 22,
              color: accentGreen.withOpacity(0.65),
            ),
          ),
        ),
      ],
    );
  }

  Widget _exampleRow({
    required DictionaryExample example,
    required bool showDivider,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      example.reading,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.15,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      example.japanese,
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1.3,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      example.english,
                      style: const TextStyle(
                        fontSize: 25,
                        height: 1.18,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right,
                size: 34,
                color: Colors.grey,
              ),
            ],
          ),
          if (showDivider)
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Divider(
                height: 1,
                thickness: 1,
                color: dividerColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      width: double.infinity,
      color: sectionColor,
      padding: const EdgeInsets.fromLTRB(22, 7, 22, 7),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  Widget _topActionButton({
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: GakujiTopBar.buttonSize,
      height: GakujiTopBar.buttonSize,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            icon,
            size: 28,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}