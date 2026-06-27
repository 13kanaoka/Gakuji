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
                trailing: Icon(
                  exists ? Icons.check : null,
                  color: Colors.green,
                ),
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
                padding: const EdgeInsets.only(bottom: 96),
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
      padding: const EdgeInsets.fromLTRB(18, 25, 18, 23),
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
                    fontSize: 38,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    word.reading,
                    style: const TextStyle(
                      fontSize: 28,
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
          const SizedBox(height: 28),
          Text(
            word.partOfSpeech,
            style: const TextStyle(
              fontSize: 21,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 5),
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
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey,
                width: 1.7,
              ),
            ),
            child: Center(
              child: Text(
                letter,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 20,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: accentGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Common',
        style: TextStyle(
          fontSize: 15,
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
          padding: const EdgeInsets.fromLTRB(18, 21, 18, 25),
          child: Text(
            word.note ?? 'Write a note',
            style: TextStyle(
              fontSize: 18,
              color: word.note == null ? accentGreen : Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _kanjiSection(Term word) {
    final canOpenKanjiDetails = word.hasKanjiDetails;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Kanji'),
        Material(
          color: Colors.white,
          child: InkWell(
            onTap: canOpenKanjiDetails ? () => openKanjiDetail(word) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 13),
              child: Row(
                children: [
                  SizedBox(
                    width: 59,
                    child: Text(
                      word.kanji.isEmpty ? '' : word.kanji.substring(0, 1),
                      style: const TextStyle(
                        fontSize: 39,
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
                          style: const TextStyle(fontSize: 19),
                        ),
                        if (word.kunyomi.isNotEmpty)
                          Text(
                            word.kunyomi.join(', '),
                            style: const TextStyle(fontSize: 17),
                          ),
                        if (word.onyomi.isNotEmpty)
                          Text(
                            word.onyomi.join(', '),
                            style: const TextStyle(fontSize: 17),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 30,
                    color: canOpenKanjiDetails ? Colors.grey : dividerColor,
                  ),
                ],
              ),
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
            padding: EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: Text(
              'No examples yet',
              style: TextStyle(
                fontSize: 16,
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
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 0),
          child: Text(
            'More Examples',
            style: TextStyle(
              fontSize: 18,
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
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
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
                        fontSize: 13,
                        height: 1.15,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      example.japanese,
                      style: const TextStyle(
                        fontSize: 21,
                        height: 1.3,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      example.english,
                      style: const TextStyle(
                        fontSize: 21,
                        height: 1.18,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 28,
                color: Colors.grey,
              ),
            ],
          ),
          if (showDivider)
            const Padding(
              padding: EdgeInsets.only(top: 15),
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
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 22,
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