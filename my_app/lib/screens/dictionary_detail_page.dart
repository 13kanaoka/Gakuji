import 'package:flutter/material.dart';
import '../data/deck_data.dart';
import '../models/deck.dart';
import '../models/term.dart';

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
      decks.firstWhere((d) => d.name == 'Gakuji test deck');

  bool get isSaved {
    return defaultDeck.termIds.contains(widget.word.id);
  }

  void toggleDefaultDeck() {
    setState(() {
      if (isSaved) {
        defaultDeck.termIds.remove(widget.word.id);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from deck')),
        );
      } else {
        defaultDeck.termIds.add(widget.word.id);

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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              final exists = deck.termIds.contains(widget.word.id);

              return ListTile(
                title: Text(deck.name),
                trailing: Icon(
                  exists ? Icons.check : null,
                  color: Colors.green,
                ),
                onTap: () {
                  setState(() {
                    if (!exists) {
                      deck.termIds.add(widget.word.id);
                    }
                  });

                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved to ${deck.name}')),
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
        child: Stack(
          children: [
            /// BACK BUTTON
            Positioned(
              top: 20,
              left: 20,
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new),
                ),
              ),
            ),

            /// ❤️ HEART (dictionary favorite system)
            Positioned(
              top: 28,
              right: 70,
              child: IconButton(
                icon: Icon(
                  isSaved ? Icons.favorite : Icons.favorite_border,
                  color: isSaved ? Colors.red : Colors.grey,
                  size: 30,
                ),
                onPressed: toggleDefaultDeck,
              ),
            ),

            /// 📄 DECK PICKER
            Positioned(
              top: 28,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.menu_book_outlined, size: 30),
                onPressed: openDeckPicker,
              ),
            ),

            /// MAIN KANJI
            Positioned(
              top: 70,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  kanji,
                  style: const TextStyle(
                    fontSize: 78,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),

            /// READING + MEANING
            Positioned(
              top: 200,
              left: 58,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reading, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 18),
                  Text(meaning, style: const TextStyle(fontSize: 24)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}