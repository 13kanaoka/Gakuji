import 'package:flutter/material.dart';

import '../data/deck_data.dart';
import '../models/deck.dart';
import '../models/term.dart';
import '../widgets/gakuji_top_bar.dart';

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

  @override
  Widget build(BuildContext context) {
    final kanji = widget.word.kanji;
    final reading = widget.word.reading;
    final meaning = widget.word.meaning;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            GakujiTopBar(
              leftIcon: Icons.arrow_back_ios_new,
              onLeftTap: () => Navigator.pop(context),
              title: '',
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

            const SizedBox(height: 10),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: [
                    Text(
                      kanji,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 78,
                        fontWeight: FontWeight.w400,
                      ),
                    ),

                    const SizedBox(height: 36),

                    Padding(
                      padding: const EdgeInsets.only(left: 36),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reading,
                              style: const TextStyle(fontSize: 26),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              meaning,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ],
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